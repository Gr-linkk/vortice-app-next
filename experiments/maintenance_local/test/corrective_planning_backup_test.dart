import 'dart:convert';
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/corrective_planning.dart';
import 'package:maintenance_local/corrective_planning_store.dart';
import 'package:maintenance_local/device_authority.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/local_sync.dart';
import 'package:maintenance_local/manual_fault_intake.dart';
import 'package:maintenance_local/manual_fault_intake_store.dart';
import 'package:maintenance_local/model.dart';
import 'package:maintenance_local/office_backup.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';
import 'package:sqlite3/sqlite3.dart';

import 'support/corrective_planning_legacy_backup_case.dart' as legacy;

void main() {
  setUpAll(() async {
    final native = Platform.environment['MAINTENANCE_NATIVE_LIBRARY']!;
    expect(digest(await File(native).readAsBytes()), legacy.acceptedNativeHash);
    await RustLib.init(externalLibrary: ExternalLibrary.open(native));
  });
  late Directory root;
  late LabStore office;
  late OfficeIdentity identity;
  late Json equipment;
  var clock = DateTime.utc(2026, 10, 1, 16);
  final stores = <LabStore>[];
  Directory path(String name) => Directory('${root.path}/$name');
  Future<LabStore> open(String name, {bool maintenanceOnly = true}) async {
    final store = await LabStore.open(
      path(name),
      office: true,
      maintenanceOnly: maintenanceOnly,
      now: () => clock,
    );
    stores.add(store);
    return store;
  }

  Future<void> close(LabStore store) async {
    await store.close();
    stores.remove(store);
  }

  setUp(() async {
    clock = DateTime.utc(2026, 10, 1, 16);
    root = await Directory.systemTemp.createTemp('corrective-backup-');
    office = await open('office');
    await office.createCompany(
      'Synthetic corrective recovery company',
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

  void tick() => clock = clock.add(const Duration(minutes: 1));
  String commandId(int number) =>
      'c2000000-0000-4000-8000-${number.toString().padLeft(12, '0')}';
  int version(LabStore store) =>
      store.db.select('PRAGMA user_version').single.values.single as int;
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

  String inspectionAndFaultState(LabStore store) {
    final snapshot = jsonDecode(legacy.retainedState(store.db)) as Json;
    (snapshot['settings'] as List).removeWhere(
      (row) => row['key'] == correctivePlanningSetting,
    );
    (snapshot['events'] as List).removeWhere(
      (row) => row['kind'] == correctivePlanningRecordedEvent,
    );
    return canonical(snapshot);
  }

  Future<CorrectivePlanningState> state(LabStore store) async {
    final settings = <String, dynamic>{
      for (final row in store.db.select('SELECT * FROM settings'))
        row['key'] as String: jsonDecode(row['value'] as String),
    };
    final events = <Json>[
      for (final row in store.db.select('SELECT * FROM events ORDER BY id'))
        {'kind': row['kind'], 'payload': jsonDecode(row['payload'] as String)},
    ];
    final faults = validateManualFaultIntake(
      settings: settings,
      events: events,
      catalog: store.catalog,
      deviceId: store.device,
      submissions: store.submissions,
      receipts: store.receipts,
    );
    return validateCorrectivePlanning(
      settings: settings,
      events: events,
      catalog: store.catalog,
      deviceId: store.device,
      manualFaultHistory: faults,
      databaseVersion: version(store),
    );
  }

  Future<List<ManualFaultRecord>> savedFaults() async {
    final publication = await office.publishChecklist(
      title: 'Synthetic saved inspection',
      items: [
        {'id': 'guard', 'label': 'Inspect the guard', 'input_type': 'check'},
      ],
    );
    final job = await office.prepareWork(
      equipmentId: equipment['id'] as String,
      templateId: publication['id'] as String,
      title: 'Synthetic inspection remains an inspection',
    );
    await office.update({
      'answer:guard': {'result': 'action', 'value': ''},
      'meter': 0,
      'notes':
          'Synthetic original note retained exactly; repair not performed.',
    }, jobId: job['id'] as String);
    await office.attach(
      utf8.encode('Synthetic original gallery evidence, retained exactly.'),
      jobId: job['id'] as String,
    );
    final submission = await office.submit(jobId: job['id'] as String);
    final intake = ManualFaultIntakeStore(office);
    final pendingOrigin = (await intake.availableOrigins(
      equipment['id'] as String,
    )).singleWhere((origin) => origin.kind == ManualFaultOriginKind.item);
    tick();
    final first = await intake.freeze(
      equipmentId: equipment['id'] as String,
      description: 'Synthetic pending-inspection original item finding.',
      severity: ManualFaultSeverity.normal,
      originSelection: pendingOrigin,
      commandId: commandId(1),
    );
    await intake.record(first);
    tick();
    await office.decide(submission['id'] as String, approve: true);
    final approvedOrigin = (await intake.availableOrigins(
      equipment['id'] as String,
    )).singleWhere((origin) => origin.kind == ManualFaultOriginKind.note);
    tick();
    final second = await intake.freeze(
      equipmentId: equipment['id'] as String,
      description: 'Synthetic approved-inspection original note finding.',
      severity: ManualFaultSeverity.urgent,
      originSelection: approvedOrigin,
      commandId: commandId(2),
    );
    await intake.record(second);
    tick();
    final third = await intake.freeze(
      equipmentId: equipment['id'] as String,
      description: 'Synthetic manual reported fault.',
      severity: ManualFaultSeverity.normal,
      commandId: commandId(3),
    );
    await intake.record(third);
    tick();
    await intake.freeze(
      equipmentId: equipment['id'] as String,
      description: 'Synthetic LF009 pending intake also survives recovery.',
      severity: ManualFaultSeverity.urgent,
      commandId: commandId(4),
    );
    return intake.listRecords();
  }

  Future<FrozenCorrectivePlanningCommand> populated() async {
    final faults = await savedFaults();
    final untouched = inspectionAndFaultState(office);
    final planning = CorrectivePlanningStore(office);
    tick();
    final create = await planning.freezeCreate(
      equipmentId: equipment['id'] as String,
      title: 'Synthetic corrective guard diagnosis',
      description: 'Inspect original findings and plan corrective work.',
      faultIds: [faults[0].id, faults[1].id],
      commandId: commandId(10),
    );
    var draft = (await planning.apply(create)).draft;
    tick();
    final edit = await planning.freezeEdit(
      draftId: draft.id,
      expectedRevision: draft.revision,
      expectedDraftHash: draft.hash,
      title: 'Synthetic revised corrective diagnosis',
      description: 'Revised planning instructions; no repair has been done.',
      commandId: commandId(11),
    );
    draft = (await planning.apply(edit)).draft;
    tick();
    final link = await planning.freezeLink(
      draftId: draft.id,
      expectedRevision: draft.revision,
      expectedDraftHash: draft.hash,
      faultIds: [faults[2].id],
      commandId: commandId(12),
    );
    draft = (await planning.apply(link)).draft;
    tick();
    final standalone = await planning.freezeCreate(
      equipmentId: equipment['id'] as String,
      title: 'Synthetic standalone corrective draft',
      description: '',
      commandId: commandId(13),
    );
    await planning.apply(standalone);
    tick();
    final pending = await planning.freezeEdit(
      draftId: draft.id,
      expectedRevision: draft.revision,
      expectedDraftHash: draft.hash,
      title: 'Synthetic recovered planning title',
      description:
          'Durable pending planning instructions awaiting exact replay.',
      commandId: commandId(14),
    );
    expect(inspectionAndFaultState(office), untouched);
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

  Future<Json> manifest() async =>
      jsonDecode(
            await File('${path('backup').path}/manifest.json').readAsString(),
          )
          as Json;
  Future<void> rehashBackup({int? manifestVersion}) async {
    final data = await manifest();
    if (manifestVersion != null) data['version'] = manifestVersion;
    final bytes = await File(
      '${path('backup').path}/workspace.sqlite',
    ).readAsBytes();
    (data['files'] as Json)['workspace.sqlite'] = {
      'hash': digest(bytes),
      'size': bytes.length,
    };
    await File(
      '${path('backup').path}/manifest.json',
    ).writeAsString(canonical(data), flush: true);
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
                    correctivePlanningSetting,
                  ]).single['value']
                  as String,
            )
            as Json;
    mutate(data);
    db.execute('UPDATE settings SET value=? WHERE key=?', [
      canonical(data),
      correctivePlanningSetting,
    ]);
  }

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
    'Schema2 planning recovery retains manifest2 and refuses a mismatched manifest3',
    () async {
      final intake = ManualFaultIntakeStore(office);
      await intake.freeze(
        equipmentId: equipment['id'] as String,
        description: 'Synthetic LF009 pending request in schema2.',
        severity: ManualFaultSeverity.normal,
        commandId: commandId(1),
      );
      final before = legacy.retainedState(office.db);
      final planning = CorrectivePlanningStore(office);
      expect(await planning.listDrafts(), isEmpty);
      expect(await planning.pendingCommands(), isEmpty);
      expect(version(office), 2);
      expect(office.setting(correctivePlanningSetting), isNull);
      await OfficeBackup.create(office, path('backup'));
      expect((await manifest())['version'], 2);
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
      expect(version(restored), 2);
      expect(legacy.retainedState(restored.db), before);
      expect(
        (await state(restored)).toJson(),
        CorrectivePlanningState.empty().toJson(),
      );
      expect(
        (await ManualFaultIntakeStore(restored).pendingCommands()).length,
        1,
      );
      await rehashBackup(manifestVersion: 3);
      await rejectsBeforePublish();
    },
  );

  test(
    'Legacy SyncLab manifest1 recovery remains intact with planning absent',
    () async {
      final source = await open('legacy-office', maintenanceOnly: false);
      await source.createWorkspace();
      final pin = (await OfficeIdentity.load(source)).fingerprint;
      final before = legacy.retainedState(source.db);
      await OfficeBackup.create(source, path('backup'));
      expect((await manifest())['format'], 'vortice-sync-lab-office');
      expect((await manifest())['version'], 1);
      await OfficeBackup.inspect(
        path('backup'),
        requiredFormat: OfficeBackupFormat.syncLab,
      );
      await expectLater(
        OfficeBackup.inspect(
          path('backup'),
          requiredFormat: OfficeBackupFormat.maintenance,
        ),
        throwsStateError,
      );
      await close(source);
      await OfficeBackup.restore(
        path('backup'),
        path('legacy-restored'),
        expectedFingerprint: pin,
        requiredFormat: OfficeBackupFormat.syncLab,
      );
      final restored = await open('legacy-restored', maintenanceOnly: false);
      expect(version(restored), 1);
      expect(legacy.retainedState(restored.db), before);
    },
  );

  test(
    'First durable planning intent alone survives schema3 backup and resumes exactly once',
    () async {
      final planning = CorrectivePlanningStore(office);
      final pending = await planning.freezeCreate(
        equipmentId: equipment['id'] as String,
        title: 'Synthetic pending standalone corrective draft',
        description: 'Planning only; corrective execution is not recorded.',
        commandId: commandId(10),
      );
      expect(version(office), 3);
      expect((await state(office)).receipts, isEmpty);
      final before = legacy.retainedState(office.db);
      await OfficeBackup.create(office, path('backup'));
      expect((await manifest())['version'], 3);
      await close(office);
      await OfficeBackup.restore(
        path('backup'),
        path('restored'),
        expectedFingerprint: identity.fingerprint,
        requiredFormat: OfficeBackupFormat.maintenance,
      );
      final restored = await open('restored');
      expect(legacy.retainedState(restored.db), before);
      final recovered = CorrectivePlanningStore(restored);
      expect(
        (await recovered.pendingCommands()).single.toJson(),
        pending.toJson(),
      );
      final accepted = await recovered.apply(pending);
      expect((await recovered.apply(pending)).toJson(), accepted.toJson());
      expect((await recovered.listDrafts()).single.kind, 'corrective');
      expect((await recovered.listDrafts()).single.state, 'draft');
      expect((await recovered.pendingCommands()), isEmpty);
      expect(
        restored.db.select('SELECT * FROM events WHERE kind=?', [
          correctivePlanningRecordedEvent,
        ]).length,
        1,
      );
    },
  );

  test(
    'Schema3 recovery retains draft revisions, links, both pending intents, sources and identity fences',
    () async {
      final pending = await populated();
      final original = await state(office);
      final before = legacy.retainedState(office.db);
      final untouched = inspectionAndFaultState(office);
      final media = await inventory(office.evidence.root);
      final keyHash = digest(
        await File('${office.root.path}/office-key.pem').readAsBytes(),
      );
      expect(original.receipts.length, 4);
      expect(original.drafts.length, 2);
      expect(original.draftFor(pending.draftId)!.revision, 3);
      expect(original.draftFor(pending.draftId)!.faults.length, 3);
      await OfficeBackup.create(office, path('backup'));
      expect((await manifest())['version'], 3);
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
      expect(version(restored), 3);
      expect(legacy.retainedState(restored.db), before);
      expect((await state(restored)).toJson(), original.toJson());
      expect(await inventory(restored.evidence.root), media);
      expect(
        (await OfficeIdentity.load(restored)).fingerprint,
        identity.fingerprint,
      );
      expect(
        digest(
          await File('${restored.root.path}/office-key.pem').readAsBytes(),
        ),
        keyHash,
      );
      expect(DeviceAuthority(restored).phones.map((row) => row['status']), [
        'pending',
        'pending',
        'revoked',
      ]);
      expect(restored.db.select('SELECT * FROM invites'), isEmpty);
      expect(
        (await ManualFaultIntakeStore(restored).pendingCommands()).length,
        1,
      );
      final planning = CorrectivePlanningStore(restored);
      expect(
        (await planning.pendingCommands()).single.toJson(),
        pending.toJson(),
      );
      final accepted = await planning.apply(pending);
      expect((await planning.apply(pending)).toJson(), accepted.toJson());
      final after = await state(restored);
      expect(after.receipts.length, 5);
      expect(
        after.receipts.take(4).map((r) => r.toJson()).toList(),
        original.receipts.map((r) => r.toJson()).toList(),
      );
      expect(after.draftFor(pending.draftId)!.revision, 4);
      expect(after.draftFor(pending.draftId)!.faults.length, 3);
      expect(
        after.drafts.every((d) => d.kind == 'corrective' && d.state == 'draft'),
        isTrue,
      );
      expect(
        (await ManualFaultIntakeStore(
          restored,
        ).listRecords()).every((r) => r.status == manualFaultReportedStatus),
        isTrue,
      );
      expect(
        restored.db.select('SELECT * FROM events WHERE kind=?', [
          correctivePlanningRecordedEvent,
        ]).length,
        5,
      );
      expect(inspectionAndFaultState(restored), untouched);
      expect(restored.jobs.length, 1);
    },
  );

  for (final corruption in [
    'future-ledger',
    'empty-ledger',
    'missing-planning',
    'unsupported-schema',
  ]) {
    test(
      '$corruption retains source and refuses creation before publication',
      () async {
        await populated();
        switch (corruption) {
          case 'future-ledger':
            changeState(office.db, (data) => data['version'] = 2);
          case 'empty-ledger':
            office.setSetting(correctivePlanningSetting, {
              'version': 1,
              'pending': <Json>[],
              'receipts': <Json>[],
            });
          case 'missing-planning':
            office.db.execute('DELETE FROM settings WHERE key=?', [
              correctivePlanningSetting,
            ]);
          case 'unsupported-schema':
            office.db.execute('PRAGMA user_version=4');
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
    'manifest-mismatch',
    'unsupported-manifest',
    'unsupported-schema',
    'missing-planning',
    'future-ledger',
    'missing-event',
    'wrong-fault-reference',
  ]) {
    test(
      'Rehashed $corruption refuses inspect and restore retaining all backup bytes',
      () async {
        await populated();
        await OfficeBackup.create(office, path('backup'));
        if (corruption == 'manifest-mismatch' ||
            corruption == 'unsupported-manifest') {
          await rehashBackup(
            manifestVersion: corruption == 'manifest-mismatch' ? 2 : 4,
          );
        } else {
          await mutateBackup((db) {
            switch (corruption) {
              case 'unsupported-schema':
                db.execute('PRAGMA user_version=4');
              case 'missing-planning':
                db.execute('DELETE FROM settings WHERE key=?', [
                  correctivePlanningSetting,
                ]);
              case 'future-ledger':
                changeState(db, (data) => data['version'] = 2);
              case 'missing-event':
                db.execute('DELETE FROM events WHERE kind=?', [
                  correctivePlanningRecordedEvent,
                ]);
              case 'wrong-fault-reference':
                changeState(db, (data) {
                  final receipt = data['receipts'][0] as Json;
                  final command = receipt['command'] as Json;
                  (command['faults'][0] as Json)['faultRecordHash'] = '0' * 64;
                  command.remove('hash');
                  command['hash'] = contentHash(command);
                  final replacement = CorrectivePlanningReceipt.create(
                    FrozenCorrectivePlanningCommand.fromJson(command),
                    previousDraft: null,
                    recordedAt: receipt['recordedAt'] as String,
                  ).toJson();
                  data['receipts'][0] = replacement;
                  final event = db.select(
                    'SELECT id FROM events WHERE kind=? ORDER BY id',
                    [correctivePlanningRecordedEvent],
                  ).first;
                  db.execute('UPDATE events SET payload=? WHERE id=?', [
                    canonical(replacement),
                    event['id'],
                  ]);
                });
            }
          });
        }
        await rejectsBeforePublish();
      },
    );
  }
}
