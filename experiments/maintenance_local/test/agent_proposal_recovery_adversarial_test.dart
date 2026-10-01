import 'dart:convert';
import 'dart:io';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/agent_service/agent_service.dart';
import 'package:maintenance_local/agent_service/errors.dart';
import 'package:maintenance_local/agent_service/grants.dart';
import 'package:maintenance_local/agent_service/proposal_store.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/local_sync.dart';
import 'package:maintenance_local/model.dart';
import 'package:maintenance_local/office_backup.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';
import 'support/recovery_process_harness.dart';

// Independent filesystem/recovery probes. All stores, grants, staging files and
// optional child processes below belong to newly created synthetic fixtures.
class _Grants implements GrantProvider {
  AgentGrant? grant;
  @override
  Future<AgentGrant?> resolve(String token) async =>
      token == 'synthetic-recovery-token' ? grant : null;
}

// Generated under .dart_tool so Dart run resolves the package's existing native
// assets. The only injected pause is a trusted authorization callback, reached
// after the production store has flushed/protected its stage. The second gate
// is after the unmodified create() has published and flushed its final record.
const _crashChild = r'''
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:maintenance_local/agent_service/proposal_store.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/model.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';

Future<void> main(List<String> args) async {
  final control = Directory(args.single);
  final config = jsonDecode(await File('${control.path}/config.json').readAsString()) as Json;
  await RustLib.init(externalLibrary: ExternalLibrary.open(config['library'] as String));
  final store = await LabStore.open(Directory(config['workspace'] as String), office: true, maintenanceOnly: true);
  final proposals = AgentProposalStore(store.root);
  var authorizations = 0;
  Future<void> gate(String phase) async {
    // An unresolved Future alone does not keep a Dart VM alive. Retain an
    // explicit event source until the parent kills this exact paused process.
    final keepAlive = ReceivePort();
    try {
      await File('${control.path}/ready').writeAsString(
        canonical({'phase': phase, 'pid': pid}), flush: true);
      await Completer<void>().future;
    } finally {
      keepAlive.close();
    }
  }
  await proposals.create(
    grantId: config['grant_id'] as String,
    actorId: config['actor_id'] as String,
    payload: config['payload'] as Json,
    context: config['context'] as Json,
    scope: config['scope'] as Json,
    createdAt: DateTime.parse(config['created_at'] as String),
    authorize: () async {
      if (++authorizations == 2 && config['boundary'] == 'stage-flushed') {
        await gate('stage-flushed');
      }
    },
  );
  await gate('published-no-response');
}
''';

