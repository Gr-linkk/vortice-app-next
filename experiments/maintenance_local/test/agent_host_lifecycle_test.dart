import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/agent_service/access_models.dart';
import 'package:maintenance_local/agent_service/agent_host.dart';
import 'package:maintenance_local/agent_service/proposal_store.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/model.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';

import 'support/recovery_process_harness.dart';

class _Peer {
  _Peer(this.socket)
    : lines = StreamIterator(
        socket
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter()),
      );
  final Socket socket;
  final StreamIterator<String> lines;
  static Future<_Peer> connect(String path) async => _Peer(
    await Socket.connect(
      InternetAddress(path, type: InternetAddressType.unix),
      0,
    ),
  );
  Future<void> send(Json request) async {
    socket.add(utf8.encode('${jsonEncode(request)}\n'));
    await socket.flush();
  }

  Future<Json> next() async {
    expect(await lines.moveNext().timeout(const Duration(seconds: 5)), true);
    return jsonDecode(lines.current) as Json;
  }

  Future<void> close() async {
    socket.destroy();
    await lines.cancel();
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
  late Directory root, runtime;
  late LabStore store;
  late OfficeAgentHost host;
  late String equipment, otherEquipment, job, otherJob, procedure;
  late DateTime clock;
  Completer<void>? observedClock;
  final peers = <_Peer>[];
  final hosts = <OfficeAgentHost>[];

  DateTime now() {
    final observer = observedClock;
    if (observer != null && !observer.isCompleted) observer.complete();
    return clock;
  }

  OfficeAgentHost makeHost({Directory? directory}) {
    final result = OfficeAgentHost(
      store: store,
      runtimeDirectory: directory ?? runtime,
      now: now,
    );
    hosts.add(result);
    return result;
  }

  AgentGrantRequest grant({Set<String>? jobs, Set<String>? equipmentIds}) =>
      AgentGrantRequest(
        label: 'Synthetic assistant',
        expiresAt: clock.add(const Duration(hours: 2)),
        equipmentIds: equipmentIds ?? {equipment},
        jobIds: jobs ?? {job},
        allowNotes: true,
      );
  Json request(String token, String command, [Json? args]) => {
    'protocol_version': 1,
    'request_id': 'synthetic-request',
    'scope': host.scope!.toJson(),
    'credential': {'token': token},
    'command': command,
    'args': args ?? <String, dynamic>{},
  };
  Future<_Peer> peer() async {
    final result = await _Peer.connect(host.snapshot.socketPath!);
    peers.add(result);
    return result;
  }

  String database() => canonical({
    for (final name in [
      'settings',
      'documents',
      'submissions',
      'receipts',
      'events',
    ])
      name: store.db
          .select('SELECT * FROM $name')
          .map((row) => Map<String, dynamic>.from(row))
          .toList(),
  });
  Future<Completer<void>> holdStore() async {
    final entered = Completer<void>(), release = Completer<void>();
    unawaited(
      store.queue.run(() async {
        entered.complete();
        await release.future;
      }),
    );
    await entered.future;
    return release;
  }

  setUp(() async {
    clock = DateTime.utc(2026, 10, 1, 12);
    observedClock = null;
    root = await Directory('/tmp').createTemp('host-test-');
    final protected = await Process.run('/usr/bin/chmod', [
      '700',
      '--',
      root.path,
    ]);
    expect(protected.exitCode, 0);
    runtime = Directory('${root.path}/runtime');
    store = await LabStore.open(
      Directory('${root.path}/office'),
      office: true,
      maintenanceOnly: true,
    );
    await store.createCompany('Synthetic host company');
    equipment =
        (await store.addEquipment(name: 'Selected', meterUnit: 'none'))['id']
            as String;
    otherEquipment =
        (await store.addEquipment(name: 'Other', meterUnit: 'none'))['id']
            as String;
    procedure =
        (await store.publishChecklist(
              title: 'Synthetic procedure',
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
              title: 'Selected work',
            ))['id']
            as String;
    otherJob =
        (await store.prepareWork(
              equipmentId: otherEquipment,
              templateId: procedure,
              title: 'Other work',
            ))['id']
            as String;
    host = makeHost();
  });
  tearDown(() async {
    for (final client in peers) {
      await client.close();
    }
    peers.clear();
    for (final current in hosts) {
      await current.close();
    }
    hosts.clear();
    await store.close();
    await root.delete(recursive: true);
  });

  test(
    'constructor has no effects; fresh init is disabled with no grants',
    () async {
      final before = database();
      expect(
        Directory('${store.root.path}/agent-access-v1').existsSync(),
        false,
      );
      expect(runtime.existsSync(), false);
      expect(host.snapshot.state, OfficeAgentHostState.disabled);
      await host.initialize();
      await host.initialize();
      expect(host.snapshot.state, OfficeAgentHostState.disabled);
      expect(host.snapshot.enabled, false);
      expect(host.snapshot.socketPath, null);
      expect(host.scope, isNotNull);
      expect(host.grants, isEmpty);
      expect(runtime.existsSync(), false);
      expect(database(), before);
      await expectLater(host.issue(grant()), throwsStateError);
    },
  );

  test(
    'enable is explicit, private, idempotent and resumes only saved intent',
    () async {
      final states = <OfficeAgentHostState>[];
      final subscription = host.changes.listen(
        (_) => states.add(host.snapshot.state),
      );
      await host.enable();
      final firstPath = host.snapshot.socketPath!;
      expect(host.snapshot.state, OfficeAgentHostState.listening);
      expect(host.snapshot.enabled, true);
      expect(host.grants, isEmpty);
      expect(runtime.statSync().mode & 0xfff, 0x1c0);
      expect(File(firstPath).statSync().mode & 0xfff, 0x180);
      await host.initialize();
      expect(host.snapshot.socketPath, firstPath);
      await host.close();
      expect(host.snapshot.state, OfficeAgentHostState.closed);
      expect(host.snapshot.enabled, true);
      await host.close();
      host = makeHost();
      await host.initialize();
      expect(host.snapshot.state, OfficeAgentHostState.listening);
      expect(host.snapshot.socketPath, isNot(firstPath));
      await host.disable();
      expect(host.snapshot.enabled, false);
      expect(host.snapshot.state, OfficeAgentHostState.disabled);
      await host.close();
      host = makeHost();
      await host.initialize();
      expect(host.snapshot.state, OfficeAgentHostState.disabled);
      expect(host.snapshot.socketPath, null);
      expect(states, contains(OfficeAgentHostState.listening));
      await subscription.cancel();
    },
  );

  test(
    'second host refuses without changing the first live endpoint',
    () async {
      await host.enable();
      final issued = await host.issue(grant());
      final path = host.snapshot.socketPath;
      final second = makeHost();
      await second.initialize();
      expect(second.snapshot.state, OfficeAgentHostState.unavailable);
      expect(second.snapshot.socketPath, null);
      await second.close();
      expect(host.snapshot.socketPath, path);
      final client = await peer();
      await client.send(request(issued.token, 'capabilities'));
      expect((await client.next())['ok'], true);
    },
  );

  test(
    'cross-process refusal and SIGKILL reopen preserve stale private sockets',
    () async {
      File(
        '${root.path}/agent-host-synthetic.txt',
      ).writeAsStringSync('Synthetic agent host fixture only.');
      await host.enable();
      final issued = await host.issue(grant());
      final originalPath = host.snapshot.socketPath!;
      final probe = await Process.run(RecoveryProcess.dart, [
        'run',
        '--verbosity=error',
        'test/agent_host_process_child.dart',
        root.path,
        'probe',
      ]);
      expect(probe.exitCode, 0, reason: probe.stderr as String);
      expect(
        jsonDecode((probe.stdout as String).trim())['state'],
        'unavailable',
      );
      final client = await peer();
      await client.send(request(issued.token, 'capabilities'));
      expect((await client.next())['ok'], true);
      await host.close();
      final workspace = store.root;
      await store.close();
      final child = await Process.start(RecoveryProcess.dart, [
        'run',
        '--verbosity=error',
        'test/agent_host_process_child.dart',
        root.path,
        'hold',
      ]);
      final errors = child.stderr.transform(utf8.decoder).join();
      final output = StreamIterator(
        child.stdout.transform(utf8.decoder).transform(const LineSplitter()),
      );
      late String crashedPath;
      try {
        expect(
          await output.moveNext().timeout(const Duration(seconds: 30)),
          true,
        );
        final ready = jsonDecode(output.current) as Json;
        expect(ready['state'], 'listening');
        expect(ready['enabled'], true);
        crashedPath = ready['socket_path'] as String;
        expect(crashedPath, isNot(originalPath));
        child.kill(ProcessSignal.sigkill);
        expect(
          await child.exitCode.timeout(const Duration(seconds: 5)),
          isNot(0),
        );
        expect(await errors, isEmpty);
      } finally {
        child.kill(ProcessSignal.sigkill);
        await child.exitCode;
        await output.cancel();
        store = await LabStore.open(
          workspace,
          office: true,
          maintenanceOnly: true,
        );
      }
      expect(
        FileSystemEntity.typeSync(crashedPath, followLinks: false),
        FileSystemEntityType.unixDomainSock,
      );
      final staleBefore = Process.runSync('/usr/bin/stat', [
        '--format=%d:%i:%a',
        '--',
        crashedPath,
      ]).stdout;
      host = makeHost();
      await host.initialize();
      expect(host.snapshot.state, OfficeAgentHostState.listening);
      expect(host.snapshot.socketPath, isNot(crashedPath));
      expect(
        Process.runSync('/usr/bin/stat', [
          '--format=%d:%i:%a',
          '--',
          crashedPath,
        ]).stdout,
        staleBefore,
      );
      final reopened = await peer();
      await reopened.send(request(issued.token, 'capabilities'));
      expect((await reopened.next())['ok'], true);
      await host.close();
      expect(
        FileSystemEntity.typeSync(crashedPath, followLinks: false),
        FileSystemEntityType.unixDomainSock,
      );
    },
  );

  test(
    'current selections reject unknown, removed and mismatched records',
    () async {
      await host.enable();
      for (final invalid in [
        grant(jobs: {'unknown'}),
        grant(equipmentIds: {'unknown'}),
        grant(equipmentIds: {}),
        grant(jobs: {otherJob}),
      ]) {
        await expectLater(host.issue(invalid), throwsStateError);
      }
      final removed = store.catalog!;
      removed['jobs'] = (removed['jobs'] as List)
          .where((row) => row['id'] != otherJob)
          .toList();
      store.setSetting('catalog', removed);
      await expectLater(
        host.issue(grant(jobs: {otherJob}, equipmentIds: {otherEquipment})),
        throwsStateError,
      );
      expect(host.grants, isEmpty);
      expect(host.snapshot.state, OfficeAgentHostState.listening);
    },
  );

  test(
    'pinned selections and empty jobs do not broaden for new records',
    () async {
      final before = database();
      await host.enable();
      final issued = await host.issue(grant());
      final empty = await host.issue(grant(jobs: {}));
      expect(issued.summary.grant.jobIds, {job});
      expect(issued.summary.grant.equipmentIds, {equipment});
      expect(database(), before);
      final later = (await store.prepareWork(
        equipmentId: equipment,
        templateId: procedure,
        title: 'Later work',
      ))['id'];
      final client = await peer();
      await client.send(request(issued.token, 'work.list'));
      final visible = (await client.next())['result']['items'] as List;
      expect(visible.map((row) => row['job_id']), [job]);
      expect(visible.map((row) => row['job_id']), isNot(contains(later)));
      await client.send(request(empty.token, 'work.list'));
      expect((await client.next())['result']['items'], isEmpty);
      expect(() => host.grants.clear(), throwsUnsupportedError);
    },
  );

  for (final action in ['disable', 'close']) {
    test(
      '$action fences queued handlers before drain; later enable cannot revive them',
      () async {
        await host.enable();
        final issued = await host.issue(grant());
        final release = await holdStore();
        final client = await peer();
        observedClock = Completer<void>();
        await client.send(request(issued.token, 'work.list'));
        await observedClock!.future.timeout(const Duration(seconds: 5));
        observedClock = null;
        final queued = await peer();
        await queued.send(
          request(issued.token, 'proposals.create', {
            'idempotency_key': '11111111-1111-4111-8111-111111111111',
            'type': 'inspection.notes',
            'job_id': job,
            'expected_document_hash': digest(store.documentFor(job)!),
            'notes': 'Queued suggestion must be denied',
          }),
        );
        var drained = false;
        final stopping = (action == 'close' ? host.close() : host.disable())
            .then((_) => drained = true);
        expect(host.snapshot.socketPath, null);
        expect(host.snapshot.state, OfficeAgentHostState.stopping);
        await Future<void>.delayed(const Duration(milliseconds: 40));
        expect(drained, false);
        final enabling = action == 'disable'
            ? host.enable()
            : host.initialize();
        release.complete();
        await stopping.timeout(const Duration(seconds: 5));
        await enabling;
        expect(await AgentProposalStore(store.root).records(), isEmpty);
        expect(await client.lines.moveNext(), false);
        if (action == 'disable') {
          expect(host.snapshot.state, OfficeAgentHostState.listening);
          final current = await peer();
          await current.send(request(issued.token, 'capabilities'));
          expect((await current.next())['ok'], true);
        } else {
          expect(host.snapshot.state, OfficeAgentHostState.closed);
        }
      },
    );
  }

  for (final action in ['revoke', 'expire']) {
    test('$action prevents a read at its final authorization fence', () async {
      await host.enable();
      final issued = await host.issue(grant());
      final release = await holdStore();
      final client = await peer();
      observedClock = Completer<void>();
      await client.send(request(issued.token, 'work.list'));
      await observedClock!.future.timeout(const Duration(seconds: 5));
      observedClock = null;
      if (action == 'revoke') {
        await host.revoke(issued.summary.grant.id);
        expect(host.grants.single.revokedAt, isNotNull);
      } else {
        clock = clock.add(const Duration(hours: 3));
      }
      release.complete();
      final response = await client.next();
      expect(response['ok'], false);
      expect(
        response['error']['code'],
        action == 'revoke' ? 'grant_revoked' : 'grant_expired',
      );
      expect(host.snapshot.state, OfficeAgentHostState.listening);
    });
  }

  test(
    'committed suggestion survives an unobserved reply and exact retry after restart',
    () async {
      final before = database();
      await host.enable();
      final issued = await host.issue(grant());
      final payload = <String, dynamic>{
        'idempotency_key': '22222222-2222-4222-8222-222222222222',
        'type': 'inspection.notes',
        'job_id': job,
        'expected_document_hash': digest(store.documentFor(job)!),
        'notes': 'Committed synthetic suggestion',
      };
      final client = await peer();
      await client.send(request(issued.token, 'proposals.create', payload));
      final proposals = AgentProposalStore(store.root);
      List<Json> records;
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      do {
        records = await proposals.records();
        if (records.isNotEmpty) break;
        if (DateTime.now().isAfter(deadline)) {
          fail('Synthetic proposal did not commit.');
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      } while (true);
      // The peer observes no response; its operation must remain uncertain.
      await client.close();
      peers.remove(client);
      await host.disable();
      await host.close();
      host = makeHost();
      await host.enable();
      final retry = await peer();
      await retry.send(request(issued.token, 'proposals.create', payload));
      final response = await retry.next();
      expect(response['ok'], true);
      expect(response['result']['item'], records.single['result']);
      expect(await proposals.records(), hasLength(1));
      expect(database(), before);
    },
  );

  test(
    'corrupt access state reload stops authority and retains exact bytes',
    () async {
      await host.enable();
      await host.issue(grant());
      final config = File('${store.root.path}/agent-access-v1/state.json');
      config.writeAsStringSync(
        'Synthetic corrupt state retained.',
        flush: true,
      );
      final mode = config.statSync().mode;
      await host.reload();
      expect(host.snapshot.state, OfficeAgentHostState.unavailable);
      expect(host.snapshot.enabled, true);
      expect(host.snapshot.socketPath, null);
      expect(host.grants, isEmpty);
      expect(config.readAsStringSync(), 'Synthetic corrupt state retained.');
      expect(config.statSync().mode, mode);
      await host.close();
      host = makeHost();
      await host.initialize();
      expect(host.snapshot.state, OfficeAgentHostState.unavailable);
      expect(config.readAsStringSync(), 'Synthetic corrupt state retained.');
    },
  );

  test(
    'an opened host fails closed when its office scope disappears',
    () async {
      await host.enable();
      store.db.execute("DELETE FROM settings WHERE key='catalog'");
      await host.reload();
      expect(host.snapshot.state, OfficeAgentHostState.unavailable);
      expect(host.snapshot.socketPath, null);
    },
  );

  test(
    'unsafe runtime paths stay intact and saved intent remains truthful',
    () async {
      for (final kind in ['file', 'public-directory', 'symlink', 'long']) {
        await host.close();
        final target = '${root.path}/$kind';
        Directory directory;
        if (kind == 'file') {
          File(target).writeAsStringSync('retained');
          directory = Directory(target);
        } else if (kind == 'public-directory') {
          directory = await Directory(target).create();
          await Process.run('/usr/bin/chmod', ['755', '--', target]);
        } else if (kind == 'symlink') {
          await Link(target).create(root.path);
          directory = Directory(target);
        } else {
          directory = Directory('${root.path}/${'x' * 100}');
        }
        final mode =
            FileSystemEntity.typeSync(target, followLinks: false) ==
                FileSystemEntityType.notFound
            ? null
            : File(target).statSync().mode;
        host = makeHost(directory: directory);
        await host.enable();
        expect(host.snapshot.state, OfficeAgentHostState.unavailable);
        expect(host.snapshot.enabled, true);
        expect(host.snapshot.socketPath, null);
        expect(host.snapshot.problem, isNot(contains(root.path)));
        if (mode != null) expect(File(target).statSync().mode, mode);
        if (kind == 'file') expect(File(target).readAsStringSync(), 'retained');
        if (kind == 'symlink') expect(Link(target).targetSync(), root.path);
      }
    },
  );

  test(
    'phone and unprepared office do not create access files; later company retries',
    () async {
      await host.close();
      await store.close();
      store = await LabStore.open(
        Directory('${root.path}/unprepared'),
        office: true,
        maintenanceOnly: true,
      );
      host = makeHost();
      await host.initialize();
      await host.enable();
      expect(host.scope, null);
      expect(host.snapshot.state, OfficeAgentHostState.disabled);
      expect(
        Directory('${store.root.path}/agent-access-v1').existsSync(),
        false,
      );
      await store.createCompany('Prepared later');
      await host.initialize();
      expect(host.scope, isNotNull);
      expect(host.snapshot.state, OfficeAgentHostState.disabled);
      await host.enable();
      expect(host.snapshot.state, OfficeAgentHostState.listening);
      await host.close();
      await store.close();
      store = await LabStore.open(
        Directory('${root.path}/phone'),
        office: false,
        maintenanceOnly: true,
      );
      host = makeHost();
      await host.initialize();
      await host.enable();
      expect(host.scope, null);
      expect(host.snapshot.state, OfficeAgentHostState.disabled);
      expect(
        Directory('${store.root.path}/agent-access-v1').existsSync(),
        false,
      );
    },
  );
}
