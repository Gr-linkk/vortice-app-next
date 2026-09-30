import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/local_sync.dart';
import 'package:maintenance_local/model.dart';
import 'package:maintenance_local/src/rust/api/documents.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';

Json _copy(Json value) => jsonDecode(canonical(value)) as Json;

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('Timed out waiting for the synthetic office queue.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

/// Exchanges a caller-selected document against one prepared work order. This
/// deliberately bypasses PhoneSync's selection of the matching local document.
Future<void> _exchange(
  PinnedConnection connection,
  Uint8List bytes,
  String jobId, {
  String? session,
}) async {
  final state = await newSession();
  final id = session ?? secret();
  Uint8List? incoming;
  try {
    for (var round = 0; round < 32; round++) {
      final packet = await state.step(bytes: bytes, incoming: incoming);
      bytes = packet.document;
      final reply = await connection.request('/sync', {
        'jobId': jobId,
        'session': id,
        'message': packet.message == null
            ? null
            : base64Encode(packet.message!),
      });
      incoming = reply['message'] == null
          ? null
          : base64Decode(reply['message'] as String);
      if (incoming == null && packet.message == null) return;
    }
    throw StateError('The synthetic document exchange did not finish.');
  } finally {
    state.dispose();
  }
}

void main() {
  setUpAll(
    () async => RustLib.init(
      externalLibrary: ExternalLibrary.open(
        Platform.environment['MAINTENANCE_NATIVE_LIBRARY'] ??
            File('rust/target/debug/librust_lib_sync_lab.so').absolute.path,
      ),
    ),
  );

  late Directory root;
  late LabStore office, phone;
  late OfficeServer server;
  late PhoneSync sync;
  late Json firstJob, secondJob;
  final extraStores = <LabStore>[];

  setUp(() async {
    root = await Directory.systemTemp.createTemp('maintenance-network-');
    office = await LabStore.open(
      Directory('${root.path}/office'),
      office: true,
    );
    await office.createCompany(
      'Synthetic network company',
      coordinatorName: 'Synthetic coordinator',
    );
    final equipment = await office.addEquipment(
      name: 'Synthetic generator',
      serial: 'NETWORK-ONLY-01',
      meterUnit: 'hours',
    );
    final checklist = await office.publishChecklist(
      title: 'Synthetic inspection',
      items: [
        {'id': 'guards', 'label': 'Inspect guards', 'input_type': 'check'},
      ],
      provenance: {'kind': 'company-authored', 'reference': ''},
    );
    firstJob = await office.prepareWork(
      equipmentId: equipment['id'] as String,
      templateId: checklist['id'] as String,
      title: 'Synthetic first inspection',
    );
    secondJob = await office.prepareWork(
      equipmentId: equipment['id'] as String,
      templateId: checklist['id'] as String,
      title: 'Synthetic second inspection',
    );
    phone = await LabStore.open(Directory('${root.path}/phone'), office: false);
    server = await OfficeServer.start(
      office,
      port: 0,
      address: InternetAddress.loopbackIPv4,
    );
    sync = PhoneSync(phone);
  });

  tearDown(() async {
    await server.close();
    await phone.close();
    await office.close();
    for (final store in extraStores) {
      await store.close();
    }
    extraStores.clear();
    await root.delete(recursive: true);
  });

  String firstId() => firstJob['id'] as String;
  String secondId() => secondJob['id'] as String;

  Future<void> connect() async {
    await sync.enroll(server.invitation('127.0.0.1'));
    server.authority.confirm(phone.device);
    await sync.sync();
  }

  Future<Json> submit(
    String jobId, {
    String notes = 'Synthetic guard inspected.',
  }) async {
    await phone.update({
      'answer:guards': {'result': 'action', 'value': ''},
      'meter': 42.5,
      'notes': notes,
    }, jobId: jobId);
    await phone.attach(
      List.generate(8193, (i) => (i * 19 + 11) % 251),
      jobId: jobId,
    );
    return phone.submit(jobId: jobId);
  }

  Json documents(LabStore store) => {
    for (final job in store.jobs)
      job['id'] as String: base64Encode(
        store.documentFor(job['id'] as String)!,
      ),
  };

  Future<void> rejectedWhileQueued(
    String path,
    Json body, {
    void Function()? afterRevocation,
  }) async {
    final connection = PinnedConnection(sync.pairing!);
    final entered = Completer<void>(), release = Completer<void>();
    final blocker = office.queue.run(() async {
      entered.complete();
      await release.future;
    });
    await entered.future;
    final tail = office.queue.idle;
    final rejected = expectLater(
      connection.request(path, body),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'revocation',
          contains('revoked'),
        ),
      ),
    );
    try {
      await _until(() => !identical(office.queue.idle, tail));
      server.authority.revoke(phone.device);
      afterRevocation?.call();
    } finally {
      release.complete();
    }
    try {
      await blocker;
      await rejected;
      await office.queue.idle;
    } finally {
      connection.close();
    }
  }

  test(
    'Phone cannot author the company catalog or prepare authoritative work',
    () async {
      await connect();
      final before = canonical(phone.catalog),
          beforeDocuments = documents(phone);
      await expectLater(
        phone.createCompany('Injected company'),
        throwsStateError,
      );
      await expectLater(
        phone.addEquipment(name: 'Injected equipment'),
        throwsStateError,
      );
      await expectLater(
        phone.publishChecklist(
          title: 'Injected checklist',
          items: [
            {'id': 'injected', 'label': 'Injected step', 'input_type': 'check'},
          ],
          provenance: {'kind': 'company-authored'},
        ),
        throwsStateError,
      );
      await expectLater(
        phone.prepareWork(
          equipmentId: office.equipment.single['id'] as String,
          templateId: office.templates.single['id'] as String,
          title: 'Injected work',
        ),
        throwsStateError,
      );
      final connection = PinnedConnection(sync.pairing!);
      try {
        for (final route in [
          '/company/create',
          '/equipment/add',
          '/checklist/publish',
          '/work/prepare',
          '/approve',
        ]) {
          await expectLater(
            connection.request(route, {'catalog': phone.catalog}),
            throwsStateError,
          );
        }
        final bundle = await connection.request('/bundle', {});
        expect(bundle['catalog'], office.catalog);
        expect((bundle['documents'] as Map).keys.toSet(), {
          firstId(),
          secondId(),
        });
        expect(bundle.keys, isNot(contains('phones')));
        expect(bundle.keys, isNot(contains('invites')));
        expect(bundle.keys, isNot(contains('pairing')));
      } finally {
        connection.close();
      }
      expect(canonical(phone.catalog), before);
      expect(documents(phone), beforeDocuments);
      expect(phone.db.select('SELECT * FROM phones'), isEmpty);
      expect(phone.db.select('SELECT * FROM invites'), isEmpty);
      expect(office.jobs, hasLength(2));
      expect(office.receipts, isEmpty);
    },
  );

  test(
    'TLS rejects forged company, job, device and frozen submission context',
    () async {
      await connect();
      final submission = await submit(firstId());
      final otherContext = office.jobContextFor(secondId());
      final changedContext = _copy(submission['context'] as Json)
        ..['coordinatorName'] = 'Injected reviewer';
      final connection = PinnedConnection(sync.pairing!);
      final before = documents(office),
          beforeCatalog = canonical(office.catalog);
      try {
        for (final bad in <Json>[
          {...submission, 'companyId': 'foreign-company'},
          {...submission, 'jobId': 'foreign-job'},
          {...submission, 'device': 'foreign-device'},
          {...submission, 'jobId': secondId()},
          {...submission, 'equipmentId': 'foreign-equipment'},
          {...submission, 'snapshotHash': '0' * 64},
          {...submission, 'revision': 2},
          {...submission, 'context': changedContext},
          {...submission, 'context': otherContext},
          {...submission, 'approved': true},
          {...submission, 'documentHash': '0' * 64},
          {
            ...submission,
            'values': {
              ...submission['values'] as Json,
              'notes': 'Injected answers',
            },
          },
          // All outer metadata is relabelled consistently. The encoded document
          // must still be bound to the original prepared work order.
          {
            ...submission,
            'jobId': secondId(),
            'context': otherContext,
            'equipmentId': otherContext['equipmentId'],
            'snapshotHash': otherContext['snapshotHash'],
            'revision': otherContext['revision'],
          },
        ]) {
          await expectLater(
            connection.request('/submit', bad),
            throwsStateError,
          );
        }
      } finally {
        connection.close();
      }
      expect(office.submissions, isEmpty);
      expect(office.receipts, isEmpty);
      expect(documents(office), before);
      expect(canonical(office.catalog), beforeCatalog);
    },
  );

  test(
    'Automerge packets cannot cross prepared jobs or import phone authority',
    () async {
      await connect();
      await phone.update({
        'notes': 'First job local-only draft',
      }, jobId: firstId());
      final connection = PinnedConnection(sync.pairing!);
      final before = documents(office), catalog = canonical(office.catalog);
      try {
        await expectLater(
          _exchange(connection, phone.documentFor(firstId())!, secondId()),
          throwsStateError,
        );
        for (final body in <Json>[
          {'jobId': 'foreign-job', 'session': secret(), 'message': null},
          {'session': secret(), 'message': null},
        ]) {
          await expectLater(
            connection.request('/sync', body),
            throwsStateError,
          );
        }
        final injected = await editDocument(
          bytes: phone.documentFor(firstId())!,
          actor: 'synthetic-attacker',
          fieldsJson: canonical({'approved': true, 'catalog': office.catalog}),
        );
        await expectLater(
          _exchange(connection, injected, firstId()),
          throwsStateError,
        );
      } finally {
        connection.close();
      }
      expect(documents(office), before);
      expect(canonical(office.catalog), catalog);
      expect(office.submissions, isEmpty);
      expect(office.receipts, isEmpty);
    },
  );

  test(
    'The same TLS session label keeps two prepared job histories separate',
    () async {
      await connect();
      await phone.update({'notes': 'First job packet'}, jobId: firstId());
      await phone.update({'notes': 'Second job packet'}, jobId: secondId());
      final connection = PinnedConnection(sync.pairing!);
      final session = secret();
      try {
        await _exchange(
          connection,
          phone.documentFor(firstId())!,
          firstId(),
          session: session,
        );
        await _exchange(
          connection,
          phone.documentFor(secondId())!,
          secondId(),
          session: session,
        );
      } finally {
        connection.close();
      }
      expect(
        valuesOf(await office.fields(jobId: firstId()))['notes'],
        'First job packet',
      );
      expect(
        valuesOf(await office.fields(jobId: secondId()))['notes'],
        'Second job packet',
      );
      expect(
        valuesOf(await office.fields(jobId: firstId()))['_jobId'],
        firstId(),
      );
      expect(
        valuesOf(await office.fields(jobId: secondId()))['_jobId'],
        secondId(),
      );
    },
  );

  test(
    'TLS replay is immutable and submission revisions follow each job and device',
    () async {
      await connect();
      final first = await submit(firstId());
      await phone.update({
        'notes': 'Synthetic revised findings.',
      }, jobId: firstId());
      final next = await phone.submit(jobId: firstId());
      final other = await submit(secondId());
      expect(first['submissionRevision'], 1);
      expect(first['predecessorId'], isNull);
      expect(next['submissionRevision'], 2);
      expect(next['predecessorId'], first['id']);
      expect(other['submissionRevision'], 1);
      expect(other['predecessorId'], isNull);
      final connection = PinnedConnection(sync.pairing!);
      try {
        await expectLater(
          connection.request('/submit', next),
          throwsStateError,
        );
        await expectLater(
          connection.request('/submit', {
            ...first,
            'submissionRevision': 2,
            'predecessorId': other['id'],
          }),
          throwsStateError,
        );
        for (final payload in [first, other, next, first, next, other]) {
          expect(
            (await connection.request('/submit', payload))['accepted'],
            payload['id'],
          );
        }
        await expectLater(
          connection.request('/submit', {
            ...first,
            'createdAt': '2000-01-01T00:00:00Z',
          }),
          throwsStateError,
        );
      } finally {
        connection.close();
      }
      expect(office.submissions, hasLength(3));
      expect(office.submissions.map((p) => p['id']).toSet(), {
        first['id'],
        next['id'],
        other['id'],
      });
      expect(office.receipts, isEmpty);
    },
  );

  test(
    'A different company cannot replace saved work or borrow its paired credential',
    () async {
      await connect();
      await phone.update({
        'notes': 'Retained first-company draft',
      }, jobId: firstId());
      final submission = await submit(
        firstId(),
        notes: 'Retained first-company submission',
      );
      final foreign = await LabStore.open(
        Directory('${root.path}/foreign-office'),
        office: true,
      );
      extraStores.add(foreign);
      await foreign.createCompany('Other synthetic company');
      final foreignServer = await OfficeServer.start(
        foreign,
        port: 0,
        address: InternetAddress.loopbackIPv4,
      );
      final before = documents(phone),
          catalog = canonical(phone.catalog),
          pairing = canonical(sync.pairing);
      try {
        await expectLater(
          sync.enroll(foreignServer.invitation('127.0.0.1')),
          throwsStateError,
        );
        final borrowed = PinnedConnection({
          ...sync.pairing!,
          'url': 'https://127.0.0.1:${foreignServer.port}',
          'fingerprint': foreignServer.identity.fingerprint,
        });
        try {
          await expectLater(borrowed.request('/bundle', {}), throwsStateError);
          await expectLater(
            borrowed.request('/submit', submission),
            throwsStateError,
          );
        } finally {
          borrowed.close();
        }
      } finally {
        await foreignServer.close();
      }
      expect(canonical(phone.catalog), catalog);
      expect(canonical(sync.pairing), pairing);
      expect(
        phone.submissions.single['companyId'],
        office.catalog!['companyId'],
      );
      expect(
        valuesOf(await phone.fields(jobId: secondId())),
        valuesOf(await office.fields(jobId: secondId())),
      );
      expect(documents(phone), before);
      expect(foreign.submissions, isEmpty);
      expect(foreign.receipts, isEmpty);
      expect(foreign.jobs, isEmpty);
    },
  );

  test(
    'TLS photo routes and bundles expose only hashes referenced by company work',
    () async {
      await connect();
      final bytes = List.generate(8193, (i) => (i * 7 + 3) % 251);
      final hash = await office.evidence.add(bytes);
      final connection = PinnedConnection(sync.pairing!);
      try {
        for (final request in <String, Json>{
          '/blob/status': {'hash': hash},
          '/blob/get': {'hash': hash, 'offset': 0},
          '/blob/put': {
            'hash': hash,
            'offset': 0,
            'total': bytes.length,
            'bytes': base64Encode(bytes),
          },
        }.entries) {
          await expectLater(
            connection.request(request.key, request.value),
            throwsStateError,
          );
        }
        final bundle = await connection.request('/bundle', {});
        expect(
          (bundle['blobs'] as List).where(
            (blob) => (blob as Map)['hash'] == hash,
          ),
          isEmpty,
        );
      } finally {
        connection.close();
      }
      expect(
        await office.evidence.file(hash).readAsBytes(),
        orderedEquals(bytes),
      );
      expect(office.submissions, isEmpty);
    },
  );

  test(
    'Missing and corrupt TLS photo transfers block exact-version office approval',
    () async {
      await connect();
      final submission = await submit(firstId());
      final hash = (submission['values'] as Json)['photo'] as String;
      final bytes = await phone.evidence.file(hash).readAsBytes();
      final connection = PinnedConnection(sync.pairing!);
      try {
        await _exchange(connection, phone.documentFor(firstId())!, firstId());
        await connection.request('/submit', submission);
        expect(await office.approvalProblem(submission), contains('photo'));
        await expectLater(
          office.decide(submission['id'] as String, approve: true),
          throwsStateError,
        );
        await connection.request('/blob/put', {
          'hash': hash,
          'offset': 0,
          'total': bytes.length,
          'bytes': base64Encode(bytes.sublist(0, 777)),
        });
        await expectLater(
          office.decide(submission['id'] as String, approve: true),
          throwsStateError,
        );
        final changedTail = bytes.sublist(777)..[0] ^= 1;
        await expectLater(
          connection.request('/blob/put', {
            'hash': hash,
            'offset': 777,
            'total': bytes.length,
            'bytes': base64Encode(changedTail),
          }),
          throwsStateError,
        );
        expect((await office.evidence.status(hash))['offset'], 0);
        expect(office.receipts, isEmpty);
        await connection.request('/blob/put', {
          'hash': hash,
          'offset': 0,
          'total': bytes.length,
          'bytes': base64Encode(bytes),
        });
        await office.evidence.file(hash).writeAsBytes([1, 2, 3], flush: true);
        await expectLater(
          office.decide(submission['id'] as String, approve: true),
          throwsStateError,
        );
        expect(office.receipts, isEmpty);
        await connection.request('/blob/put', {
          'hash': hash,
          'offset': 0,
          'total': bytes.length,
          'bytes': base64Encode(bytes),
        });
        final receipt = await office.decide(
          submission['id'] as String,
          approve: true,
        );
        expect(receipt['submissionHash'], contentHash(submission));
        expect(receipt['values'], submission['values']);
        expect(
          await office.decide(submission['id'] as String, approve: true),
          receipt,
        );
      } finally {
        connection.close();
      }
      expect(office.submissions, hasLength(1));
      expect(office.receipts, hasLength(1));
      expect(
        office.db.select("SELECT * FROM events WHERE kind='reviewed'"),
        hasLength(1),
      );
    },
  );

  test(
    'Revoking a queued TLS submission prevents a durable prepared-job record',
    () async {
      await connect();
      final submission = await submit(firstId());
      final before = documents(office);
      await rejectedWhileQueued('/submit', submission);
      expect(office.submissions, isEmpty);
      expect(office.receipts, isEmpty);
      expect(documents(office), before);
    },
  );

  test('Revoking a queued TLS work packet prevents document changes', () async {
    await connect();
    await phone.update({
      'notes': 'Revoked prepared-job packet',
    }, jobId: firstId());
    final connection = PinnedConnection(sync.pairing!);
    final state = await newSession(), session = secret();
    try {
      final first = await state.step(
        bytes: phone.documentFor(firstId())!,
        incoming: null,
      );
      final reply = await connection.request('/sync', {
        'jobId': firstId(),
        'session': session,
        'message': base64Encode(first.message!),
      });
      final changed = await state.step(
        bytes: first.document,
        incoming: base64Decode(reply['message'] as String),
      );
      expect(changed.message, isNotNull);
      final before = documents(office);
      await rejectedWhileQueued('/sync', {
        'jobId': firstId(),
        'session': session,
        'message': base64Encode(changed.message!),
      });
      expect(documents(office), before);
      expect(valuesOf(await office.fields(jobId: firstId()))['notes'], '');
    } finally {
      state.dispose();
      connection.close();
    }
  });

  for (final route in ['/bundle', '/blob/status', '/blob/get', '/blob/put']) {
    test(
      'Revoking queued TLS $route denies catalog and evidence access',
      () async {
        await connect();
        final submission = await submit(firstId());
        final connection = PinnedConnection(sync.pairing!);
        try {
          await connection.request('/submit', submission);
        } finally {
          connection.close();
        }
        final hash = (submission['values'] as Json)['photo'] as String;
        final bytes = await phone.evidence.file(hash).readAsBytes();
        if (route == '/blob/get') await office.evidence.add(bytes);
        if (route == '/blob/status') {
          await office.evidence.root.create(recursive: true);
          await File(
            '${office.evidence.file(hash).path}.part',
          ).writeAsBytes(bytes, flush: true);
        }
        final before = documents(office);
        await rejectedWhileQueued(route, switch (route) {
          '/bundle' => <String, dynamic>{},
          '/blob/status' => {'hash': hash},
          '/blob/get' => {'hash': hash, 'offset': 0},
          _ => {
            'hash': hash,
            'offset': 0,
            'total': bytes.length,
            'bytes': base64Encode(bytes),
          },
        });
        expect(documents(office), before);
        expect(office.submissions, hasLength(1));
        expect(office.receipts, isEmpty);
        if (route == '/blob/get') {
          expect(
            await office.evidence.file(hash).readAsBytes(),
            orderedEquals(bytes),
          );
        } else {
          expect(await office.evidence.file(hash).exists(), isFalse);
          if (route == '/blob/status') {
            expect(
              await File(
                '${office.evidence.file(hash).path}.part',
              ).readAsBytes(),
              orderedEquals(bytes),
            );
          }
          if (route == '/blob/put') {
            expect(
              await File('${office.evidence.file(hash).path}.part').exists(),
              isFalse,
            );
          }
        }
      },
    );
  }

  test(
    'TLS status rechecks revocation after an asynchronous evidence read before publication',
    () async {
      await connect();
      final submission = await submit(firstId());
      final hash = (submission['values'] as Json)['photo'] as String;
      final bytes = await phone.evidence.file(hash).readAsBytes();
      final connection = PinnedConnection(sync.pairing!);
      Process? writer;
      try {
        await connection.request('/submit', submission);
        await office.evidence.root.create(recursive: true);
        final partial = File('${office.evidence.file(hash).path}.part');
        final created = await Process.run('mkfifo', [partial.path]);
        expect(created.exitCode, 0, reason: created.stderr.toString());
        // A FIFO writer opens only after the server opens its reader. Holding its
        // stdin makes the real async file read wait at a deterministic barrier.
        writer = await Process.start('sh', [
          '-c',
          'exec 3>"\$1"; printf "reader-open\\n"; cat >&3',
          'synthetic-evidence-writer',
          partial.path,
        ]);
        final ready = writer.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .first;
        final rejected = expectLater(
          connection.request('/blob/status', {'hash': hash}),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'revocation after read',
              contains('revoked'),
            ),
          ),
        );
        expect(await ready.timeout(const Duration(seconds: 5)), 'reader-open');
        server.authority.revoke(phone.device);
        writer.stdin.add(bytes);
        await writer.stdin.close();
        expect(await writer.exitCode.timeout(const Duration(seconds: 5)), 0);
        await rejected;
        await office.queue.idle;
        expect(
          await FileSystemEntity.type(partial.path),
          FileSystemEntityType.pipe,
        );
        expect(await office.evidence.file(hash).exists(), isFalse);
        expect(office.submissions, hasLength(1));
        expect(office.receipts, isEmpty);
      } finally {
        writer?.kill();
        connection.close();
      }
    },
    skip: !Platform.isLinux,
  );
}
