import 'dart:convert';
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/local_sync.dart';
import 'package:maintenance_local/manual_fault_intake.dart';
import 'package:maintenance_local/manual_fault_intake_store.dart';
import 'package:maintenance_local/model.dart';
import 'package:maintenance_local/office_backup.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';
import 'package:sqlite3/sqlite3.dart';

// New compatibility helper only. Its production package map must remain the
// exact reviewed LF009 reader; no LF010 implementation is needed for this proof.
const legacyRevision = 'fc086136e1cf9cbfc4ab90c844d2cff62e2d2ea9';
const legacyStoreHash =
    '08709d0a9578f96ca4bae8fc458680cce927309506ada8b97f92ee2ad14ff6b5';
const legacyBackupHash =
    'b6f1997c5bc1acc6ef6473179d77d9f9a6b10e997c368a427574a08bde1d8c85';
const acceptedNativeHash =
    '582b0b00d645d9683512d4426729c633985302322232e3413fca4e7fe015d412';

String retainedState(Database db) => canonical({
  'settings': [
    for (final row in db.select(
      "SELECT * FROM settings WHERE key<>'officeRestore' ORDER BY key",
    ))
      {'key': row['key'], 'value': row['value']},
  ],
  'documents': [
    for (final row in db.select('SELECT * FROM documents ORDER BY id'))
      {'id': row['id'], 'bytes': base64Encode(row['bytes'] as List<int>)},
  ],
  'submissions': [
    for (final row in db.select('SELECT * FROM submissions ORDER BY id'))
      Map<String, dynamic>.from(row),
  ],
  'receipts': [
    for (final row in db.select('SELECT * FROM receipts ORDER BY id'))
      Map<String, dynamic>.from(row),
  ],
  'events': [
    for (final row in db.select(
      "SELECT * FROM events WHERE kind<>'office-restored' ORDER BY id",
    ))
      Map<String, dynamic>.from(row),
  ],
});

