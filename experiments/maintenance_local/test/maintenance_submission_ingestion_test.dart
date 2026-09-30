import 'dart:convert';
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/local_sync.dart';
import 'package:maintenance_local/model.dart';
import 'package:maintenance_local/office_backup.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';
import 'package:sqlite3/sqlite3.dart';

Json _copy(Json value) => jsonDecode(canonical(value)) as Json;

// Hash complete raw rows, including private authority/settings rows, so a
// failed assertion cannot print a synthetic enrollment credential.
Json _databaseState(LabStore store) => {
  'schema': store.db.select('PRAGMA user_version').single.values.single,
  for (final table in [
    'settings',
    'documents',
    'submissions',
    'receipts',
    'events',
    'phones',
    'invites',
  ])
    table: contentHash([
      for (final row in store.db.select('SELECT * FROM $table ORDER BY rowid'))
        {
          for (final key in row.keys)
            key: row[key] is List<int>
                ? base64Encode(row[key] as List<int>)
                : row[key],
        },
    ]),
};

Future<Json> _files(Directory root) async {
  if (!await root.exists()) return {'exists': false};
  final result = <String, dynamic>{'exists': true};
  await for (final entry in root.list(recursive: true, followLinks: false)) {
    final name = entry.path.substring(root.path.length + 1);
    result[name] = entry is File
        ? digest(await entry.readAsBytes())
        : 'directory';
  }
  return result;
}

Future<List<String>> _staging(Directory root) async {
  final names = <String>[];
  await for (final entry in root.list(followLinks: false)) {
    if (entry.uri.pathSegments
        .where((s) => s.isNotEmpty)
        .last
        .startsWith('.office-recovery-')) {
      names.add(entry.path);
    }
  }
  names.sort();
  return names;
}

class _Fixture {
  _Fixture(
    this.root,
    this.office,
    this.phone,
    this.server,
    this.sync,
    this.jobs,
  );
  final Directory root;
  final LabStore office, phone;
  final OfficeServer server;
  final PhoneSync sync;
  final List<String> jobs;
  final extraStores = <LabStore>[];
  final connections = <PinnedConnection>[];

  static Future<_Fixture> create() async {
    final root = await Directory.systemTemp.createTemp(
      'maintenance-ingestion-',
    );
    final office = await LabStore.open(
      Directory('${root.path}/office'),
      office: true,
      maintenanceOnly: true,
    );
    final phone = await LabStore.open(
      Directory('${root.path}/phone'),
      office: false,
      maintenanceOnly: true,
    );
    await office.createCompany(
      'Synthetic ingestion probe company',
      coordinatorName: 'Synthetic ingestion coordinator',
    );
    final jobs = <String>[];
    for (final name in ['A', 'B']) {
      jobs.add(await _prepare(office, name));
    }
    final server = await OfficeServer.start(
      office,
      port: 0,
      address: InternetAddress.loopbackIPv4,
    );
    final sync = PhoneSync(phone);
    await sync.enroll(server.invitation('127.0.0.1'));
    server.authority.confirm(phone.device);
    await sync.sync();
    return _Fixture(root, office, phone, server, sync, jobs);
  }

  static Future<String> _prepare(LabStore office, String name) async {
    final equipment = await office.addEquipment(
      name: 'Synthetic ingestion pump $name',
      serial: 'INGESTION-$name',
    );
    final template = await office.publishChecklist(
      title: 'Synthetic ingestion guard procedure $name',
      items: [
        {'id': 'guard', 'label': 'Guard secure', 'input_type': 'check'},
      ],
      provenance: {'kind': 'company-authored'},
    );
    return (await office.prepareWork(
          equipmentId: equipment['id'] as String,
          templateId: template['id'] as String,
          title: 'Synthetic ingestion inspection $name',
        ))['id']
        as String;
  }

  Future<String> addOfficeJob() => _prepare(office, 'C');

  PinnedConnection connection() {
    final connection = PinnedConnection(sync.pairing!);
    connections.add(connection);
    return connection;
  }

  Future<LabStore> importTarget(Json seed) async {
    final target = await LabStore.open(
      Directory('${root.path}/import-target-${extraStores.length}'),
      office: false,
      maintenanceOnly: true,
    );
    extraStores.add(target);
    await target.importOfficeBundle(seed);
    return target;
  }

