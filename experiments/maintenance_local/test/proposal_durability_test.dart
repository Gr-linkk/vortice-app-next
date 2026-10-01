import 'dart:async';
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/agent_service/agent_service.dart';
import 'package:maintenance_local/agent_service/errors.dart';
import 'package:maintenance_local/agent_service/grants.dart';
import 'package:maintenance_local/agent_service/proposal_store.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/model.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';

class _Grants implements GrantProvider {
  late AgentGrant grant;
  Future<void> Function()? beforeResolve;
  @override
  Future<AgentGrant?> resolve(String token) async {
    await beforeResolve?.call();
    return token == 'synthetic-token' ? grant : null;
  }
}

void main() {
  setUpAll(
    () => RustLib.init(
      externalLibrary: ExternalLibrary.open(
        Platform.environment['MAINTENANCE_NATIVE_LIBRARY']!,
      ),
    ),
  );
  late Directory fixture;
  late LabStore store;
  late String job, equipment;
  late _Grants grants;
  final clock = DateTime.utc(2026, 10, 1, 12);
  AgentGrant authority({
    bool revoked = false,
    Set<String>? jobs,
    Set<String>? equipmentIds,
    String actor = 'synthetic-agent',
  }) => AgentGrant(
    id: 'synthetic-grant',
    actorId: actor,
    workspaceId: 'synthetic-workspace',
    companyId: store.catalog!['companyId'] as String,
    deviceId: 'synthetic-service',
    expiresAt: clock.add(const Duration(hours: 1)),
    commands: AgentService.commands,
    revoked: revoked,
    jobIds: jobs ?? {job},
    equipmentIds: equipmentIds ?? {equipment},
  );
  Json scope() => {
    'workspace_id': 'synthetic-workspace',
    'company_id': store.catalog!['companyId'],
    'device_id': 'synthetic-service',
  };
  Json payload() => {
    'idempotency_key': '11111111-1111-4111-8111-111111111111',
    'type': 'inspection.notes',
    'job_id': job,
    'expected_document_hash': digest(store.documentFor(job)!),
    'notes': 'Synthetic proposal remains pending.',
  };
  Json request(Json args, [String id = 'initial-create']) => {
    'protocol_version': 1,
    'request_id': id,
    'scope': scope(),
    'credential': {'token': 'synthetic-token'},
    'command': 'proposals.create',
    'args': args,
  };
  AgentService service(AgentProposalStore proposals) => AgentService(
    store: store,
    workspaceId: 'synthetic-workspace',
    serviceDeviceId: 'synthetic-service',
    grants: grants,
    now: () => clock,
    proposals: proposals,
  );
  String nativeState() => canonical({
    for (final table in [
      'settings',
      'documents',
      'submissions',
      'receipts',
      'invites',
      'phones',
      'events',
    ])
      table: store.db
          .select('SELECT * FROM $table')
          .map((row) => Map<String, dynamic>.from(row))
          .toList(),
  });
  Future<File> proposalFile(AgentProposalStore proposals) async =>
      (await proposals.root
              .list()
              .where((entry) => entry is File)
              .cast<File>()
              .toList())
          .single;
  void unknown(Json result) {
    expect(result['ok'], false);
    expect(result['error']['code'], 'internal_error');
    expect(result['error']['outcome'], 'unknown');
    expect(result.containsKey('result'), false);
  }

  Future<Json> directCreate(
    AgentProposalStore proposals,
    Json args, {
    Future<void> Function()? authorize,
    Future<void> Function()? validateContext,
  }) => proposals.create(
    grantId: grants.grant.id,
    actorId: grants.grant.actorId,
    payload: args,
    context: store.jobContextFor(job),
    scope: scope(),
    createdAt: clock,
    authorize: authorize ?? () async {},
    validateContext: validateContext,
  );

  setUp(() async {
    fixture = await Directory.systemTemp.createTemp(
      'proposal-durability-synthetic-',
    );
    store = await LabStore.open(
      Directory('${fixture.path}/office'),
      office: true,
      maintenanceOnly: true,
    );
    await store.createCompany('Synthetic durability company');
    equipment =
        (await store.addEquipment(
              name: 'Synthetic equipment',
              meterUnit: 'none',
            ))['id']
            as String;
    final procedure =
        (await store.publishChecklist(
              title: 'Synthetic inspection',
              items: [
                {
                  'id': 'guard',
                  'label': 'Inspect guard',
                  'input_type': 'check',
                },
              ],
            ))['id']
            as String;
    job =
        (await store.prepareWork(
              equipmentId: equipment,
              templateId: procedure,
              title: 'Synthetic job',
            ))['id']
            as String;
    grants = _Grants()..grant = authority();
  });
  tearDown(() async {
    await store.close();
    await fixture.delete(recursive: true);
  });

  test(
    'persistent directory flush failure keeps every service retry unknown',
    () async {
      var flushes = 0;
      final proposals = AgentProposalStore.forSyntheticTest(
        store.root,
        flushDirectory: (_) {
          flushes++;
          return 1;
        },
      );
      final agent = service(proposals),
          args = payload(),
          before = nativeState();
      unknown(await agent.handle(request(args)));
      expect(flushes, 1);
      final file = await proposalFile(proposals),
          bytes = await file.readAsBytes();
      for (var attempt = 1; attempt <= 3; attempt++) {
        unknown(await agent.handle(request(args, 'retry-$attempt')));
        expect(flushes, attempt + 1);
        expect(await file.readAsBytes(), bytes);
        expect(await proposals.records(), hasLength(1));
        expect(nativeState(), before);
      }
    },
  );

  test(
    'later successful flush acknowledges original immutable result only',
    () async {
      var flushes = 0, failure = true;
      final proposals = AgentProposalStore.forSyntheticTest(
        store.root,
        flushDirectory: (_) {
          flushes++;
          return failure ? 1 : 0;
        },
      );
      final agent = service(proposals),
          args = payload(),
          before = nativeState();
      unknown(await agent.handle(request(args)));
      final record = (await proposals.records()).single;
      final file = await proposalFile(proposals),
          bytes = await file.readAsBytes();
      failure = false;
      final retry = await agent.handle(request(args, 'retry-after-flush'));
      expect(retry['ok'], true);
      expect(retry['request_id'], 'retry-after-flush');
      expect(retry['result']['item'], record['result']);
      expect(flushes, 2);
      expect(await file.readAsBytes(), bytes);
      expect(nativeState(), before);
      final exact = await agent.handle(request(args, 'another-exact-retry'));
      expect(exact['result']['item'], record['result']);
      expect(flushes, 3);
      expect(await proposals.records(), hasLength(1));
    },
  );

  test(
    'restarted service cannot turn visible failed-flush state into success',
    () async {
      var initialFlushes = 0, retryFlushes = 0, failure = true;
      final initial = AgentProposalStore.forSyntheticTest(
        store.root,
        flushDirectory: (_) {
          initialFlushes++;
          return 1;
        },
      );
      final args = payload();
      unknown(await service(initial).handle(request(args)));
      final file = await proposalFile(initial),
          bytes = await file.readAsBytes();
      final original = (await initial.records()).single['result'];
      final workspace = store.root;
      await store.close();
      store = await LabStore.open(
        workspace,
        office: true,
        maintenanceOnly: true,
      );
      final before = nativeState();
      final restarted = AgentProposalStore.forSyntheticTest(
        store.root,
        flushDirectory: (_) {
          retryFlushes++;
          return failure ? 1 : 0;
        },
      );
      final agent = service(restarted);
      unknown(await agent.handle(request(args, 'retry-after-restart')));
      expect(initialFlushes, 1);
      expect(retryFlushes, 1);
      failure = false;
      final success = await agent.handle(request(args, 'retry-after-recovery'));
      expect(success['ok'], true);
      expect(success['result']['item'], original);
      expect(retryFlushes, 2);
      expect(await file.readAsBytes(), bytes);
      expect(nativeState(), before);
    },
  );

  test(
    'store existing-record creation also confirms every replay flush',
    () async {
      var flushes = 0, failure = true;
      final proposals = AgentProposalStore.forSyntheticTest(
        store.root,
        flushDirectory: (_) {
          flushes++;
          return failure ? 1 : 0;
        },
      );
      final args = payload(), before = nativeState();
      await expectLater(
        directCreate(proposals, args),
        throwsA(
          isA<AgentFailure>().having(
            (error) => error.code,
            'code',
            'internal_error',
          ),
        ),
      );
      final original = (await proposals.records()).single['result'];
      final file = await proposalFile(proposals),
          bytes = await file.readAsBytes();
      await expectLater(
        directCreate(proposals, args),
        throwsA(
          isA<AgentFailure>().having(
            (error) => error.code,
            'code',
            'internal_error',
          ),
        ),
      );
      expect(flushes, 2);
      failure = false;
      expect(await directCreate(proposals, args), original);
      expect(flushes, 3);
      expect(await file.readAsBytes(), bytes);
      expect(nativeState(), before);
    },
  );

  test(
    'no-clobber collision confirms durability of the winning original',
    () async {
      var flushes = 0, failure = true;
      final proposals = AgentProposalStore.forSyntheticTest(
        store.root,
        flushDirectory: (_) {
          flushes++;
          return failure ? 1 : 0;
        },
      );
      final winner = AgentProposalStore.forSyntheticTest(
        store.root,
        flushDirectory: (_) => 0,
      );
      final args = payload(), before = nativeState();
      Json? original;
      await expectLater(
        directCreate(
          proposals,
          args,
          validateContext: () async {
            original = await directCreate(winner, args);
          },
        ),
        throwsA(
          isA<AgentFailure>().having(
            (error) => error.code,
            'code',
            'internal_error',
          ),
        ),
      );
      expect(flushes, 1);
      expect((await proposals.records()).single['result'], original);
      final file = await proposalFile(proposals),
          bytes = await file.readAsBytes();
      failure = false;
      expect(await directCreate(proposals, args), original);
      expect(flushes, 2);
      expect(await file.readAsBytes(), bytes);
      expect(await proposals.root.list().toList(), hasLength(1));
      expect(nativeState(), before);
    },
  );

  test(
    'revocation during replay final authorization rejects retry without losing record',
    () async {
      var flushes = 0, failure = true;
      final proposals = AgentProposalStore.forSyntheticTest(
        store.root,
        flushDirectory: (_) {
          flushes++;
          return failure ? 1 : 0;
        },
      );
      final agent = service(proposals),
          args = payload(),
          before = nativeState();
      unknown(await agent.handle(request(args)));
      final file = await proposalFile(proposals),
          bytes = await file.readAsBytes();
      failure = false;
      final finalAuthorization = Completer<void>(), release = Completer<void>();
      grants.beforeResolve = () async {
        if (flushes == 2) {
          if (!finalAuthorization.isCompleted) finalAuthorization.complete();
          await release.future;
        }
      };
      final retry = agent.handle(request(args, 'revoked-during-retry'));
      await finalAuthorization.future.timeout(const Duration(seconds: 5));
      grants.grant = authority(revoked: true);
      release.complete();
      final denied = await retry;
      expect(denied['ok'], false);
      expect(denied['error']['code'], 'grant_revoked');
      expect(denied['error']['outcome'], 'rejected');
      expect(flushes, 2);
      expect(await file.readAsBytes(), bytes);
      expect(nativeState(), before);
    },
  );

  test(
    'initial post-publication revocation remains unknown after record commit',
    () async {
      var flushes = 0;
      final proposals = AgentProposalStore.forSyntheticTest(
        store.root,
        flushDirectory: (_) {
          flushes++;
          grants.grant = authority(revoked: true);
          return 0;
        },
      );
      final before = nativeState();
      unknown(await service(proposals).handle(request(payload())));
      expect(flushes, 1);
      expect(await proposals.records(), hasLength(1));
      expect(nativeState(), before);
    },
  );

  test(
    'changed scope, filters, actor and payload cannot acknowledge old result',
    () async {
      var flushes = 0, failure = true;
      final proposals = AgentProposalStore.forSyntheticTest(
        store.root,
        flushDirectory: (_) {
          flushes++;
          return failure ? 1 : 0;
        },
      );
      final agent = service(proposals),
          args = payload(),
          before = nativeState();
      unknown(await agent.handle(request(args)));
      final file = await proposalFile(proposals),
          bytes = await file.readAsBytes();
      failure = false;
      final changed = Map<String, dynamic>.of(args)
        ..['notes'] = 'Changed payload';
      expect(
        (await agent.handle(request(changed)))['error']['code'],
        'idempotency_conflict',
      );
      final foreign = request(args)
        ..['scope'] = {...scope(), 'workspace_id': 'foreign-workspace'};
      expect((await agent.handle(foreign))['error']['code'], 'scope_mismatch');
      for (final denial in [
        (authority(jobs: {}), 'not_found'),
        (authority(equipmentIds: {}), 'not_found'),
        (authority(actor: 'another-agent'), 'unauthorized'),
      ]) {
        grants.grant = denial.$1;
        expect((await agent.handle(request(args)))['error']['code'], denial.$2);
      }
      expect(flushes, 1);
      expect(await file.readAsBytes(), bytes);
      expect(nativeState(), before);
    },
  );
}
