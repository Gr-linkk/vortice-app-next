import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/corrective_planning.dart';
import 'package:maintenance_local/corrective_planning_store.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/manual_fault_intake.dart';
import 'package:maintenance_local/manual_fault_intake_store.dart';
import 'package:maintenance_local/model.dart';
import 'package:sqlite3/sqlite3.dart';

import 'inspection_editor_coherence_support.dart';

const _a = '11111111-1111-4111-8111-111111111111';
const _b = '22222222-2222-4222-8222-222222222222';
const _c = '33333333-3333-4333-8333-333333333333';
const _d = '44444444-4444-4444-8444-444444444444';
const _f1 = '77777777-7777-4777-8777-777777777777';
const _f2 = '88888888-8888-4888-8888-888888888888';

/// Keeps the real queue/database/transaction while injecting bounded failures.
class _PlanningStore implements LabStore {
  _PlanningStore(this.inner);
  final LabStore inner;
  bool authorized = true;
  bool failAfterSetting = false;
  bool revokeAfterSetting = false;
  bool sawSchemaThreeAfterRevocation = false;
  bool failEvent = false;
  bool failAfterCommit = false;
  bool revokeAtTransaction = false;
  void Function()? beforeTransaction;
  String? overrideStamp;
  @override
  bool get office {
    if (!authorized && _version(inner) == 3) {
      sawSchemaThreeAfterRevocation = true;
    }
    return authorized && inner.office;
  }

  @override
  Database get db => inner.db;
  @override
  SerialQueue get queue => inner.queue;
  @override
  Json? get catalog => inner.catalog;
  @override
  String get device => inner.device;
  @override
  List<Json> get submissions => inner.submissions;
  @override
  List<Json> get receipts => inner.receipts;
  @override
  String stamp() => overrideStamp ?? inner.stamp();
  @override
  void requireOffice() {
    if (!authorized) throw StateError('Synthetic office authority expired.');
    inner.requireOffice();
  }

  @override
  void setSetting(String key, Object? value) {
    inner.setSetting(key, value);
    if (revokeAfterSetting) authorized = false;
    if (failAfterSetting) {
      throw StateError('Synthetic setting failure before commit.');
    }
  }

  @override
  void event(String kind, Json value) {
    if (failEvent) throw StateError('Synthetic event failure before commit.');
    inner.event(kind, value);
  }