  Future<Json> firstCommand({bool send = true}) async {
    await phone.update({
      'answer:guard': {'result': 'pass', 'value': ''},
      'meter': 0,
      'notes': 'Synthetic complete guard observation.',
    }, jobId: jobs.first);
    await phone.attach([1, 2, 3, 4, 5, 6], jobId: jobs.first);
    // Save work and evidence before exercising /submit directly.
    await sync.sync();
    final first = await phone.submit(jobId: jobs.first);
    expect(await office.approvalProblem(first), isNull);
    if (send) await sync.sync();
    return first;
  }

  Future<_History> twoVersions() async {
    final first = await firstCommand();
    final returned = await office.decide(
      first['id'] as String,
      approve: false,
      reason: 'Synthetic requested follow-up observation.',
    );
    await sync.sync();
    final seed = await office.publicBundle();
    // Equal displayed values can represent distinct document history. The
    // duplicate rule must bind exact bytes, not prohibit an honest edit/revert.
    final notes = (first['values'] as Json)['notes'] as String;
    await phone.update({
      'notes': 'Synthetic temporary draft.',
    }, jobId: jobs.first);
    await phone.update({'notes': notes}, jobId: jobs.first);
    final second = await phone.submit(jobId: jobs.first);
    expect(second['values'], first['values']);
    expect(second['documentHash'], isNot(first['documentHash']));
    expect(second['document'], isNot(first['document']));
    expect(second['submissionRevision'], 2);
    expect(second['predecessorId'], first['id']);
    await sync.sync();
    final approved = await office.decide(second['id'] as String, approve: true);
    return _History(first, second, returned, approved, seed);
  }

  Future<void> close() async {
    for (final connection in connections) {
      connection.close();
    }
    await server.close();
    for (final store in extraStores.reversed) {
      await store.close();
    }
    await phone.close();
    await office.close();
    await root.delete(recursive: true);
  }
}

class _History {
  _History(this.first, this.second, this.returned, this.approved, this.seed);
  final Json first, second, returned, approved, seed;

  Json poisoned(String kind) {
    final payload = _copy(second);
    if (kind == 'duplicate version') {
      payload['document'] = first['document'];
      payload['documentHash'] = first['documentHash'];
      expect(payload['values'], first['values']);
    } else {
      payload['_state'] = 'received';
    }
    return payload;
  }

  Json receiptFor(Json payload) =>
      _copy(approved)
        ..['submissionHash'] = contentHash(_copy(payload)..remove('_state'));
}

void _replaceSavedCommand(Database db, Json payload, Json receipt) {
  db.execute('UPDATE submissions SET hash=?,payload=? WHERE id=?', [
    contentHash(payload),
    canonical(payload),
    payload['id'],
  ]);
  db.execute('UPDATE receipts SET hash=?,payload=? WHERE id=?', [
    contentHash(receipt),
    canonical(receipt),
    receipt['id'],
  ]);
}

Future<void> _poisonBackup(Directory backup, Json payload, Json receipt) async {
  final file = File('${backup.path}/workspace.sqlite');
  final db = sqlite3.open(file.path);
  try {
    _replaceSavedCommand(db, payload, receipt);
  } finally {
    db.close();
  }
  final manifestFile = File('${backup.path}/manifest.json');
  final manifest = jsonDecode(await manifestFile.readAsString()) as Json;
  final bytes = await file.readAsBytes();
  (manifest['files'] as Json)['workspace.sqlite'] = {
    'hash': digest(bytes),
    'size': bytes.length,
  };
  await manifestFile.writeAsString(canonical(manifest), flush: true);
}