void main() {
  final now = DateTime.utc(2026, 10, 1, 15);
  late Directory root;
  late LabStore store;
  late OfficeIdentity identity;
  late String jobId;
  late _Grants grants;
  late AgentService service;
  late Directory childScripts;
  late File childScript;
  late String nativeLibrary;
  final children = <Process>[];
  final extraChildPids = <int>{};
  const grantId = 'synthetic-recovery-grant';
  const actorId = 'synthetic-recovery-agent';
  const key = '10000000-0000-4000-8000-000000000001';

  AgentGrant grant({
    bool revoked = false,
    bool expired = false,
    Set<String>? commands,
    Set<String>? jobIds,
    Set<String>? equipmentIds,
  }) => AgentGrant(
    id: grantId,
    actorId: actorId,
    workspaceId: 'synthetic-recovery-workspace',
    companyId: store.catalog!['companyId'] as String,
    deviceId: 'synthetic-service-device',
    expiresAt: now.add(Duration(hours: expired ? -1 : 1)),
    commands: commands ?? AgentService.commands,
    revoked: revoked,
    jobIds: jobIds,
    equipmentIds: equipmentIds,
  );
  AgentService openService() => AgentService(
    store: store,
    workspaceId: 'synthetic-recovery-workspace',
    serviceDeviceId: 'synthetic-service-device',
    grants: grants,
    now: () => now,
  );
  Json payload({String idempotencyKey = key}) => {
    'idempotency_key': idempotencyKey,
    'type': 'inspection.notes',
    'job_id': jobId,
    'expected_document_hash': digest(store.documentFor(jobId)!),
    'notes': 'Synthetic unapplied follow-up suggestion',
  };
  Json request(String command, [Json? args]) => {
    'protocol_version': 1,
    'request_id': 'synthetic-recovery-request',
    'scope': {
      'workspace_id': 'synthetic-recovery-workspace',
      'company_id': store.catalog!['companyId'],
      'device_id': 'synthetic-service-device',
    },
    'credential': {'token': 'synthetic-recovery-token'},
    'command': command,
    'args': args ?? <String, dynamic>{},
  };
  File published([String idempotencyKey = key]) => File(
    '${service.proposals.root.path}/${contentHash([grantId, idempotencyKey])}.json',
  );
  Future<void> mode(String path, String permission) async => expect(
    (await Process.run('/usr/bin/chmod', [permission, '--', path])).exitCode,
    0,
  );
  String tables() => canonical({
    for (final table in [
      'settings',
      'documents',
      'submissions',
      'receipts',
      'events',
      'phones',
      'invites',
    ])
      table: store.db
          .select('SELECT * FROM $table')
          .map((row) => Map<String, dynamic>.from(row))
          .toList(),
  });
  Future<String> databaseBytes() async => canonical({
    for (final name in [
      'workspace.sqlite',
      'workspace.sqlite-wal',
      'workspace.sqlite-shm',
    ])
      if (await File('${store.root.path}/$name').exists())
        name: digest(await File('${store.root.path}/$name').readAsBytes()),
  });
  Future<String> sourceBytes() async => canonical({
    'db': await databaseBytes(),
    'tables': tables(),
    'documents': {
      for (final job in store.jobs)
        job['id']: digest(store.documentFor(job['id'] as String)!),
    },
    'submissions': store.submissions,
    'receipts': store.receipts,
    'key': digest(
      await File('${store.root.path}/office-key.pem').readAsBytes(),
    ),
    // Include evidence, ownership marker and certificate, and detect added or
    // removed application files. Only proposal sidecars are outside this proof.
    'files': {
      for (final entry
          in await store.root
              .list(recursive: true, followLinks: false)
              .toList())
        if (entry is File &&
            !entry.path.startsWith('${store.root.path}/agent-proposals-v1/'))
          entry.path.substring(store.root.path.length + 1): digest(
            await entry.readAsBytes(),
          ),
    },
  });
  void rejected(Json response, String code) {
    expect(response['ok'], false);
    expect(response['error']['code'], code);
    expect(response['error']['retryable'], false);
    final encoded = canonical(response);
    expect(encoded, isNot(contains(root.path)));
    expect(encoded, isNot(contains('synthetic-recovery-token')));
    expect(encoded, isNot(contains('office-key.pem')));
  }

  Future<void> signRecord(File file, void Function(Json) mutation) async {
    final record = jsonDecode(await file.readAsString()) as Json;
    mutation(record);
    record.remove('hash');
    record['hash'] = contentHash(record);
    await file.writeAsString(canonical(record), flush: true);
  }

  Future<void> crashAt(String boundary, Json candidate) async {
    final control = await Directory('${root.path}/child-$boundary').create();
    await File('${control.path}/config.json').writeAsString(
      canonical({
        'library': nativeLibrary,
        'workspace': store.root.path,
        'grant_id': grantId,
        'actor_id': actorId,
        'payload': candidate,
        'context': store.jobContextFor(jobId),
        'scope': request('proposals.create')['scope'],
        'created_at': now.toIso8601String(),
        'boundary': boundary,
      }),
      flush: true,
    );
    await store.close();
    try {
      final child = await Process.start(
        RecoveryProcess.dart,
        ['--suppress-analytics', 'run', childScript.path, control.path],
        environment: {'MAINTENANCE_NATIVE_LIBRARY': nativeLibrary},
      );
      children.add(child);
      final output = child.stdout.transform(utf8.decoder).join();
      final errors = child.stderr.transform(utf8.decoder).join();
      final ready = File('${control.path}/ready');
      final deadline = DateTime.now().add(const Duration(seconds: 25));
      while (!await ready.exists() && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      if (!await ready.exists()) {
        child.kill(ProcessSignal.sigkill);
        await child.exitCode.timeout(const Duration(seconds: 5));
        fail('Child did not reach its crash gate: ${await errors}');
      }
      final gate = jsonDecode(await ready.readAsString()) as Json;
      final actualPid = gate['pid'] as int;
      if (actualPid != child.pid) extraChildPids.add(actualPid);
      expect(gate['phase'], boundary);
      expect(
        actualPid,
        child.pid,
        reason: 'The gate must belong to the exact process being killed.',
      );
      expect(child.kill(ProcessSignal.sigkill), true);
      expect(await child.exitCode.timeout(const Duration(seconds: 5)), -9);
      expect(
        await Directory('/proc/$actualPid').exists(),
        false,
        reason: 'The killed child must be reaped without an orphan VM.',
      );
      final diagnostic = await errors.timeout(const Duration(seconds: 5));
      expect(await ready.exists(), true, reason: diagnostic);
      expect(await output, isEmpty);
      // Dart's cached native-assets runner emits this fixed progress message.
      // The child itself emits neither a response nor private record content.
      expect(
        diagnostic.replaceAll('Running build hooks...', '').trim(),
        isEmpty,
      );
      children.remove(child);
    } finally {
      store = await LabStore.open(
        Directory('${root.path}/office'),
        office: true,
        maintenanceOnly: true,
      );
      service = openService();
    }
  }

  setUpAll(() async {
    final library = File(
      Platform.environment['MAINTENANCE_NATIVE_LIBRARY'] ??
          '../../work/native/librust_lib_sync_lab.so',
    );
    nativeLibrary = library.absolute.path;
    // A private copy is provided by the fixture owner, never a live app binary.
    await RustLib.init(
      externalLibrary: ExternalLibrary.open(library.absolute.path),
    );
    childScripts = await Directory(
      '.dart_tool',
    ).createTemp('proposal-recovery-');
    childScript = await File(
      '${childScripts.absolute.path}/crash_child.dart',
    ).writeAsString(_crashChild, flush: true);
  });
  tearDownAll(() => childScripts.delete(recursive: true));
  setUp(() async {
    root = await Directory.systemTemp.createTemp('agent-proposal-recovery-');
    store = await LabStore.open(
      Directory('${root.path}/office'),
      office: true,
      maintenanceOnly: true,
    );
    await store.createCompany(
      'Synthetic proposal recovery company',
      coordinatorName: 'Synthetic coordinator',
    );
    identity = await OfficeIdentity.load(store);
    final equipment = await store.addEquipment(
      name: 'Synthetic inspection equipment',
      meterUnit: 'none',
    );
    final template = await store.publishChecklist(
      title: 'Synthetic private procedure',
      items: [
        {'id': 'guard', 'label': 'Inspect guard', 'input_type': 'check'},
      ],
    );
    jobId =
        (await store.prepareWork(
              equipmentId: equipment['id'] as String,
              templateId: template['id'] as String,
              title: 'Synthetic proposal inspection',
            ))['id']
            as String;
    await store.update({
      'answer:guard': {'result': 'action', 'value': ''},
      'notes': 'Original committed inspection findings',
    }, jobId: jobId);
    await store.attach([1, 2, 3, 4], jobId: jobId);
    final submission = await store.submit(jobId: jobId);
    await store.decide(submission['id'] as String, approve: true);
    grants = _Grants()..grant = grant();
    service = openService();
  });
  tearDown(() async {
    for (final childPid in extraChildPids) {
      Process.killPid(childPid, ProcessSignal.sigkill);
    }
    extraChildPids.clear();
    for (final child in children) {
      child.kill(ProcessSignal.sigkill);
      await child.exitCode.timeout(const Duration(seconds: 5));
    }
    children.clear();
    await store.close();
    await root.delete(recursive: true);
  });

  test(
    'SIGKILL after flushed staging leaves an inert orphan and restart publishes once',
    () async {
      final candidate = payload();
      final originalTables = tables();
      final originalDocument = store.documentFor(jobId)!;
      await crashAt('stage-flushed', candidate);
      expect(tables(), originalTables);
      expect(store.documentFor(jobId), originalDocument);
      expect(await published().exists(), false);
      final orphan =
          (await service.proposals.root.list().toList()).single as File;
      expect(orphan.uri.pathSegments.last, startsWith('.pending-'));
      final staged = await orphan.readAsBytes();
      expect((orphan.statSync().mode & 0xfff), 0x180);
      expect(jsonDecode(utf8.decode(staged))['payload'], candidate);
      expect(await service.proposals.records(), isEmpty);
      final before = await sourceBytes();
      final created = await service.handle(
        request('proposals.create', candidate),
      );
      expect(created['ok'], true);
      expect(await service.proposals.records(), hasLength(1));
      expect(await orphan.readAsBytes(), staged);
      expect(await sourceBytes(), before);
      final retry = await service.handle(
        request('proposals.create', candidate),
      );
      expect(canonical(retry['result']), canonical(created['result']));
      expect(await service.proposals.records(), hasLength(1));
    },
  );

  test(
    'SIGKILL after publication and lost response replays the exact durable result',
    () async {
      final candidate = payload();
      final originalTables = tables();
      final originalDocument = store.documentFor(jobId)!;
      await crashAt('published-no-response', candidate);
      expect(tables(), originalTables);
      expect(store.documentFor(jobId), originalDocument);
      final file = published();
      final committed = await file.readAsBytes();
      final recordedResult = jsonDecode(utf8.decode(committed))['result'];
      final before = await sourceBytes();
      grants.grant = grant(revoked: true);
      rejected(
        await service.handle(request('proposals.create', candidate)),
        'grant_revoked',
      );
      grants.grant = grant();
      final replay = await service.handle(
        request('proposals.create', candidate),
      );
      expect(replay['ok'], true);
      expect(canonical(replay['result']['item']), canonical(recordedResult));
      expect(await service.proposals.records(), hasLength(1));
      expect(await file.readAsBytes(), committed);
      expect((await service.proposals.root.list().toList()), hasLength(1));
      expect(await sourceBytes(), before);
    },
  );

  test(
    'partial and flushed unpublished stages remain inert across actual store restart',
    () async {
      final original = payload();
      final created = await service.handle(
        request('proposals.create', original),
      );
      expect(created['ok'], true);
      final file = published();
      final committed = await file.readAsBytes();
      final partial = File('${service.proposals.root.path}/.pending-truncated');
      await partial.writeAsString(
        '{"grant_id":"synthetic-secret-staged-only"',
        flush: true,
      );
      await mode(partial.path, '600');
      final flushed = File(
        '${service.proposals.root.path}/.pending-complete-unpublished',
      );
      await flushed.writeAsBytes(committed, flush: true);
      await mode(flushed.path, '600');
      await store.close();
      store = await LabStore.open(
        Directory('${root.path}/office'),
        office: true,
        maintenanceOnly: true,
      );
      service = openService();
      final before = await sourceBytes();
      final replay = await service.handle(
        request('proposals.create', original),
      );
      expect(canonical(replay['result']), canonical(created['result']));
      final listed = await service.handle(request('proposals.list'));
      expect(listed['result']['items'], hasLength(1));
      expect(
        canonical(listed),
        isNot(contains('synthetic-secret-staged-only')),
      );
      expect(await service.proposals.records(), hasLength(1));
      expect(await file.readAsBytes(), committed);
      expect(
        await partial.readAsString(),
        '{"grant_id":"synthetic-secret-staged-only"',
      );
      expect(await flushed.readAsBytes(), committed);
      expect(await sourceBytes(), before);
    },
  );

  test(
    'authorization rejects before reading a corrupt exact replay record',
    () async {
      final original = payload();
      await service.handle(request('proposals.create', original));
      final file = published();
      await file.writeAsString('{broken-synthetic-private-record', flush: true);
      final before = await sourceBytes();
      for (final entry in [
        (null, 'unauthorized'),
        (grant(revoked: true), 'grant_revoked'),
        (grant(expired: true), 'grant_expired'),
        (grant(commands: {'capabilities'}), 'permission_denied'),
        (grant(jobIds: {}), 'not_found'),
        (grant(equipmentIds: {}), 'not_found'),
      ]) {
        grants.grant = entry.$1;
        rejected(
          await service.handle(request('proposals.create', original)),
          entry.$2,
        );
        expect(await file.readAsString(), '{broken-synthetic-private-record');
        expect(await sourceBytes(), before);
      }
      grants.grant = grant();
      for (final scopeKey in ['workspace_id', 'company_id', 'device_id']) {
        final mismatched = request('proposals.create', original);
        mismatched['scope'][scopeKey] = 'other-synthetic-scope';
        rejected(await service.handle(mismatched), 'scope_mismatch');
        expect(await file.readAsString(), '{broken-synthetic-private-record');
        expect(await sourceBytes(), before);
      }
      rejected(
        await service.handle(request('proposals.create', original)),
        'internal_error',
      );
      expect(await sourceBytes(), before);
    },
  );

  test(
    'authorized alternate service scope cannot replay an existing same-grant same-key record',
    () async {
      final original = payload();
      final created = await service.handle(
        request('proposals.create', original),
      );
      expect(created['ok'], true);
      final committed = await published().readAsBytes();
      final before = await sourceBytes();
      grants.grant = AgentGrant(
        id: grantId,
        actorId: actorId,
        workspaceId: 'other-synthetic-workspace',
        companyId: store.catalog!['companyId'] as String,
        deviceId: 'other-synthetic-service-device',
        expiresAt: now.add(const Duration(hours: 1)),
        commands: AgentService.commands,
      );
      final alternate = AgentService(
        store: store,
        workspaceId: 'other-synthetic-workspace',
        serviceDeviceId: 'other-synthetic-service-device',
        grants: grants,
        now: () => now,
      );
      final alternateRequest = request('proposals.create', original);
      alternateRequest['scope']['workspace_id'] = 'other-synthetic-workspace';
      alternateRequest['scope']['device_id'] = 'other-synthetic-service-device';
      rejected(
        await alternate.handle(alternateRequest),
        'idempotency_conflict',
      );
      expect(await published().readAsBytes(), committed);
      expect(await sourceBytes(), before);
      grants.grant = grant();
      final replay = await service.handle(
        request('proposals.create', original),
      );
      expect(canonical(replay['result']), canonical(created['result']));
      expect(await service.proposals.records(), hasLength(1));
      expect(await sourceBytes(), before);
    },
  );

  test(
    'well-hashed frozen context and result corruption are rejected without repair or disclosure',
    () async {
      await service.handle(request('proposals.create', payload()));
      final file = published();
      final committed = await file.readAsBytes();
      final before = await sourceBytes();
      final mutations = <void Function(Json)>[
        (r) => r['context']['checklistSnapshot']['items'][0]['label'] =
            'Tampered definition',
        (r) => r['result']['applied'] = true,
        (r) => r['result']['notes'] = 'PRIVATE CORRUPT RECORD TEXT',
        (r) => r['result']['requires_human_review'] = false,
        (r) => r['result']['status'] = 'approved',
        (r) => r['result']['local_only'] = false,
        (r) => r['result']['backup_included'] = true,
        (r) => r['result']['human_review_available'] = true,
        (r) => r['scope']['unexpected'] = 'PRIVATE CORRUPT RECORD TEXT',
        (r) => r['command'] = 'inspection.apply',
        (r) => r['version'] = 1,
      ];
      for (final mutation in mutations) {
        await file.writeAsBytes(committed, flush: true);
        await signRecord(file, mutation);
        final damaged = await file.readAsBytes();
        final response = await service.handle(request('proposals.list'));
        rejected(response, 'internal_error');
        expect(
          canonical(response),
          isNot(contains('PRIVATE CORRUPT RECORD TEXT')),
        );
        expect(await file.readAsBytes(), damaged);
        expect(await sourceBytes(), before);
      }
    },
  );

  test(
    'oversized persisted sidecar is rejected and preserved without loading or repairing its contents',
    () async {
      final original = payload();
      await service.handle(request('proposals.create', original));
      final file = published();
      await file.writeAsBytes(
        List.filled(AgentProposalStore.maxRecordBytes + 1, 0x20),
        flush: true,
      );
      final corruptHash = digest(await file.readAsBytes());
      final before = await sourceBytes();
      rejected(
        await service.handle(request('proposals.create', original)),
        'internal_error',
      );
      rejected(
        await service.handle(request('proposals.list')),
        'internal_error',
      );
      expect(await file.length(), AgentProposalStore.maxRecordBytes + 1);
      expect(digest(await file.readAsBytes()), corruptHash);
      expect(await sourceBytes(), before);
    },
  );

  test(
    'published ordinary/dangling links and unsafe modes fail closed without clobbering targets',
    () async {
      final original = payload();
      await service.handle(request('proposals.create', original));
      final target = published();
      final committed = await target.readAsBytes();
      final external = File('${root.path}/outside-record')
        ..writeAsBytesSync(committed, flush: true);
      await mode(external.path, '600');
      final before = await sourceBytes();
      for (final destination in [external.path, '${root.path}/absent-record']) {
        await target.delete();
        await Link(target.path).create(destination);
        rejected(
          await service.handle(request('proposals.create', original)),
          'internal_error',
        );
        expect(Link(target.path).targetSync(), destination);
        expect(await external.readAsBytes(), committed);
        expect(await File('${root.path}/absent-record').exists(), false);
        expect(await sourceBytes(), before);
        await Link(target.path).delete();
        await target.writeAsBytes(committed, flush: true);
        await mode(target.path, '600');
      }
      await mode(target.path, '644');
      final modeBefore = target.statSync().mode;
      rejected(
        await service.handle(request('proposals.create', original)),
        'internal_error',
      );
      expect(target.statSync().mode, modeBefore);
      expect(await target.readAsBytes(), committed);
      await mode(target.path, '600');
      await mode(service.proposals.root.path, '755');
      final rootMode = service.proposals.root.statSync().mode;
      rejected(
        await service.handle(request('proposals.create', original)),
        'internal_error',
      );
      expect(service.proposals.root.statSync().mode, rootMode);
      expect(await sourceBytes(), before);
    },
  );

  test(
    'collision arriving after flushed staging is preserved byte-for-byte',
    () async {
      final candidate = payload();
      final proposals = service.proposals;
      final before = await sourceBytes();
      var authorizations = 0;
      await expectLater(
        proposals.create(
          grantId: grantId,
          actorId: actorId,
          payload: candidate,
          context: store.jobContextFor(jobId),
          scope: request('proposals.create')['scope'] as Json,
          createdAt: now,
          authorize: () async {
            if (++authorizations == 2) {
              expect(
                (await proposals.root.list().toList())
                    .whereType<File>()
                    .single
                    .path,
                contains('.pending-'),
              );
              await published().writeAsString(
                'UNRELATED DESTINATION MUST SURVIVE',
                flush: true,
              );
              await mode(published().path, '600');
            }
          },
        ),
        throwsException,
      );
      expect(
        await published().readAsString(),
        'UNRELATED DESTINATION MUST SURVIVE',
      );
      rejected(
        await service.handle(request('proposals.create', candidate)),
        'internal_error',
      );
      expect(
        (await proposals.root.list().toList()).where(
          (f) => f.uri.pathSegments.last.startsWith('.pending-'),
        ),
        isEmpty,
      );
      expect(await sourceBytes(), before);
    },
  );

  test(
    'final authorization failure removes only own stage and retains prior orphan stages',
    () async {
      await service.proposals.root.create();
      await mode(service.proposals.root.path, '700');
      final orphan = File(
        '${service.proposals.root.path}/.pending-earlier-crash',
      )..writeAsStringSync('preserved orphan', flush: true);
      await mode(orphan.path, '600');
      final before = await sourceBytes();
      var checks = 0;
      await expectLater(
        service.proposals.create(
          grantId: grantId,
          actorId: actorId,
          payload: payload(),
          context: store.jobContextFor(jobId),
          scope: request('proposals.create')['scope'] as Json,
          createdAt: now,
          authorize: () async {
            if (++checks == 2) throw const AgentFailure('grant_revoked');
          },
        ),
        throwsA(
          isA<AgentFailure>().having((e) => e.code, 'code', 'grant_revoked'),
        ),
      );
      expect(await orphan.readAsString(), 'preserved orphan');
      expect(await published().exists(), false);
      expect((await service.proposals.root.list().toList()).length, 1);
      expect(await sourceBytes(), before);
    },
  );

  test(
    'root replacement after flushed staging fails closed without publishing through a symlink',
    () async {
      final proposals = service.proposals;
      final candidate = payload();
      final before = await sourceBytes();
      final displaced = Directory('${root.path}/displaced-private-proposals');
      var authorizations = 0;
      await expectLater(
        proposals.create(
          grantId: grantId,
          actorId: actorId,
          payload: candidate,
          context: store.jobContextFor(jobId),
          scope: request('proposals.create')['scope'] as Json,
          createdAt: now,
          authorize: () async {
            if (++authorizations == 2) {
              expect(
                (await proposals.root.list().toList()).single.path,
                contains('.pending-'),
              );
              await proposals.root.rename(displaced.path);
              await Link(proposals.root.path).create(displaced.path);
            }
          },
        ),
        throwsA(
          isA<AgentFailure>().having(
            (failure) => failure.code,
            'code',
            'internal_error',
          ),
        ),
      );
      expect(Link(proposals.root.path).targetSync(), displaced.path);
      expect(await published().exists(), false);
      expect(
        (await displaced.list().toList()).where(
          (entry) => entry.path.endsWith('.json'),
        ),
        isEmpty,
      );
      rejected(
        await service.handle(request('proposals.create', candidate)),
        'internal_error',
      );
      expect(await sourceBytes(), before);
    },
  );

  test(
    'ordinary root inode replacement preserves displaced and foreign stages without publishing',
    () async {
      final proposals = service.proposals;
      final before = await sourceBytes();
      final displaced = Directory('${root.path}/displaced-ordinary-proposals');
      late File originalStage, foreignStage;
      late List<int> originalBytes;
      var authorizations = 0;
      await expectLater(
        proposals.create(
          grantId: grantId,
          actorId: actorId,
          payload: payload(),
          context: store.jobContextFor(jobId),
          scope: request('proposals.create')['scope'] as Json,
          createdAt: now,
          authorize: () async {
            if (++authorizations == 2) {
              final stage =
                  (await proposals.root.list().toList()).single as File;
              originalBytes = await stage.readAsBytes();
              final name = stage.uri.pathSegments.last;
              await proposals.root.rename(displaced.path);
              originalStage = File('${displaced.path}/$name');
              await proposals.root.create();
              await mode(proposals.root.path, '700');
              foreignStage = File('${proposals.root.path}/$name');
              await foreignStage.writeAsString(
                'FOREIGN STAGE MUST SURVIVE',
                flush: true,
              );
              await mode(foreignStage.path, '600');
            }
          },
        ),
        throwsA(
          isA<AgentFailure>().having(
            (failure) => failure.code,
            'code',
            'internal_error',
          ),
        ),
      );
      expect(await published().exists(), false);
      expect(await originalStage.readAsBytes(), originalBytes);
      expect(await foreignStage.readAsString(), 'FOREIGN STAGE MUST SURVIVE');
      expect(await service.proposals.records(), isEmpty);
      expect(await sourceBytes(), before);
    },
  );

  test(
    'strict backup and normal restore ignore corrupt proposals and unpublished stages',
    () async {
      await service.handle(request('proposals.create', payload()));
      await published().writeAsString('CORRUPT LOCAL PROPOSAL', flush: true);
      final stage = File('${service.proposals.root.path}/.pending-backup-crash')
        ..writeAsStringSync('UNPUBLISHED PRIVATE SUGGESTION', flush: true);
      await mode(stage.path, '600');
      final originalTables = tables();
      final originalSubmissions = canonical(store.submissions);
      final originalReceipts = canonical(store.receipts);
      final originalSubmissionRows = canonical(
        store.db
            .select('SELECT * FROM submissions')
            .map((row) => Map<String, dynamic>.from(row))
            .toList(),
      );
      final originalReceiptRows = canonical(
        store.db
            .select('SELECT * FROM receipts')
            .map((row) => Map<String, dynamic>.from(row))
            .toList(),
      );
      final originalEvidence = canonical({
        for (final entry in await store.evidence.root.list().toList())
          if (entry is File)
            entry.uri.pathSegments.last: digest(await entry.readAsBytes()),
      });
      final originalDoc = store.documentFor(jobId)!;
      final backup = Directory('${root.path}/backup');
      final summary = await OfficeBackup.create(store, backup);
      expect(summary.submissions, 1);
      expect(summary.receipts, 1);
      await OfficeBackup.inspect(
        backup,
        requiredFormat: OfficeBackupFormat.maintenance,
      );
      expect(
        await Directory('${backup.path}/agent-proposals-v1').exists(),
        false,
      );
      expect(await published().readAsString(), 'CORRUPT LOCAL PROPOSAL');
      expect(await stage.readAsString(), 'UNPUBLISHED PRIVATE SUGGESTION');
      expect(tables(), originalTables);
      await OfficeBackup.restore(
        backup,
        Directory('${root.path}/restored'),
        expectedFingerprint: identity.fingerprint,
        requiredFormat: OfficeBackupFormat.maintenance,
      );
      final restored = await LabStore.open(
        Directory('${root.path}/restored'),
        office: true,
        maintenanceOnly: true,
      );
      try {
        expect(restored.documentFor(jobId), originalDoc);
        expect(canonical(restored.submissions), originalSubmissions);
        expect(canonical(restored.receipts), originalReceipts);
        expect(
          canonical(
            restored.db
                .select('SELECT * FROM submissions')
                .map((row) => Map<String, dynamic>.from(row))
                .toList(),
          ),
          originalSubmissionRows,
        );
        expect(
          canonical(
            restored.db
                .select('SELECT * FROM receipts')
                .map((row) => Map<String, dynamic>.from(row))
                .toList(),
          ),
          originalReceiptRows,
        );
        expect(
          canonical({
            for (final entry in await restored.evidence.root.list().toList())
              if (entry is File)
                entry.uri.pathSegments.last: digest(await entry.readAsBytes()),
          }),
          originalEvidence,
        );
        expect(await AgentProposalStore(restored.root).records(), isEmpty);
        expect(
          await Directory('${restored.root.path}/agent-proposals-v1').exists(),
          false,
        );
      } finally {
        await restored.close();
      }
    },
  );
}
