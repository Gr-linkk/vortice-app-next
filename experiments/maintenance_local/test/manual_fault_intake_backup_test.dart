import 'dart:convert';
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/device_authority.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/local_sync.dart';
import 'package:maintenance_local/manual_fault_intake.dart';
import 'package:maintenance_local/manual_fault_intake_store.dart';
import 'package:maintenance_local/model.dart';
import 'package:maintenance_local/office_backup.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';
import 'package:sqlite3/sqlite3.dart';

import 'support/manual_fault_intake_legacy_backup_runner.dart' as legacy;

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
  late Directory root;
  late LabStore office;
  late OfficeIdentity identity;
  late Json equipment;
  var clock = DateTime.utc(2026, 10, 1, 12);
  final stores = <LabStore>[];
  Directory path(String name) => Directory('${root.path}/$name');
  Future<void> close(LabStore store) async {
    await store.close();
    stores.remove(store);
  }

  Future<LabStore> open(String name) async {
    final store = await LabStore.open(
      path(name),
      office: true,
      maintenanceOnly: true,
      now: () => clock,
    );
    stores.add(store);
    return store;
  }

  setUp(() async {
    clock = DateTime.utc(2026, 10, 1, 12);
    root = await Directory.systemTemp.createTemp('manual-fault-backup-');
    office = await open('office');
    await office.createCompany(
      'Synthetic fault recovery company',
      coordinatorName: 'Synthetic coordinator',
    );
    identity = await OfficeIdentity.load(office);
    equipment = await office.addEquipment(name: 'Synthetic excavator');
  });
  tearDown(() async {
    for (final store in stores) {
      await store.close();
    }
    stores.clear();
    await root.delete(recursive: true);
  });

  String commandId(int number) =>
      'b2000000-0000-4000-8000-${number.toString().padLeft(12, '0')}';
  void tick() => clock = clock.add(const Duration(minutes: 1));
  Future<Json> submission(String label) async {
    final publication = await office.publishChecklist(
      title: 'Synthetic inspection $label',
      items: [
        {
          'id': 'guard',
          'label': 'Inspect the synthetic guard',
          'input_type': 'check',
        },
      ],
    );
    final job = await office.prepareWork(
      equipmentId: equipment['id'] as String,
      templateId: publication['id'] as String,
      title: 'Synthetic saved inspection $label',
    );
    await office.update({
      'answer:guard': {'result': 'action', 'value': ''},
      'meter': 0,
      'notes': 'Synthetic original finding $label; preserve exactly.',
    }, jobId: job['id'] as String);
    await office.attach(
      utf8.encode('Synthetic gallery evidence $label'),
      jobId: job['id'] as String,
    );
    return office.submit(jobId: job['id'] as String);
  }

  Future<ManualFaultReceipt> record(
    int number, {
    ManualFaultOrigin? origin,
    ManualFaultSeverity severity = ManualFaultSeverity.normal,
  }) async {
    tick();
    final intake = ManualFaultIntakeStore(office);
    final command = await intake.freeze(
      equipmentId: equipment['id'] as String,
      description: 'Synthetic manual fault $number',
      severity: severity,
      originSelection: origin,
      commandId: commandId(number),
    );
    return intake.record(command);
  }

  Future<ManualFaultIntakeState> state(LabStore store) async =>
      validateManualFaultIntake(
        settings: {
          for (final row in store.db.select('SELECT * FROM settings'))
            row['key'] as String: jsonDecode(row['value'] as String),
        },
        events: [
          for (final row in store.db.select('SELECT * FROM events ORDER BY id'))
            {
              'kind': row['kind'],
              'payload': jsonDecode(row['payload'] as String),
            },
        ],
        catalog: store.catalog,
        deviceId: store.device,
        submissions: store.submissions,
        receipts: store.receipts,
      );

  Future<FrozenManualFaultCommand> populated() async {
    final intake = ManualFaultIntakeStore(office);
    final first = await submission('pending-at-capture');
    tick();
    final pendingOrigin =
        (await intake.availableOrigins(equipment['id'] as String)).singleWhere(
          (origin) =>
              origin.submissionId == first['id'] &&
              origin.kind == ManualFaultOriginKind.item,
        );
    await record(1, origin: pendingOrigin);
    tick();
    await office.decide(first['id'] as String, approve: true);

    final second = await submission('approved-at-capture');
    tick();
    await office.decide(second['id'] as String, approve: true);
    final approvedOrigin =
        (await intake.availableOrigins(equipment['id'] as String)).singleWhere(
          (origin) =>
              origin.submissionId == second['id'] &&
              origin.kind == ManualFaultOriginKind.note,
        );
    await record(2, origin: approvedOrigin);

    final third = await submission('returned-at-capture');
    tick();
    await office.decide(
      third['id'] as String,
      approve: false,
      reason: 'Synthetic inspection correction requested.',
    );
    final returnedOrigin =
        (await intake.availableOrigins(equipment['id'] as String)).singleWhere(
          (origin) =>
              origin.submissionId == third['id'] &&
              origin.kind == ManualFaultOriginKind.submission,
        );
    await record(3, origin: returnedOrigin);
    await record(4, severity: ManualFaultSeverity.urgent);
    tick();
    final pending = await intake.freeze(
      equipmentId: equipment['id'] as String,
      description: 'Synthetic durable request awaiting exact replay.',
      severity: ManualFaultSeverity.urgent,
      originSelection: returnedOrigin,
      commandId: commandId(5),
    );
    // Unknown legacy-compatible data must survive whole-database recovery too.
    office.setSetting('syntheticUnknownSetting', {'retain': 'exact'});
    office.event('synthetic-unknown-event', {'retain': 'exact'});
    final authority = DeviceAuthority(office);
    for (final status in ['active', 'pending', 'revoked']) {
      final id = 'synthetic-$status-phone';
      authority.request({
        'device': id,
        'label': 'Synthetic $status phone',
        'token': secret(),
        'invitation': authority.invite(),
      });
      if (status == 'active') authority.confirm(id);
      if (status == 'revoked') authority.revoke(id);
    }
    return pending;
  }

  Future<void> rehashBackup() async {
    final manifestFile = File('${path('backup').path}/manifest.json');
    final manifest = jsonDecode(await manifestFile.readAsString()) as Json;
    final bytes = await File(
      '${path('backup').path}/workspace.sqlite',
    ).readAsBytes();
    (manifest['files'] as Json)['workspace.sqlite'] = {
      'hash': digest(bytes),
      'size': bytes.length,
    };
    await manifestFile.writeAsString(canonical(manifest), flush: true);
  }

  Future<void> mutateBackup(void Function(Database) mutate) async {
    final db = sqlite3.open('${path('backup').path}/workspace.sqlite');
    try {
      mutate(db);
    } finally {
      db.close();
    }
    await rehashBackup();
  }

  void changeState(Database db, void Function(Json) mutate) {
    final data =
        jsonDecode(
              db.select('SELECT value FROM settings WHERE key=?', [
                    manualFaultIntakeSetting,
                  ]).single['value']
                  as String,
            )
            as Json;
    mutate(data);
    db.execute('UPDATE settings SET value=? WHERE key=?', [
      canonical(data),
      manualFaultIntakeSetting,
    ]);
  }

  Future<Json> inventory(Directory directory) async => {
    for (final file in await directory.list(recursive: true).toList())
      if (file is File)
        file.path.substring(directory.path.length + 1): digest(
          await file.readAsBytes(),
        ),
  };

  Future<void> rejectsBeforePublish() async {
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
  }

  test(
    'Absent fault namespace remains an empty compatible old workspace',
    () async {
      final before = legacy.retainedState(office.db);
      await OfficeBackup.create(office, path('backup'));
      await OfficeBackup.inspect(
        path('backup'),
        requiredFormat: OfficeBackupFormat.maintenance,
      );
      await close(office);
      await expectLater(
        OfficeBackup.restore(
          path('backup'),
          path('wrong-pin'),
          expectedFingerprint: '0' * 64,
          requiredFormat: OfficeBackupFormat.maintenance,
        ),
        throwsStateError,
      );
      expect(await path('wrong-pin').exists(), isFalse);
      await OfficeBackup.restore(
        path('backup'),
        path('restored'),
        expectedFingerprint: identity.fingerprint,
        requiredFormat: OfficeBackupFormat.maintenance,
      );
      final restored = await open('restored');
      expect(
        (await state(restored)).toJson(),
        ManualFaultIntakeState.empty().toJson(),
      );
      expect(legacy.retainedState(restored.db), before);
    },
  );

  test(
    'New recovery preserves exact origins, pending request, inspection bytes and identity fences',
    () async {
      final pending = await populated();
      final before = legacy.retainedState(office.db);
      final originalState = await state(office);
      expect(
        originalState.receipts.map((r) => r.record.origin?.observation.name),
        ['pending', 'approved', 'returned', null],
      );
      await OfficeBackup.create(office, path('backup'));
      await OfficeBackup.inspect(
        path('backup'),
        requiredFormat: OfficeBackupFormat.maintenance,
      );
      await close(office);
      await OfficeBackup.restore(
        path('backup'),
        path('restored'),
        expectedFingerprint: identity.fingerprint,
        requiredFormat: OfficeBackupFormat.maintenance,
      );
      final restored = await open('restored');
      expect(legacy.retainedState(restored.db), before);
      expect((await state(restored)).toJson(), originalState.toJson());
      expect(
        (await OfficeIdentity.load(restored)).fingerprint,
        identity.fingerprint,
      );
      expect(DeviceAuthority(restored).phones.map((row) => row['status']), [
        'pending',
        'pending',
        'revoked',
      ]);
      expect(restored.db.select('SELECT * FROM invites'), isEmpty);
      final intake = ManualFaultIntakeStore(restored);
      expect(
        (await intake.pendingCommands()).single.toJson(),
        pending.toJson(),
      );
      final accepted = await intake.record(pending);
      expect((await intake.record(pending)).toJson(), accepted.toJson());
      expect((await intake.listRecords()).length, 5);
      expect(
        restored.db.select('SELECT * FROM events WHERE kind=?', [
          manualFaultReportedEvent,
        ]).length,
        5,
      );
      expect(
        (await state(restored)).receipts.first.record.origin!.observation,
        ManualFaultObservation.pending,
      );
      expect(
        (await state(
          restored,
        )).receipts.every((r) => r.record.status == manualFaultReportedStatus),
        isTrue,
      );
    },
  );

  for (final corruption in [
    'future-version',
    'malformed-pending',
    'orphan-event',
  ]) {
    test(
      '$corruption fault state retains source and rejects creation before publication',
      () async {
        await populated();
        if (corruption == 'orphan-event') {
          office.db.execute('DELETE FROM settings WHERE key=?', [
            manualFaultIntakeSetting,
          ]);
        } else {
          final invalid = office.setting(manualFaultIntakeSetting) as Json;
          if (corruption == 'future-version') {
            invalid['version'] = 999;
          } else {
            invalid['pending'] = {'not': 'a list'};
          }
          office.setSetting(manualFaultIntakeSetting, invalid);
        }
        final before = legacy.retainedState(office.db);
        await expectLater(
          OfficeBackup.create(office, path('backup')),
          throwsStateError,
        );
        expect(await path('backup').exists(), isFalse);
        expect(legacy.retainedState(office.db), before);
        expect(
          (await root.list().toList()).where(
            (entry) => entry.path.contains('.office-recovery-'),
          ),
          isEmpty,
        );
      },
    );
  }

  for (final corruption in [
    'future-version',
    'malformed-pending',
    'missing-event',
    'orphan-event',
    'wrong-source-item',
  ]) {
    test(
      'Rehashed $corruption fault history refuses inspect and restore without changing bytes',
      () async {
        await populated();
        await OfficeBackup.create(office, path('backup'));
        await mutateBackup((db) {
          switch (corruption) {
            case 'future-version':
              changeState(db, (data) => data['version'] = 2);
            case 'malformed-pending':
              changeState(db, (data) => data['pending'] = {'not': 'a list'});
            case 'missing-event':
              db.execute('DELETE FROM events WHERE kind=?', [
                manualFaultReportedEvent,
              ]);
            case 'orphan-event':
              db.execute('DELETE FROM settings WHERE key=?', [
                manualFaultIntakeSetting,
              ]);
            case 'wrong-source-item':
              changeState(db, (data) {
                final receipt = data['receipts'][0] as Json;
                final input = receipt['command'] as Json;
                (input['origin'] as Json)['itemId'] = 'unseen-original-item';
                input.remove('hash');
                input['hash'] = contentHash(input);
                final replacement = ManualFaultReceipt.create(
                  FrozenManualFaultCommand.fromJson(input),
                  reportedAt: receipt['record']['reportedAt'] as String,
                ).toJson();
                data['receipts'][0] = replacement;
                final event = db.select(
                  'SELECT id FROM events WHERE kind=? ORDER BY id',
                  [manualFaultReportedEvent],
                ).first;
                db.execute('UPDATE events SET payload=? WHERE id=?', [
                  canonical(replacement),
                  event['id'],
                ]);
              });
          }
        });
        await rejectsBeforePublish();
      },
    );
  }

  test(
    'Actual accepted98 old backup implementation retains new ledger, pending intent and history',
    () async {
      await populated();
      final before = legacy.retainedState(office.db);
      final expectedState = (await state(office)).toJson();
      await close(office);
      final app = Directory.current.absolute;
      final repository = app.parent.parent;
      final oldRoot = Directory(
        '${repository.path}/work/manual-fault-legacy-${root.uri.pathSegments.where((s) => s.isNotEmpty).last}',
      );
      Future<void> command(
        List<String> args, {
        String? cwd,
        Map<String, String>? env,
      }) async {
        final result = await Process.run(
          args.first,
          args.skip(1).toList(),
          workingDirectory: cwd,
          environment: env,
        );
        expect(
          result.exitCode,
          0,
          reason: '${args.first}: ${result.stdout}\n${result.stderr}',
        );
      }

      try {
        await command([
          'git',
          'clone',
          '--no-hardlinks',
          '--no-checkout',
          repository.path,
          oldRoot.path,
        ]);
        await command([
          'git',
          '-C',
          oldRoot.path,
          'checkout',
          '--detach',
          legacy.legacyRevision,
        ]);
        final oldApp = Directory(
          '${oldRoot.path}/experiments/maintenance_local',
        );
        final oldWork = Directory(
          '${oldRoot.path}/work/manual-fault-toolchain',
        );
        await oldWork.create(recursive: true);
        for (final name in ['flutter', 'pub']) {
          await command([
            'cp',
            '-R',
            '${repository.path}/work/manual-fault-toolchain/$name',
            '${oldWork.path}/$name',
          ]);
        }
        for (final name in [
          'manual_fault_intake_legacy_backup_runner.dart',
          'manual_fault_intake_legacy_backup_case.dart',
        ]) {
          await File(
            '${app.path}/test/support/$name',
          ).copy('${oldApp.path}/test/support/$name');
        }
        final env = {
          ...Platform.environment,
          'PATH': '${oldWork.path}/flutter/bin:/usr/local/bin:/usr/bin:/bin',
          'HOME': '${oldWork.path}/home',
          'PUB_CACHE': '${oldWork.path}/pub',
          'FLUTTER_ROOT': '${oldWork.path}/flutter',
          'CI': 'true',
          'FLUTTER_SUPPRESS_ANALYTICS': 'true',
          'DART_SUPPRESS_ANALYTICS': 'true',
          'MANUAL_FAULT_LEGACY_ARGS': canonical([
            path('office').path,
            path('old-backup').path,
            path('old-restored').path,
            identity.fingerprint,
            path('legacy-proof.json').path,
          ]),
        };
        await Directory(env['HOME']!).create(recursive: true);
        await command(
          [
            '${oldWork.path}/flutter/bin/flutter',
            'pub',
            'get',
            '--offline',
            '--enforce-lockfile',
          ],
          cwd: oldApp.path,
          env: env,
        );
        const sqliteCache =
            '.dart_tool/hooks_runner/shared/sqlite3/build/download-2219febf/libsqlite3.so';
        final cachedSqlite = File('${app.path}/$sqliteCache');
        expect(
          digest(await cachedSqlite.readAsBytes()),
          '2219febf70a5ed39a39db1bc46e00d3df0b3bb881ad36a67e2e5a0cd91ebd3a5',
        );
        final oldSqlite = File('${oldApp.path}/$sqliteCache');
        await oldSqlite.parent.create(recursive: true);
        await cachedSqlite.copy(oldSqlite.path);
        expect(
          digest(await oldSqlite.readAsBytes()),
          digest(await cachedSqlite.readAsBytes()),
        );
        final cacheInodes = await Future.wait([
          Process.run('stat', ['-c', '%d:%i', cachedSqlite.path]),
          Process.run('stat', ['-c', '%d:%i', oldSqlite.path]),
        ]);
        expect(cacheInodes.every((result) => result.exitCode == 0), isTrue);
        final sourceInode = cacheInodes[0].stdout.toString().trim();
        final destinationInode = cacheInodes[1].stdout.toString().trim();
        expect(destinationInode, isNot(sourceInode));
        await command(
          [
            '${oldWork.path}/flutter/bin/flutter',
            'test',
            '--no-pub',
            '--concurrency=1',
            'test/support/manual_fault_intake_legacy_backup_case.dart',
          ],
          cwd: oldApp.path,
          env: env,
        );
        final proof =
            jsonDecode(
                  await File(path('legacy-proof.json').path).readAsString(),
                )
                as Json;
        expect(proof['sourceRevision'], legacy.legacyRevision);
        expect(proof['officeBackupSha256'], legacy.legacyBackupHash);
        expect(proof['createdInspectedRestoredAndReopened'], isTrue);
        expect(proof['sourceRetainedHash'], digest(utf8.encode(before)));
        expect(proof['backupRetainedHash'], proof['sourceRetainedHash']);
        expect(proof['restoredRetainedHash'], proof['sourceRetainedHash']);
        expect(proof['fingerprint'], identity.fingerprint);
        expect(proof['phonesToReconfirm'], 2);
        expect(proof['revokedPhones'], 1);
        proof['legacySqliteCache'] = {
          'source': cachedSqlite.path,
          'destination': oldSqlite.path,
          'sourceSha256': digest(await cachedSqlite.readAsBytes()),
          'destinationSha256': digest(await oldSqlite.readAsBytes()),
          'sourceDeviceAndInode': sourceInode,
          'destinationDeviceAndInode': destinationInode,
          'distinctFiles': true,
        };
        // The new semantic boundary accepts actual old-produced recovery records.
        await OfficeBackup.inspect(
          path('old-backup'),
          requiredFormat: OfficeBackupFormat.maintenance,
        );
        final restored = await open('old-restored');
        expect((await state(restored)).toJson(), expectedState);
        expect(legacy.retainedState(restored.db), before);
        await OfficeBackup.create(
          restored,
          path('new-backup-from-old-restored'),
        );
        // Durable supporting receipt contains hashes, never private key bytes.
        final output = Directory(
          '${repository.path}/outputs/manual-fault-intake',
        );
        await output.create(recursive: true);
        await File(
          '${output.path}/legacy-backup-proof.json',
        ).writeAsString(canonical(proof), flush: true);
      } finally {
        if (await oldRoot.exists()) await oldRoot.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