void main() {
  final proof = <String, dynamic>{};
  setUpAll(() async {
    final revision = await Process.run('git', ['rev-parse', 'HEAD']);
    expect(revision.exitCode, 0);
    expect(revision.stdout.toString().trim(), legacyRevision);
    expect(
      digest(await File('lib/lab_store.dart').readAsBytes()),
      legacyStoreHash,
    );
    expect(
      digest(await File('lib/office_backup.dart').readAsBytes()),
      legacyBackupHash,
    );
    final native = Platform.environment['MAINTENANCE_NATIVE_LIBRARY']!;
    expect(digest(await File(native).readAsBytes()), acceptedNativeHash);
    await RustLib.init(externalLibrary: ExternalLibrary.open(native));
    proof.addAll({
      'sourceRevision': legacyRevision,
      'labStoreSha256': legacyStoreHash,
      'officeBackupSha256': legacyBackupHash,
      'nativeSha256': acceptedNativeHash,
      'productionImplementationUnchanged': true,
      'checks': <String, dynamic>{},
    });
  });
  tearDownAll(() async {
    final repository = Directory.current.parent.parent;
    final output = Directory('${repository.path}/outputs/corrective-planning');
    await output.create(recursive: true);
    await File(
      '${output.path}/legacy-format-fence-proof.json',
    ).writeAsString(canonical(proof), flush: true);
  });
  late Directory root;
  late LabStore office;
  late OfficeIdentity identity;
  var opened = false;
  Directory path(String name) => Directory('${root.path}/$name');
  Future<void> close() async {
    if (opened) {
      await office.close();
      opened = false;
    }
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('corrective-legacy-');
    office = await LabStore.open(
      path('office'),
      office: true,
      maintenanceOnly: true,
      now: () => DateTime.utc(2026, 10, 1, 15),
    );
    opened = true;
    await office.createCompany(
      'Synthetic corrective compatibility company',
      coordinatorName: 'Synthetic coordinator',
    );
    identity = await OfficeIdentity.load(office);
    final equipment = await office.addEquipment(name: 'Synthetic excavator');
    final intake = ManualFaultIntakeStore(office);
    final recorded = await intake.freeze(
      equipmentId: equipment['id'] as String,
      description: 'Synthetic accepted LF009 fault retained by rollback.',
      severity: ManualFaultSeverity.normal,
      commandId: 'c1000000-0000-4000-8000-000000000001',
    );
    await intake.record(recorded);
    await intake.freeze(
      equipmentId: equipment['id'] as String,
      description: 'Synthetic accepted LF009 durable pending request.',
      severity: ManualFaultSeverity.urgent,
      commandId: 'c1000000-0000-4000-8000-000000000002',
    );
    expect(office.db.select('PRAGMA user_version').single.values.single, 2);
  });
  tearDown(() async {
    await close();
    await root.delete(recursive: true);
  });

  Future<Json> inventory(Directory directory) async {
    final files =
        (await directory.list(recursive: true).toList())
            .whereType<File>()
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    return {
      for (final file in files)
        file.path.substring(directory.path.length + 1): digest(
          await file.readAsBytes(),
        ),
    };
  }

  void syntheticSchema3(Directory directory) {
    final db = sqlite3.open('${directory.path}/workspace.sqlite');
    try {
      // Deliberately synthetic format marker; no real migration or draft API.
      db.execute('BEGIN IMMEDIATE');
      db.execute('INSERT INTO settings(key,value) VALUES(?,?)', [
        'syntheticUnsupportedFormatSentinel',
        canonical({'retained': 'exact bytes', 'synthetic': true}),
      ]);
      db.execute('PRAGMA user_version=3');
      db.execute('COMMIT');
      db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    } finally {
      db.close();
    }
  }

  Future<void> retagBackup(int manifestVersion) async {
    final manifestFile = File('${path('backup').path}/manifest.json');
    final manifest = jsonDecode(await manifestFile.readAsString()) as Json;
    manifest['version'] = manifestVersion;
    final bytes = await File(
      '${path('backup').path}/workspace.sqlite',
    ).readAsBytes();
    (manifest['files'] as Json)['workspace.sqlite'] = {
      'hash': digest(bytes),
      'size': bytes.length,
    };
    await manifestFile.writeAsString(canonical(manifest), flush: true);
  }

  test(
    'Exact fc schema2 still opens and creates, inspects, restores and reopens',
    () async {
      final before = retainedState(office.db);
      await OfficeBackup.create(office, path('backup'));
      await close();
      final source = await LabStore.open(
        path('office'),
        office: true,
        maintenanceOnly: true,
      );
      try {
        expect(retainedState(source.db), before);
      } finally {
        await source.close();
      }
      final summary = await OfficeBackup.inspect(
        path('backup'),
        requiredFormat: OfficeBackupFormat.maintenance,
      );
      expect(summary.fingerprint, identity.fingerprint);
      await OfficeBackup.restore(
        path('backup'),
        path('restored'),
        expectedFingerprint: identity.fingerprint,
        requiredFormat: OfficeBackupFormat.maintenance,
      );
      final restored = await LabStore.open(
        path('restored'),
        office: true,
        maintenanceOnly: true,
      );
      try {
        expect(
          restored.db.select('PRAGMA user_version').single.values.single,
          2,
        );
        expect(retainedState(restored.db), before);
        final intake = ManualFaultIntakeStore(restored);
        expect((await intake.listRecords()).length, 1);
        expect((await intake.pendingCommands()).length, 1);
      } finally {
        await restored.close();
      }
      (proof['checks'] as Json)['schema2Control'] = {
        'openedCreatedInspectedRestoredAndReopened': true,
        'retainedStateSha256': digest(utf8.encode(before)),
        'savedManualFaultAndPendingCommandRetained': true,
      };
    },
  );

  test(
    'Exact fc schema3 workspace refuses open while retaining every file byte',
    () async {
      await close();
      syntheticSchema3(path('office'));
      final before = await inventory(path('office'));
      await expectLater(
        LabStore.open(path('office'), office: true, maintenanceOnly: true),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'retention message',
            contains('files have been retained'),
          ),
        ),
      );
      expect(await inventory(path('office')), before);
      (proof['checks'] as Json)['schema3WorkspaceRefused'] = {
        'refused': true,
        'allFileBytesRetained': true,
        'inventorySha256': contentHash(before),
      };
    },
  );

  for (final manifestVersion in [2, 3]) {
    test(
      'Exact fc schema3 backup with manifest$manifestVersion refuses inspect and restore retaining bytes',
      () async {
        await OfficeBackup.create(office, path('backup'));
        await close();
        syntheticSchema3(path('backup'));
        await retagBackup(manifestVersion);
        final before = await inventory(path('backup'));
        await expectLater(
          OfficeBackup.inspect(
            path('backup'),
            requiredFormat: OfficeBackupFormat.maintenance,
          ),
          throwsStateError,
        );
        await expectLater(
          OfficeBackup.restore(
            path('backup'),
            path('rejected'),
            expectedFingerprint: identity.fingerprint,
            requiredFormat: OfficeBackupFormat.maintenance,
          ),
          throwsStateError,
        );
        expect(await path('rejected').exists(), isFalse);
        expect(await inventory(path('backup')), before);
        expect(
          (await root.list().toList()).where(
            (entry) => entry.path.contains('.office-recovery-'),
          ),
          isEmpty,
        );
        (proof['checks']
            as Json)['manifest${manifestVersion}Schema3Refused'] = {
          'inspectRefused': true,
          'restoreRefused': true,
          'allBackupFileBytesRetained': true,
          'destinationNotPublished': true,
          'inventorySha256': contentHash(before),
        };
      },
    );
  }
}