  @override
  void transaction(void Function() action) {
    final before = beforeTransaction;
    beforeTransaction = null;
    before?.call();
    if (revokeAtTransaction) authorized = false;
    inner.transaction(action);
    if (failAfterCommit) {
      failAfterCommit = false;
      throw StateError('Synthetic unknown postcommit outcome.');
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<EditorFixture> _fixture() async {
  final fixture = await EditorFixture.create();
  addTearDown(fixture.close);
  return fixture;
}

String _equipment(LabStore store) => store.equipment.first['id'] as String;
int _version(LabStore store) =>
    store.db.select('PRAGMA user_version').single.values.single as int;

Future<FrozenCorrectivePlanningCommand> _create(
  CorrectivePlanningStore planning,
  String equipment, {
  String id = _a,
  String title = 'Inspect the source of the leak',
  String description = 'Diagnose the cause before planning any repair.',
  List<String> faults = const [],
}) => planning.freezeCreate(
  equipmentId: equipment,
  title: title,
  description: description,
  faultIds: faults,
  commandId: id,
);

Future<ManualFaultRecord> _fault(
  LabStore store,
  String equipment,
  String id,
) async {
  final intake = ManualFaultIntakeStore(store);
  final frozen = await intake.freeze(
    equipmentId: equipment,
    description: 'Synthetic saved observation $id',
    severity: ManualFaultSeverity.normal,
    commandId: id,
  );
  return (await intake.record(frozen)).record;
}

String _stored(LabStore store) => canonical({
  'version': _version(store),
  'settings': [
    for (final row in store.db.select(
      'SELECT key,value FROM settings ORDER BY key',
    ))
      Map<String, dynamic>.from(row),
  ],
  'events': [
    for (final row in store.db.select(
      'SELECT id,kind,payload FROM events ORDER BY id',
    ))
      Map<String, dynamic>.from(row),
  ],
});

Future<String> _inspectionAndFaultState(LabStore store) async => canonical({
  'settings': [
    for (final row in store.db.select(
      'SELECT key,value FROM settings WHERE key<>? ORDER BY key',
      [correctivePlanningSetting],
    ))
      Map<String, dynamic>.from(row),
  ],
  'events': [
    for (final row in store.db.select(
      'SELECT id,kind,payload FROM events WHERE kind<>? ORDER BY id',
      [correctivePlanningRecordedEvent],
    ))
      Map<String, dynamic>.from(row),
  ],
  'documents': [
    for (final row in store.db.select(
      'SELECT id,bytes FROM documents ORDER BY id',
    ))
      Map<String, dynamic>.from(row),
  ],
  'submissions': [
    for (final row in store.db.select('SELECT * FROM submissions ORDER BY id'))
      Map<String, dynamic>.from(row),
  ],
  'receipts': [
    for (final row in store.db.select('SELECT * FROM receipts ORDER BY id'))
      Map<String, dynamic>.from(row),
  ],
  'phones': [
    for (final row in store.db.select('SELECT * FROM phones ORDER BY id'))
      Map<String, dynamic>.from(row),
  ],
  'invites': [
    for (final row in store.db.select('SELECT * FROM invites ORDER BY hash'))
      Map<String, dynamic>.from(row),
  ],
  'evidence': await store.evidence.manifest(),
});

Future<Json> _bundle(LabStore store) async => await store.publicBundle()
  ..remove('savedAt');

void main() {
  setUpAll(initializeEditorNative);

  test(
    'planning reads preserve schema two and do not create an empty ledger',
    () async {
      final fixture = await _fixture();
      final store = fixture.store;
      final planning = CorrectivePlanningStore(store);
      final before = _stored(store);
      expect(await planning.listDrafts(), isEmpty);
      expect(await planning.draftFor('missing'), isNull);
      expect(await planning.draftForFault(_f1), isNull);
      expect(await planning.pendingCommands(), isEmpty);
      expect(await planning.receiptFor(_a), isNull);
      expect(_version(store), 2);
      expect(store.setting(correctivePlanningSetting), isNull);
      expect(_stored(store), before);
    },
  );

  test(
    'create several fault links and edit only scope without changing inspection or fault data',
    () async {
      final fixture = await _fixture();
      final store = fixture.store;
      final equipment = _equipment(store);
      await _fault(store, equipment, _f1);
      await _fault(store, equipment, _f2);
      final source = await _inspectionAndFaultState(store);
      final bundle = canonical(await _bundle(store));
      final planning = CorrectivePlanningStore(store);
      final command = await _create(planning, equipment, faults: [_f2, _f1]);
      expect(_version(store), 3);
      expect(await planning.listDrafts(), isEmpty);
      expect((await planning.pendingCommands()).single.hash, command.hash);
      final created = await planning.apply(command);
      expect(created.draft.kind, 'corrective');
      expect(created.draft.state, 'draft');
      expect(created.draft.revision, 1);
      expect(created.draft.faults.map((row) => row.faultId), [_f1, _f2]);
      expect((await planning.draftForFault(_f1))!.id, created.draft.id);
      expect((await planning.draftForFault(_f2))!.id, created.draft.id);
      final edit = await planning.freezeEdit(
        draftId: created.draft.id,
        expectedRevision: created.draft.revision,
        expectedDraftHash: created.draft.hash,
        title: 'Inspect the retained hose connection',
        description: 'Check routing and record the intended replacement scope.',
        commandId: _b,
      );
      final edited = await planning.apply(edit);
      expect(edited.draft.revision, 2);
      expect(edited.draft.equipmentSnapshot, created.draft.equipmentSnapshot);
      expect(
        edited.draft.faults.map((row) => row.toJson()).toList(),
        created.draft.faults.map((row) => row.toJson()).toList(),
      );
      expect(await _inspectionAndFaultState(store), source);
      expect(canonical(await _bundle(store)), bundle);
      expect(store.jobs, hasLength(1));
      expect(
        store.db
            .select("SELECT name FROM sqlite_master WHERE type='table'")
            .map((row) => row['name'])
            .toSet(),
        {
          'settings',
          'documents',
          'submissions',
          'receipts',
          'invites',
          'phones',
          'events',
        },
      );
      expect(
        store.db.select('SELECT * FROM events WHERE kind=?', [
          correctivePlanningRecordedEvent,
        ]),
        hasLength(2),
      );
    },
  );

  test(
    'standalone draft gains an atomic fault batch and original retries precede newer revisions',
    () async {
      final fixture = await _fixture();
      final store = fixture.store;
      final equipment = _equipment(store);
      await _fault(store, equipment, _f1);
      await _fault(store, equipment, _f2);
      final planning = CorrectivePlanningStore(store);
      final create = await _create(planning, equipment);
      final initial = await planning.apply(create);
      expect(initial.draft.faults, isEmpty);
      final link = await planning.freezeLink(
        draftId: initial.draft.id,
        expectedRevision: initial.draft.revision,
        expectedDraftHash: initial.draft.hash,
        faultIds: [_f2, _f1],
        commandId: _b,
      );
      final linked = await planning.apply(link);
      expect(linked.draft.revision, 2);
      final edit = await planning.freezeEdit(
        draftId: linked.draft.id,
        expectedRevision: linked.draft.revision,
        expectedDraftHash: linked.draft.hash,
        title: 'Updated planning scope',
        description: 'Diagnosis remains an instruction.',
        commandId: _c,
      );
      final latest = await planning.apply(edit);
      final before = _stored(store);
      expect((await planning.apply(create)).toJson(), initial.toJson());
      expect((await planning.apply(link)).toJson(), linked.toJson());
      expect((await _create(planning, equipment)).hash, create.hash);
      expect(
        (await planning.freezeLink(
          draftId: initial.draft.id,
          expectedRevision: initial.draft.revision,
          expectedDraftHash: initial.draft.hash,
          faultIds: [_f1, _f2],
          commandId: _b,
        )).hash,
        link.hash,
      );
      expect(
        (await planning.draftFor(initial.draft.id))!.hash,
        latest.draft.hash,
      );
      expect(_stored(store), before);
    },
  );

  test(
    'another pending request survives replay of a completed operation',
    () async {
      final fixture = await _fixture();
      final planning = CorrectivePlanningStore(fixture.store);
      final equipment = _equipment(fixture.store);
      final create = await _create(planning, equipment);
      final receipt = await planning.apply(create);
      final pending = await _create(planning, equipment, id: _b);
      final before = _stored(fixture.store);
      expect((await planning.apply(create)).hash, receipt.hash);
      expect((await _create(planning, equipment)).hash, create.hash);
      expect((await planning.pendingCommands()).single.hash, pending.hash);
      await expectLater(
        _create(planning, equipment, id: _c),
        throwsA(isA<CorrectivePlanningFailure>()),
      );
      expect(_stored(fixture.store), before);
    },
  );

  test(
    'UUID reuse with different fields or action rejects without changes',
    () async {
      final fixture = await _fixture();
      final planning = CorrectivePlanningStore(fixture.store);
      final equipment = _equipment(fixture.store);
      final command = await _create(planning, equipment);
      final receipt = await planning.apply(command);
      final before = _stored(fixture.store);
      await expectLater(
        _create(planning, equipment, title: 'Different intent'),
        throwsA(isA<CorrectivePlanningFailure>()),
      );
      await expectLater(
        planning.freezeEdit(
          draftId: receipt.draft.id,
          expectedRevision: receipt.draft.revision,
          expectedDraftHash: receipt.draft.hash,
          title: receipt.draft.title,
          description: receipt.draft.description,
          commandId: _a,
        ),
        throwsA(isA<CorrectivePlanningFailure>()),
      );
      final changed = FrozenCorrectivePlanningCommand.createDraft(
        id: _a,
        companyId: command.companyId,
        deviceId: command.deviceId,
        equipmentSnapshot: command.equipmentSnapshot!,
        title: 'Different direct retry',
        description: command.description!,
        createdAt: command.createdAt,
      );
      await expectLater(
        planning.apply(changed),
        throwsA(isA<CorrectivePlanningFailure>()),
      );
      expect(_stored(fixture.store), before);
    },
  );

  test(
    'stale revision and stale hash reject edits and links before saving intent',
    () async {
      final fixture = await _fixture();
      final store = fixture.store;
      final equipment = _equipment(store);
      await _fault(store, equipment, _f1);
      final planning = CorrectivePlanningStore(store);
      final original = (await planning.apply(
        await _create(planning, equipment),
      )).draft;
      final edit = await planning.freezeEdit(
        draftId: original.id,
        expectedRevision: original.revision,
        expectedDraftHash: original.hash,
        title: 'Current scope',
        description: 'Current description',
        commandId: _b,
      );
      final current = (await planning.apply(edit)).draft;
      final before = _stored(store);
      for (final fence in [
        (original.revision, current.hash),
        (current.revision, original.hash),
      ]) {
        await expectLater(
          planning.freezeEdit(
            draftId: current.id,
            expectedRevision: fence.$1,
            expectedDraftHash: fence.$2,
            title: 'Stale scope',
            description: 'Must not persist',
            commandId: _c,
          ),
          throwsA(isA<CorrectivePlanningFailure>()),
        );
        await expectLater(
          planning.freezeLink(
            draftId: current.id,
            expectedRevision: fence.$1,
            expectedDraftHash: fence.$2,
            faultIds: [_f1],
            commandId: _c,
          ),
          throwsA(isA<CorrectivePlanningFailure>()),
        );
        expect(_stored(store), before);
      }
    },
  );

  test(
    'invalid unknown inspection duplicate and cross-equipment batches never partly link or upgrade',
    () async {
      final fixture = await _fixture();
      final store = fixture.store;
      final equipment = _equipment(store);
      final other = await store.addEquipment(name: 'Other synthetic equipment');
      await _fault(store, equipment, _f1);
      await _fault(store, other['id'] as String, _f2);
      final planning = CorrectivePlanningStore(store);
      final before = _stored(store);
      for (final batch in [
        [_f1, 'unknown-fault'],
        [_f1, fixture.job],
        [_f1, _f1],
        [_f1, _f2],
      ]) {
        await expectLater(
          _create(planning, equipment, faults: batch),
          throwsA(isA<CorrectivePlanningFailure>()),
        );
        expect(_stored(store), before);
        expect(_version(store), 2);
      }
      expect(await planning.listDrafts(), isEmpty);
      expect(await planning.pendingCommands(), isEmpty);
    },
  );

  test(
    'inspection targets and new redundant or reassignment commands leave state unchanged',
    () async {
      final fixture = await _fixture();
      final store = fixture.store;
      final equipment = _equipment(store);
      await _fault(store, equipment, _f1);
      final planning = CorrectivePlanningStore(store);
      final linked = (await planning.apply(
        await _create(planning, equipment, faults: [_f1]),
      )).draft;
      final standalone = (await planning.apply(
        await _create(planning, equipment, id: _b),
      )).draft;
      final before = _stored(store);
      for (final target in [linked, standalone]) {
        await expectLater(
          planning.freezeLink(
            draftId: target.id,
            expectedRevision: target.revision,
            expectedDraftHash: target.hash,
            faultIds: [_f1],
            commandId: _c,
          ),
          throwsA(isA<CorrectivePlanningFailure>()),
        );
        expect(_stored(store), before);
      }
      await expectLater(
        planning.freezeLink(
          draftId: fixture.job,
          expectedRevision: 1,
          expectedDraftHash: linked.hash,
          faultIds: [_f1],
          commandId: _c,
        ),
        throwsA(isA<CorrectivePlanningFailure>()),
      );
      expect(_stored(store), before);
    },
  );

  test(
    'failed first freeze rolls back both intent and schema marker',
    () async {
      final fixture = await _fixture();
      final adapter = _PlanningStore(fixture.store)..failAfterSetting = true;
      final planning = CorrectivePlanningStore(adapter);
      final before = _stored(fixture.store);
      await expectLater(
        _create(planning, _equipment(fixture.store)),
        throwsStateError,
      );
      expect(_version(fixture.store), 2);
      expect(fixture.store.setting(correctivePlanningSetting), isNull);
      expect(_stored(fixture.store), before);
      adapter.failAfterSetting = false;
      await _create(planning, _equipment(fixture.store));
      expect(_version(fixture.store), 3);
    },
  );

  test(
    'postwrite authority loss rolls back the already advanced schema marker',
    () async {
      final fixture = await _fixture();
      final adapter = _PlanningStore(fixture.store)..revokeAfterSetting = true;
      final planning = CorrectivePlanningStore(adapter);
      final before = _stored(fixture.store);
      await expectLater(
        _create(planning, _equipment(fixture.store)),
        throwsA(isA<CorrectivePlanningFailure>()),
      );
      expect(adapter.sawSchemaThreeAfterRevocation, isTrue);
      expect(_version(fixture.store), 2);
      expect(fixture.store.setting(correctivePlanningSetting), isNull);
      expect(_stored(fixture.store), before);
    },
  );

  test(
    'a valid command cannot be applied before its intent is frozen',
    () async {
      final fixture = await _fixture();
      final store = fixture.store;
      final planning = CorrectivePlanningStore(store);
      final candidate = FrozenCorrectivePlanningCommand.createDraft(
        id: _a,
        companyId: store.catalog!['companyId'] as String,
        deviceId: store.device,
        equipmentSnapshot: store.equipment.first,
        title: 'Unfrozen scope',
        description: 'Must not persist',
        createdAt: store.stamp(),
      );
      final before = _stored(store);
      await expectLater(
        planning.apply(candidate),
        throwsA(isA<CorrectivePlanningFailure>()),
      );
      expect(_stored(store), before);
      expect(_version(store), 2);
    },
  );

  test(
    'event failure rolls acceptance back and retains the exact pending command',
    () async {
      final fixture = await _fixture();
      final adapter = _PlanningStore(fixture.store);
      final planning = CorrectivePlanningStore(adapter);
      final command = await _create(planning, _equipment(fixture.store));
      final before = _stored(fixture.store);
      adapter.failEvent = true;
      await expectLater(planning.apply(command), throwsStateError);
      expect(_stored(fixture.store), before);
      expect((await planning.pendingCommands()).single.hash, command.hash);
      adapter.failEvent = false;
      await planning.apply(command);
      expect(await planning.pendingCommands(), isEmpty);
      expect(await planning.listDrafts(), hasLength(1));
    },
  );

  test(
    'lost freeze and apply replies recover original frozen intent and one receipt',
    () async {
      final fixture = await _fixture();
      final adapter = _PlanningStore(fixture.store)..failAfterCommit = true;
      final planning = CorrectivePlanningStore(adapter);
      final equipment = _equipment(fixture.store);
      await expectLater(_create(planning, equipment), throwsStateError);
      final durable = (await planning.pendingCommands()).single;
      expect(_version(fixture.store), 3);
      adapter.overrideStamp = '2024-10-01T12:00:00.000Z';
      expect((await _create(planning, equipment)).toJson(), durable.toJson());
      adapter.failAfterCommit = true;
      await expectLater(planning.apply(durable), throwsStateError);
      final receipt = (await planning.receiptFor(_a))!;
      final before = _stored(fixture.store);
      expect((await planning.apply(durable)).toJson(), receipt.toJson());
      expect(_stored(fixture.store), before);
      expect(
        fixture.store.db.select('SELECT * FROM events WHERE kind=?', [
          correctivePlanningRecordedEvent,
        ]),
        hasLength(1),
      );
    },
  );

  test(
    'ordinary reopen resumes pending intent and preserves completed receipt',
    () async {
      final fixture = await EditorFixture.create();
      LabStore current = fixture.store;
      addTearDown(() async {
        fixture.updates.dispose();
        await current.close();
        await fixture.root.delete(recursive: true);
      });
      final root = current.root;
      final equipment = _equipment(current);
      final command = await _create(
        CorrectivePlanningStore(current),
        equipment,
      );
      await current.close();
      current = await LabStore.open(root, office: true, maintenanceOnly: true);
      expect(_version(current), 3);
      final resumed = CorrectivePlanningStore(current);
      final pending = (await resumed.pendingCommands()).single;
      expect(pending.toJson(), command.toJson());
      final receipt = await resumed.apply(pending);
      await current.close();
      current = await LabStore.open(root, office: true, maintenanceOnly: true);
      final completed = CorrectivePlanningStore(current);
      expect((await completed.receiptFor(_a))!.toJson(), receipt.toJson());
      expect((await completed.apply(command)).toJson(), receipt.toJson());
    },
  );

  test(
    'queued and transaction-time authority loss cannot save planning data',
    () async {
      final fixture = await _fixture();
      final adapter = _PlanningStore(fixture.store);
      final planning = CorrectivePlanningStore(adapter);
      final gate = Completer<void>();
      final barrier = fixture.store.queue.run(() => gate.future);
      final before = _stored(fixture.store);
      final attempt = _create(planning, _equipment(fixture.store));
      final denied = expectLater(
        attempt,
        throwsA(isA<CorrectivePlanningFailure>()),
      );
      adapter.authorized = false;
      gate.complete();
      await barrier;
      await denied;
      expect(_stored(fixture.store), before);
      adapter.authorized = true;
      adapter.revokeAtTransaction = true;
      await expectLater(
        _create(planning, _equipment(fixture.store)),
        throwsA(isA<CorrectivePlanningFailure>()),
      );
      expect(_stored(fixture.store), before);
    },
  );

  test(
    'phone and absent company deny every planning read and mutation',
    () async {
      final fixture = await _fixture();
      final command = await _create(
        CorrectivePlanningStore(fixture.store),
        _equipment(fixture.store),
      );
      final root = await Directory.systemTemp.createTemp(
        'synthetic-planning-role-',
      );
      final phone = await LabStore.open(
        Directory('${root.path}/phone'),
        office: false,
        maintenanceOnly: true,
      );
      final office = await LabStore.open(
        Directory('${root.path}/office'),
        office: true,
        maintenanceOnly: true,
      );
      addTearDown(() async {
        await phone.close();
        await office.close();
        await root.delete(recursive: true);
      });
      for (final store in [phone, office]) {
        final planning = CorrectivePlanningStore(store);
        final before = _stored(store);
        for (final action in <Future<Object?> Function()>[
          planning.listDrafts,
          planning.pendingCommands,
          () => planning.draftFor(command.draftId),
          () => planning.draftForFault(_f1),
          () => planning.receiptFor(_a),
          () => _create(planning, command.equipmentId),
          () => planning.freezeEdit(
            draftId: command.draftId,
            expectedRevision: 1,
            expectedDraftHash: command.hash,
            title: 'Denied',
            description: 'Denied',
            commandId: _b,
          ),
          () => planning.freezeLink(
            draftId: command.draftId,
            expectedRevision: 1,
            expectedDraftHash: command.hash,
            faultIds: [_f1],
            commandId: _b,
          ),
          () => planning.apply(command),
        ]) {
          await expectLater(
            action(),
            throwsA(isA<CorrectivePlanningFailure>()),
          );
          expect(_stored(store), before);
        }
      }
    },
  );

  test(
    'live transaction state retains a separate writer receipt before freezing another request',
    () async {
      final fixture = await _fixture();
      final store = fixture.store;
      final equipment = _equipment(store);
      final other = FrozenCorrectivePlanningCommand.createDraft(
        id: _b,
        companyId: store.catalog!['companyId'] as String,
        deviceId: store.device,
        equipmentSnapshot: store.equipment.first,
        title: 'Other committed draft',
        description: 'Separate bounded writer scope',
        createdAt: store.stamp(),
      );
      final receipt = applyCorrectivePlanningCommand(
        state: CorrectivePlanningState.empty(),
        command: other,
        catalog: store.catalog!,
        deviceId: store.device,
        manualFaultHistory: ManualFaultIntakeState.empty(),
        recordedAt: store.stamp(),
      );
      final adapter = _PlanningStore(store)
        ..beforeTransaction = () {
          final writer = sqlite3.open('${store.root.path}/workspace.sqlite');
          try {
            writer.execute('BEGIN IMMEDIATE');
            writer.execute('INSERT INTO settings VALUES (?,?)', [
              correctivePlanningSetting,
              canonical({
                'version': 1,
                'pending': [],
                'receipts': [receipt.toJson()],
              }),
            ]);
            writer.execute('PRAGMA user_version=3');
            writer.execute('INSERT INTO events(kind,payload) VALUES (?,?)', [
              correctivePlanningRecordedEvent,
              canonical(receipt.toJson()),
            ]);
            writer.execute('COMMIT');
          } finally {
            writer.close();
          }
        };
      final planning = CorrectivePlanningStore(adapter);
      final command = await _create(planning, equipment);
      expect((await planning.receiptFor(_b))!.hash, receipt.hash);
      await planning.apply(command);
      expect(await planning.listDrafts(), hasLength(2));
      expect(
        store.db.select('SELECT * FROM events WHERE kind=?', [
          correctivePlanningRecordedEvent,
        ]),
        hasLength(2),
      );
    },
  );

  test(
    'batch input is captured before queueing and frozen fields are detached',
    () async {
      final fixture = await _fixture();
      final store = fixture.store;
      final equipment = _equipment(store);
      await _fault(store, equipment, _f1);
      final planning = CorrectivePlanningStore(store);
      final gate = Completer<void>();
      final barrier = store.queue.run(() => gate.future);
      final input = [_f1];
      final attempt = _create(planning, equipment, faults: input);
      input[0] = 'changed-after-queueing';
      gate.complete();
      await barrier;
      final command = await attempt;
      expect(command.faults.single.faultId, _f1);
      final changed = command.toJson();
      (changed['faults'] as List).clear();
      expect((await planning.pendingCommands()).single.hash, command.hash);
      expect(
        (await planning.pendingCommands()).single.faults.single.faultId,
        _f1,
      );
    },
  );

  test(
    'future or corrupt ledger is refused before any subsequent write',
    () async {
      final fixture = await _fixture();
      final store = fixture.store;
      final planning = CorrectivePlanningStore(store);
      await _create(planning, _equipment(store));
      final valid = store.setting(correctivePlanningSetting) as Json;
      for (final damaged in [
        {...valid, 'version': 2},
        {...valid, 'receipts': 'unsupported'},
      ]) {
        store.setSetting(correctivePlanningSetting, damaged);
        final before = _stored(store);
        await expectLater(
          planning.listDrafts(),
          throwsA(isA<CorrectivePlanningFailure>()),
        );
        await expectLater(
          _create(planning, _equipment(store), id: _d),
          throwsA(isA<CorrectivePlanningFailure>()),
        );
        expect(_stored(store), before);
      }
      store.setSetting(correctivePlanningSetting, valid);
      expect((await planning.pendingCommands()).single.id, _a);
    },
  );
}