void main() {
  setUpAll(() async {
    await RustLib.init(
      externalLibrary: ExternalLibrary.open(
        File(
          Platform.environment['MAINTENANCE_NATIVE_LIBRARY'] ??
              'rust/target/debug/librust_lib_sync_lab.so',
        ).absolute.path,
      ),
    );
  });
  late _Fixture f;
  setUp(() async => f = await _Fixture.create());
  tearDown(() async => f.close());

  for (final approve in [false, true]) {
    final decision = approve ? 'approved' : 'returned';
    test(
      'A $decision version rejects fresh IDs atomically but exact retry and edited successor work',
      () async {
        final first = await f.firstCommand();
        final receipt = await f.office.decide(
          first['id'] as String,
          approve: approve,
          reason: approve ? '' : 'Synthetic follow-up requested.',
        );
        final baseline = _databaseState(f.office);
        final files = await _files(f.office.evidence.root);
        final connection = f.connection();
        final duplicate = _copy(first)
          ..['id'] = 'synthetic-reenveloped-$decision'
          ..['predecessorId'] = first['id']
          ..['submissionRevision'] = 2;
        expect(duplicate['document'], first['document']);
        expect(duplicate['documentHash'], first['documentHash']);
        await expectLater(
          connection.request('/submit', duplicate),
          throwsStateError,
        );
        expect(_databaseState(f.office), baseline);
        expect(await _files(f.office.evidence.root), files);
        expect(f.office.submissions, hasLength(1));
        expect(f.office.receipts, [receipt]);

        expect(await connection.request('/submit', first), {
          'accepted': first['id'],
        });
        expect(_databaseState(f.office), baseline);
        expect((await f.phone.submit(jobId: f.jobs.first))['id'], first['id']);
        await f.sync.sync();
        await f.phone.update({
          'answer:guard': {'result': 'action', 'value': ''},
          'notes': 'Synthetic new observation: guard needs correction.',
        }, jobId: f.jobs.first);
        final second = await f.phone.submit(jobId: f.jobs.first);
        expect(second['id'], isNot(first['id']));
        expect(second['documentHash'], isNot(first['documentHash']));
        expect(second['submissionRevision'], 2);
        expect(second['predecessorId'], first['id']);
        await f.sync.sync();
        final nextReceipt = await f.office.decide(
          second['id'] as String,
          approve: true,
        );
        expect(f.office.receipts, [receipt, nextReceipt]);
        expect(f.office.submissions.map((p) => p['id']), [
          first['id'],
          second['id'],
        ]);

        // The old version remains reserved even after a genuinely new version.
        final afterEdit = _databaseState(f.office);
        duplicate['id'] = 'synthetic-old-version-after-$decision';
        duplicate['predecessorId'] = second['id'];
        duplicate['submissionRevision'] = 3;
        await expectLater(
          connection.request('/submit', duplicate),
          throwsStateError,
        );
        expect(_databaseState(f.office), afterEdit);
        expect(await connection.request('/submit', first), {
          'accepted': first['id'],
        });
        expect(_databaseState(f.office), afterEdit);
      },
    );

    test(
      'Wire local state rejects before saving and the clean original can be $decision',
      () async {
        final first = await f.firstCommand(send: false);
        final baseline = _databaseState(f.office);
        final files = await _files(f.office.evidence.root);
        final connection = f.connection();
        for (final localState in ['queued', 'received', null]) {
          final contaminated = _copy(first)..['_state'] = localState;
          await expectLater(
            connection.request('/submit', contaminated),
            throwsStateError,
          );
          expect(_databaseState(f.office), baseline);
          expect(await _files(f.office.evidence.root), files);
          expect(f.office.submissions, isEmpty);
          expect(f.office.receipts, isEmpty);
        }
        expect(await connection.request('/submit', first), {
          'accepted': first['id'],
        });
        final raw = f.office.db
            .select('SELECT payload,hash,state FROM submissions')
            .single;
        expect(jsonDecode(raw['payload'] as String), first);
        expect(raw['hash'], contentHash(first));
        expect(raw['state'], 'received');
        expect(
          (jsonDecode(raw['payload'] as String) as Json).containsKey('_state'),
          isFalse,
        );
        // Getter metadata still supports office review policy.
        expect(f.office.submissions.single['_state'], 'received');
        expect(
          await f.office.approvalProblem(f.office.submissions.single),
          isNull,
        );
        final receipt = await f.office.decide(
          first['id'] as String,
          approve: approve,
          reason: approve ? '' : 'Synthetic clean-command correction.',
        );
        expect(receipt['decision'], decision);
        expect(receipt['submissionHash'], contentHash(first));
        final reviewed = _databaseState(f.office);
        await expectLater(
          connection.request('/submit', _copy(first)..['_state'] = 'queued'),
          throwsStateError,
        );
        expect(_databaseState(f.office), reviewed);
        expect(await connection.request('/submit', first), {
          'accepted': first['id'],
        });
        expect(_databaseState(f.office), reviewed);
        await f.sync.sync();
        expect(f.phone.receipts, [receipt]);
        expect(f.phone.submissions.single['_state'], 'received');
      },
    );
  }

  for (final poison in ['duplicate version', 'local state']) {
    test(
      'Public import rejects $poison history before adopting new work or overwriting local drafts',
      () async {
        final history = await f.twoVersions();
        final target = await f.importTarget(history.seed);
        await target.update({
          'notes': 'Synthetic unsent local draft.',
        }, jobId: f.jobs[1]);
        final newId = await f.addOfficeJob();
        final clean = await f.office.publicBundle();
        final invalid = _copy(clean);
        final command = history.poisoned(poison);
        (invalid['submissions'] as List)[1] = command;
        (invalid['receipts'] as List)[1] = history.receiptFor(command);
        final baseline = _databaseState(target);
        final evidence = await _files(target.evidence.root);
        await expectLater(target.importOfficeBundle(invalid), throwsStateError);
        expect(_databaseState(target), baseline);
        expect(await _files(target.evidence.root), evidence);
        expect(target.jobs.map((j) => j['id']), isNot(contains(newId)));
        expect(target.receipts, [history.returned]);
        expect(
          valuesOf(await target.fields(jobId: f.jobs[1]))['notes'],
          'Synthetic unsent local draft.',
        );
        // No rejected ID was reserved; the original two valid versions import.
        await target.importOfficeBundle(clean);
        expect(target.jobs.map((j) => j['id']), contains(newId));
        expect(target.submissions.map((p) => p['documentHash']), [
          history.first['documentHash'],
          history.second['documentHash'],
        ]);
        expect(target.receipts, [history.returned, history.approved]);
        expect(
          valuesOf(await target.fields(jobId: f.jobs[1]))['notes'],
          'Synthetic unsent local draft.',
        );
      },
    );

    test(
      'Private backup rejects rehashed $poison history before publishing or touching the current office',
      () async {
        final history = await f.twoVersions();
        final backup = Directory('${f.root.path}/poisoned-backup');
        final summary = await OfficeBackup.create(f.office, backup);
        expect(
          (await OfficeBackup.inspect(
            backup,
            requiredFormat: OfficeBackupFormat.maintenance,
          )).receipts,
          2,
        );
        final command = history.poisoned(poison);
        await _poisonBackup(backup, command, history.receiptFor(command));
        final officeState = _databaseState(f.office);
        final backupFiles = await _files(backup);
        final stages = await _staging(f.root);
        final destination = Directory('${f.root.path}/rejected-restore');
        await expectLater(
          OfficeBackup.inspect(
            backup,
            requiredFormat: OfficeBackupFormat.maintenance,
          ),
          throwsStateError,
        );
        await expectLater(
          OfficeBackup.restore(
            backup,
            destination,
            expectedFingerprint: summary.fingerprint,
            requiredFormat: OfficeBackupFormat.maintenance,
          ),
          throwsStateError,
        );
        expect(await destination.exists(), isFalse);
        expect(await _staging(f.root), stages);
        expect(await _files(backup), backupFiles);
        expect(_databaseState(f.office), officeState);

        final validBackup = Directory('${f.root.path}/valid-backup');
        final valid = await OfficeBackup.create(f.office, validBackup);
        final restored = Directory('${f.root.path}/valid-restore');
        await OfficeBackup.restore(
          validBackup,
          restored,
          expectedFingerprint: valid.fingerprint,
          requiredFormat: OfficeBackupFormat.maintenance,
        );
        final reopened = await LabStore.open(
          restored,
          office: true,
          maintenanceOnly: true,
        );
        f.extraStores.add(reopened);
        expect(reopened.catalog, f.office.catalog);
        expect(reopened.submissions.map((p) => p['documentHash']), [
          history.first['documentHash'],
          history.second['documentHash'],
        ]);
        expect(reopened.receipts, [history.returned, history.approved]);
        for (final id in f.jobs) {
          expect(reopened.documentFor(id), f.office.documentFor(id));
        }
        expect(
          await reopened.evidence.complete(
            (history.first['values'] as Json)['photo'] as String,
          ),
          isTrue,
        );
      },
    );

    test(
      'Backup creation rejects saved $poison history without publishing a partial snapshot',
      () async {
        final history = await f.twoVersions();
        final command = history.poisoned(poison);
        _replaceSavedCommand(f.office.db, command, history.receiptFor(command));
        final baseline = _databaseState(f.office);
        final evidence = await _files(f.office.evidence.root);
        final stages = await _staging(f.root);
        final destination = Directory('${f.root.path}/rejected-backup');
        await expectLater(
          OfficeBackup.create(f.office, destination),
          throwsStateError,
        );
        expect(await destination.exists(), isFalse);
        expect(await _staging(f.root), stages);
        expect(_databaseState(f.office), baseline);
        expect(await _files(f.office.evidence.root), evidence);
      },
    );
  }
}
