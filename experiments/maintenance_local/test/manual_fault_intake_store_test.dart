import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/manual_fault_intake.dart';
import 'package:maintenance_local/manual_fault_intake_store.dart';
import 'package:maintenance_local/model.dart';
import 'package:sqlite3/sqlite3.dart';

import 'inspection_editor_coherence_support.dart';

const _id = '33333333-3333-4333-8333-333333333333';
const _otherId = '44444444-4444-4444-8444-444444444444';

/// Synthetic adapter retains the real queue, database, transaction and role
/// checks while injecting rollback and unknown postcommit outcomes.
class _FaultStore implements LabStore {
  _FaultStore(this.inner);
  final LabStore inner;
  bool authorized = true;
  bool failEvent = false;
  bool failAfterCommit = false;
  bool revokeAtTransaction = false;
  String? overrideStamp;
  @override
  bool get office => authorized && inner.office;
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
  dynamic setting(String key) => inner.setting(key);
  @override
  void setSetting(String key, Object? value) => inner.setSetting(key, value);
  @override
  void requireOffice() {
    if (!authorized) throw StateError('Synthetic office authority expired.');
    inner.requireOffice();
  }

  @override
  void transaction(void Function() action) {
    if (revokeAtTransaction) authorized = false;
    inner.transaction(action);
    if (failAfterCommit) {
      failAfterCommit = false;
      throw StateError('Synthetic unknown postcommit outcome.');
    }
  }

  @override
  void event(String kind, Json data) {
    if (failEvent) throw StateError('Synthetic event failure before commit.');
    inner.event(kind, data);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<FrozenManualFaultCommand> _freeze(
  ManualFaultIntakeStore intake,
  String equipment, {
  String id = _id,
  String description = 'Synthetic manual leak observation.',
  ManualFaultOrigin? origin,
}) => intake.freeze(
  equipmentId: equipment,
  description: description,
  severity: ManualFaultSeverity.normal,
  originSelection: origin,
  commandId: id,
);

String _storedState(LabStore store) => canonical({
  'settings': [
    for (final row in store.db.select(
      'SELECT key,value FROM settings ORDER BY key',
    ))
      {'key': row['key'], 'value': row['value']},
  ],
  'events': [
    for (final row in store.db.select(
      'SELECT id,kind,payload FROM events ORDER BY id',
    ))
      {'id': row['id'], 'kind': row['kind'], 'payload': row['payload']},
  ],
});

Future<String> _sourceState(LabStore store) async => canonical({
  'catalog': store.catalog,
  'activeJobId': store.setting('activeJobId'),
  'documents': [
    for (final row in store.db.select(
      'SELECT id,bytes FROM documents ORDER BY id',
    ))
      {'id': row['id'], 'bytes': row['bytes']},
  ],
  'submissions': [
    for (final row in store.db.select(
      'SELECT id,hash,payload,state FROM submissions ORDER BY id',
    ))
      Map<String, dynamic>.from(row),
  ],
  'receipts': [
    for (final row in store.db.select(
      'SELECT id,submission_id,hash,payload FROM receipts ORDER BY id',
    ))
      Map<String, dynamic>.from(row),
  ],
  'evidence': await store.evidence.manifest(),
});

void main() {
  setUpAll(initializeEditorNative);

  test(
    'native saved source with faster timestamp and office clock rollback remain usable',
    () async {
      final fixture = await EditorFixture.create();
      addTearDown(fixture.close);
      final submission = await fixture.store.submit(jobId: fixture.job);
      await fixture.store.decide(submission['id'] as String, approve: true);
      final adapter = _FaultStore(fixture.store)
        ..overrideStamp = '2025-10-01T12:00:00.000Z';
      final intake = ManualFaultIntakeStore(adapter);
      final equipment = fixture.store.equipment.single['id'] as String;
      final origin = (await intake.availableOrigins(equipment)).first;
      final command = await _freeze(intake, equipment, origin: origin);
      expect(
        DateTime.parse(
          submission['createdAt'] as String,
        ).isAfter(DateTime.parse(command.createdAt)),
        isTrue,
      );
      adapter.overrideStamp = '2024-10-01T12:00:00.000Z';
      final receipt = await intake.record(command);
      expect(receipt.record.reportedAt, adapter.overrideStamp);
      expect(receipt.record.origin!.receiptHash, origin.receiptHash);
      expect((await intake.record(command)).hash, receipt.hash);
    },
  );

  test(
    'exact UUID replay has one record/event and changed retry fields conflict',
    () async {
      final fixture = await EditorFixture.create();
      addTearDown(fixture.close);
      final intake = ManualFaultIntakeStore(fixture.store);
      final equipment = fixture.store.equipment.single['id'] as String;
      final command = await _freeze(intake, equipment);
      expect(await intake.pendingCommands(), hasLength(1));
      expect((await _freeze(intake, equipment)).hash, command.hash);
      await expectLater(
        _freeze(intake, equipment, description: 'Different frozen description'),
        throwsA(isA<ManualFaultIntakeFailure>()),
      );
      await expectLater(
        _freeze(intake, equipment, id: _otherId),
        throwsA(
          isA<ManualFaultIntakeFailure>().having(
            (e) => e.code,
            'code',
            'pending_command',
          ),
        ),
      );
      final first = await intake.record(command);
      final before = _storedState(fixture.store);
      expect((await intake.record(command)).toJson(), first.toJson());
      expect((await _freeze(intake, equipment)).hash, command.hash);
      expect((await intake.receiptFor(_id))!.hash, first.hash);
      expect(_storedState(fixture.store), before);
      expect(await intake.listRecords(), hasLength(1));
      expect(await intake.pendingCommands(), isEmpty);
      expect(
        fixture.store.db.select('SELECT * FROM events WHERE kind=?', [
          manualFaultReportedEvent,
        ]),
        hasLength(1),
      );
      // Similar human reports use new UUIDs; no automatic content deduplication.
      await intake.record(await _freeze(intake, equipment, id: _otherId));
      expect(await intake.listRecords(), hasLength(2));
    },
  );

  test(
    'atomic acceptance rolls back setting and event, retains frozen request for exact retry',
    () async {
      final fixture = await EditorFixture.create();
      addTearDown(fixture.close);
      final adapter = _FaultStore(fixture.store);
      final intake = ManualFaultIntakeStore(adapter);
      final command = await _freeze(
        intake,
        fixture.store.equipment.single['id'] as String,
      );
      final before = _storedState(fixture.store);
      adapter.failEvent = true;
      await expectLater(intake.record(command), throwsStateError);
      expect(_storedState(fixture.store), before);
      adapter.failEvent = false;
      expect((await intake.pendingCommands()).single.hash, command.hash);
      await intake.record(command);
      expect(await intake.listRecords(), hasLength(1));
    },
  );

  test(
    'unknown postcommit freeze and acceptance recover their original exact intent',
    () async {
      final fixture = await EditorFixture.create();
      addTearDown(fixture.close);
      final adapter = _FaultStore(fixture.store);
      final intake = ManualFaultIntakeStore(adapter);
      final equipment = fixture.store.equipment.single['id'] as String;
      adapter.failAfterCommit = true;
      await expectLater(_freeze(intake, equipment), throwsStateError);
      final durable = (await intake.pendingCommands()).single;
      expect((await _freeze(intake, equipment)).hash, durable.hash);
      adapter.failAfterCommit = true;
      await expectLater(intake.record(durable), throwsStateError);
      final receipt = (await intake.receiptFor(_id))!;
      final before = _storedState(fixture.store);
      expect(await intake.pendingCommands(), isEmpty);
      expect((await intake.record(durable)).hash, receipt.hash);
      expect(_storedState(fixture.store), before);
    },
  );

  test(
    'reopen resumes durable frozen fields and completed receipt after process loss',
    () async {
      final fixture = await EditorFixture.create();
      LabStore current = fixture.store;
      addTearDown(() async {
        fixture.updates.dispose();
        await current.close();
        await fixture.root.delete(recursive: true);
      });
      final equipment = current.equipment.single['id'] as String;
      final first = ManualFaultIntakeStore(current);
      final frozen = await _freeze(first, equipment);
      final root = current.root;
      await current.close();
      current = await LabStore.open(root, office: true, maintenanceOnly: true);
      final resumed = ManualFaultIntakeStore(current);
      final pending = (await resumed.pendingCommands()).single;
      expect(pending.toJson(), frozen.toJson());
      final receipt = await resumed.record(pending);
      await current.close();
      current = await LabStore.open(root, office: true, maintenanceOnly: true);
      final completed = ManualFaultIntakeStore(current);
      expect((await completed.receiptFor(_id))!.toJson(), receipt.toJson());
      expect((await completed.record(frozen)).hash, receipt.hash);
    },
  );

  test(
    'every queued command and atomic write rechecks office company authority',
    () async {
      final fixture = await EditorFixture.create();
      addTearDown(fixture.close);
      final adapter = _FaultStore(fixture.store);
      final intake = ManualFaultIntakeStore(adapter);
      final equipment = fixture.store.equipment.single['id'] as String;
      final gate = Completer<void>();
      final barrier = fixture.store.queue.run(() => gate.future);
      final before = _storedState(fixture.store);
      final attempt = _freeze(intake, equipment);
      final rejection = expectLater(
        attempt,
        throwsA(isA<ManualFaultIntakeFailure>()),
      );
      adapter.authorized = false;
      gate.complete();
      await barrier;
      await rejection;
      expect(_storedState(fixture.store), before);
      adapter.authorized = true;
      final frozen = await _freeze(intake, equipment);
      final pendingState = _storedState(fixture.store);
      adapter.revokeAtTransaction = true;
      await expectLater(
        intake.record(frozen),
        throwsA(isA<ManualFaultIntakeFailure>()),
      );
      expect(_storedState(fixture.store), pendingState);
      adapter.revokeAtTransaction = false;
      adapter.authorized = true;
      await intake.record(frozen);
    },
  );

  test(
    'pending approved returned provenance uses saved versions and leaves all source/private bundle bytes unchanged',
    () async {
      for (final decision in ['pending', 'approved', 'returned']) {
        final fixture = await EditorFixture.create();
        try {
          final submission = await fixture.store.submit(jobId: fixture.job);
          if (decision != 'pending') {
            await fixture.store.decide(
              submission['id'] as String,
              approve: decision == 'approved',
              reason: decision == 'returned' ? 'Synthetic return reason.' : '',
            );
          }
          final intake = ManualFaultIntakeStore(fixture.store);
          final before = await _sourceState(fixture.store);
          final bundleBefore = await fixture.store.publicBundle()
            ..remove('savedAt');
          final equipment = fixture.store.equipment.single['id'] as String;
          final origins = await intake.availableOrigins(equipment);
          expect(origins, hasLength(5));
          final selection = origins.last;
          expect(selection.kind, ManualFaultOriginKind.note);
          expect(selection.observation.name, decision);
          final command = await _freeze(intake, equipment, origin: selection);
          final receipt = await intake.record(command);
          expect(receipt.record.origin!.toJson(), selection.toJson());
          expect(await _sourceState(fixture.store), before);
          final bundleAfter = await fixture.store.publicBundle()
            ..remove('savedAt');
          expect(canonical(bundleAfter), canonical(bundleBefore));
          expect(
            fixture.store.db.select('PRAGMA user_version').single.values.single,
            2,
          );
          expect(
            fixture.store.db
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
        } finally {
          await fixture.close();
        }
      }
    },
  );

  test(
    'pending capture remains historical after approval and stale pre-freeze selection requires refresh',
    () async {
      final fixture = await EditorFixture.create();
      addTearDown(fixture.close);
      final source = await fixture.store.submit(jobId: fixture.job);
      final intake = ManualFaultIntakeStore(fixture.store);
      final equipment = fixture.store.equipment.single['id'] as String;
      final pendingOrigin = (await intake.availableOrigins(equipment)).first;
      final command = await _freeze(intake, equipment, origin: pendingOrigin);
      await fixture.store.decide(source['id'] as String, approve: true);
      expect(
        (await intake.pendingCommands()).single.origin!.observation,
        ManualFaultObservation.pending,
      );
      final receipt = await intake.record(command);
      expect(
        receipt.record.origin!.observation,
        ManualFaultObservation.pending,
      );
      await expectLater(
        _freeze(intake, equipment, id: _otherId, origin: pendingOrigin),
        throwsA(
          isA<ManualFaultIntakeFailure>().having(
            (e) => e.code,
            'code',
            'invalid_origin',
          ),
        ),
      );
      expect(await intake.pendingCommands(), isEmpty);
    },
  );

  test(
    'phone and absent company deny all intake reads and writes without database changes',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'synthetic-fault-role-',
      );
      final phone = await LabStore.open(
        Directory('${root.path}/phone'),
        office: false,
        maintenanceOnly: true,
      );
      final blankOffice = await LabStore.open(
        Directory('${root.path}/office'),
        office: true,
        maintenanceOnly: true,
      );
      addTearDown(() async {
        await phone.close();
        await blankOffice.close();
        await root.delete(recursive: true);
      });
      for (final store in [phone, blankOffice]) {
        final intake = ManualFaultIntakeStore(store);
        final before = _storedState(store);
        final fake = FrozenManualFaultCommand.create(
          id: _id,
          companyId: 'synthetic-company',
          deviceId: store.device,
          equipmentId: 'synthetic-equipment',
          description: 'Synthetic report',
          severity: ManualFaultSeverity.normal,
          createdAt: store.stamp(),
        );
        for (final command in <Future<Object?> Function()>[
          intake.listRecords,
          intake.pendingCommands,
          () => intake.availableOrigins('synthetic-equipment'),
          () => intake.receiptFor(_id),
          () => _freeze(intake, 'synthetic-equipment'),
          () => intake.record(fake),
        ]) {
          await expectLater(
            command(),
            throwsA(isA<ManualFaultIntakeFailure>()),
          );
        }
        expect(_storedState(store), before);
      }
    },
  );
}
