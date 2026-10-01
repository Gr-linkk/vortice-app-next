import 'dart:convert';
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/job_progress.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/local_sync.dart';
import 'package:maintenance_local/model.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';
import 'package:maintenance_local/work_progress_reader.dart';

Json _copy(Json value) => jsonDecode(canonical(value)) as Json;

Set<String> _ids(Iterable<SubmittedVersion> versions) =>
    versions.map((v) => v.id).toSet();

Json _rawState(LabStore store) => {
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

Future<Json> _evidenceFiles(LabStore store) async {
  final root = store.evidence.root;
  if (!await root.exists()) return {'exists': false};
  return {
    'exists': true,
    await for (final entry in root.list(recursive: true, followLinks: false))
      entry.path.substring(root.path.length + 1): entry is File
          ? digest(await entry.readAsBytes())
          : 'directory',
  };
}

Future<WorkProgressSnapshot> _read(LabStore store) async {
  final state = _rawState(store);
  final files = await _evidenceFiles(store);
  final snapshot = await readWorkProgress(store);
  expect(await workProgressToken(store), snapshot.token);
  expect(
    _rawState(store),
    state,
    reason: 'Progress is a read-only projection of every raw table.',
  );
  expect(
    await _evidenceFiles(store),
    files,
    reason: 'Progress must never recover or publish a partial photo.',
  );
  return snapshot;
}

class _Clocks {
  DateTime office = DateTime.utc(2026, 9, 30, 12);
  DateTime phone = DateTime.utc(2040, 1, 1);
}

class _ProgressFixture {
  _ProgressFixture(
    this.root,
    this.office,
    this.phone,
    this.server,
    this.sync,
    this.a,
    this.b,
    this.clocks,
  );
  final Directory root;
  final LabStore office;
  LabStore phone;
  final OfficeServer server;
  PhoneSync sync;
  final String a, b;
  final _Clocks clocks;
  final photo = [1, 2, 3, 4, 5, 6, 7, 8];

  static Future<_ProgressFixture> create() async {
    final clocks = _Clocks();
    final root = await Directory.systemTemp.createTemp(
      'maintenance-progress-probe-',
    );
    final office = await LabStore.open(
      Directory('${root.path}/office'),
      office: true,
      maintenanceOnly: true,
      now: () => clocks.office,
    );
    await office.createCompany(
      'Synthetic progress probe company',
      coordinatorName: 'Synthetic progress coordinator',
    );
    final equipmentA = await office.addEquipment(
      name: 'Synthetic hours pump',
      serial: 'PROGRESS-A',
    );
    final procedureA = await office.publishChecklist(
      title: 'Synthetic guard and pressure inspection',
      items: [
        {'id': 'guard', 'label': 'Guard secure', 'input_type': 'check'},
        {
          'id': 'pressure',
          'label': 'Record pressure',
          'input_type': 'number',
          'unit': 'bar',
          'min': 1,
          'max': 2,
          'allow_na': true,
        },
        {
          'id': 'optional',
          'label': 'Optional observation',
          'input_type': 'text',
          'required': false,
        },
      ],
      provenance: {'kind': 'company-authored'},
    );
    final a = await office.prepareWork(
      equipmentId: equipmentA['id'] as String,
      templateId: procedureA['id'] as String,
      title: 'Synthetic job A',
    );
    final equipmentB = await office.addEquipment(
      name: 'Synthetic no-meter valve',
      serial: 'PROGRESS-B',
      meterUnit: 'none',
    );
    final procedureB = await office.publishChecklist(
      title: 'Synthetic no-meter seal inspection',
      items: [
        {'id': 'seal', 'label': 'Seal inspected', 'input_type': 'check'},
      ],
      provenance: {'kind': 'company-authored'},
    );
    final b = await office.prepareWork(
      equipmentId: equipmentB['id'] as String,
      templateId: procedureB['id'] as String,
      title: 'Synthetic job B',
    );
    final server = await OfficeServer.start(
      office,
      port: 0,
      address: InternetAddress.loopbackIPv4,
    );
    final phone = await LabStore.open(
      Directory('${root.path}/phone'),
      office: false,
      maintenanceOnly: true,
      now: () => clocks.phone,
    );
    final sync = PhoneSync(phone);
    await sync.enroll(server.invitation('127.0.0.1'));
    server.authority.confirm(phone.device);
    await sync.sync();
    return _ProgressFixture(
      root,
      office,
      phone,
      server,
      sync,
      a['id'] as String,
      b['id'] as String,
      clocks,
    );
  }

  Future<void> fillA({LabStore? target}) async {
    final store = target ?? phone;
    await store.update({
      'answer:guard': {'result': 'pass', 'value': ''},
      'answer:pressure': {'result': 'pass', 'value': '1.5'},
      'meter': 0,
      'notes': 'Synthetic complete guard and pressure observation.',
    }, jobId: a);
    await store.attach(photo, jobId: a);
  }

  Future<void> fillB() async {
    await phone.update({
      'answer:seal': {'result': 'pass', 'value': ''},
      'notes': 'Synthetic complete no-meter observation.',
    }, jobId: b);
    await phone.attach(photo, jobId: b);
  }

  Future<Json> submittedA() async {
    await fillA();
    final command = await phone.submit(jobId: a);
    await sync.sync();
    return command;
  }

  Future<void> reopenPhone() async {
    final directory = phone.root;
    await phone.close();
    phone = await LabStore.open(
      directory,
      office: false,
      maintenanceOnly: true,
      now: () => clocks.phone,
    );
    sync = PhoneSync(phone);
  }

  Future<void> close() async {
    await server.close();
    await phone.close();
    await office.close();
    await root.delete(recursive: true);
  }
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
  late _ProgressFixture f;
  setUp(() async => f = await _ProgressFixture.create());
  tearDown(() async => f.close());

  test(
    'Actual untouched, partial, NA/action and no-meter work have truthful draft progress',
    () async {
      final prepared = await _read(f.phone);
      expect(prepared.jobs.keys.toSet(), {f.a, f.b});
      expect(prepared.jobs[f.a]!.draftPhase, DraftPhase.prepared);
      expect(prepared.jobs[f.a]!.requiredAnswered, 0);
      expect(prepared.jobs[f.a]!.requiredTotal, 2);
      expect(prepared.jobs[f.a]!.photoState, PhotoState.none);
      expect(prepared.jobs[f.b]!.requiredTotal, 1);
      await f.phone.update({
        'answer:guard': {'result': 'action', 'value': ''},
        'notes': 'Synthetic guard finding: a correction is needed.',
        'meter': 0,
      }, jobId: f.a);
      final partial = (await _read(f.phone)).jobs[f.a]!;
      expect(partial.draftPhase, DraftPhase.incomplete);
      expect(partial.requiredAnswered, 1);
      expect(partial.problem, isNotNull);
      await f.phone.update({
        'answer:pressure': {'result': 'na', 'value': ''},
      }, jobId: f.a);
      await f.phone.attach(f.photo, jobId: f.a);
      final ready = (await _read(f.phone)).jobs[f.a]!;
      expect(ready.draftPhase, DraftPhase.ready);
      expect(ready.requiredAnswered, 2);
      expect(ready.requiredTotal, 2);
      expect(ready.problem, isNull);
      expect(ready.currentVersions, isEmpty);
      expect(f.phone.submissions, isEmpty);
      await f.fillB();
      final noMeter = (await _read(f.phone)).jobs[f.b]!;
      expect(noMeter.draftPhase, DraftPhase.ready);
      expect(noMeter.requiredAnswered, 1);
      expect(noMeter.problem, isNull);
      expect(valuesOf(await f.phone.fields(jobId: f.b))['meter'], isNull);
    },
  );

  for (final edit in ['notes', 'photo', 'edit and revert']) {
    test(
      'Approval stays historical after an offline $edit, even with unchanged visible values',
      () async {
        final command = await f.submittedA();
        final receipt = await f.office.decide(
          command['id'] as String,
          approve: true,
        );
        await f.sync.sync();
        final approved = (await _read(f.phone)).jobs[f.a]!;
        expect(_ids(approved.currentVersions), {command['id']});
        expect(approved.currentVersions.single.decision, 'approved');
        expect(approved.documentHash, command['documentHash']);
        if (edit == 'photo') {
          await f.phone.attach([9, 8, 7, 6, 5], jobId: f.a);
        } else {
          await f.phone.update({
            'notes': 'Synthetic offline amended observation.',
          }, jobId: f.a);
          if (edit == 'edit and revert') {
            await f.phone.update({
              'notes': (command['values'] as Json)['notes'],
            }, jobId: f.a);
            expect(
              valuesOf(await f.phone.fields(jobId: f.a)),
              command['values'],
            );
          }
        }
        final draft = (await _read(f.phone)).jobs[f.a]!;
        expect(draft.documentHash, isNot(command['documentHash']));
        expect(draft.draftPhase, DraftPhase.ready);
        expect(draft.currentVersions, isEmpty);
        expect(_ids(draft.approvedVersions), {command['id']});
        expect(draft.history.single.receipt, receipt);
        expect(f.phone.receipts, [receipt]);
        expect(
          f.office.documentFor(f.a),
          base64Decode(command['document'] as String),
        );
        expect(f.phone.submissions, hasLength(1));
      },
    );
  }

  test(
    'Returned correction becomes a draft and a genuine queued successor without inherited decision',
    () async {
      final command = await f.submittedA();
      final receipt = await f.office.decide(
        command['id'] as String,
        approve: false,
        reason: 'Synthetic correction to the guard notes.',
      );
      await f.sync.sync();
      final returned = (await _read(f.phone)).jobs[f.a]!;
      expect(returned.currentVersions.single.decision, 'returned');
      expect(
        returned.currentVersions.single.receipt!['reason'],
        receipt['reason'],
      );
      await f.phone.update({
        'notes': 'Synthetic corrected guard observation.',
      }, jobId: f.a);
      final draft = (await _read(f.phone)).jobs[f.a]!;
      expect(draft.currentVersions, isEmpty);
      expect(draft.history.single.receipt, receipt);
      final successor = await f.phone.submit(jobId: f.a);
      expect(successor['predecessorId'], command['id']);
      expect(successor['submissionRevision'], 2);
      final queued = (await _read(f.phone)).jobs[f.a]!;
      expect(_ids(queued.currentVersions), {successor['id']});
      expect(queued.currentVersions.single.decision, isNull);
      expect(_ids(queued.queuedVersions), {successor['id']});
      expect(
        queued.history.singleWhere((v) => v.id == command['id']).receipt,
        receipt,
      );
      await f.sync.sync();
      final pending = await _read(f.office);
      expect(_ids(pending.undecided), {successor['id']});
      expect(_ids(pending.reviewed), {command['id']});
    },
  );

  test(
    'Reopened phone preserves queued older version separately from newer unsubmitted draft',
    () async {
      await f.fillA();
      final queued = await f.phone.submit(jobId: f.a);
      final before = (await _read(f.phone)).jobs[f.a]!;
      expect(_ids(before.currentVersions), {queued['id']});
      expect(_ids(before.queuedVersions), {queued['id']});
      final device = f.phone.device;
      final syncStamp = f.phone.setting('lastCompleteSync');
      await f.phone.update({
        'notes': 'Synthetic newer unsent draft.',
      }, jobId: f.a);
      final bytes = f.phone.documentFor(f.a)!;
      await f.reopenPhone();
      expect(f.phone.device, device);
      expect(f.phone.setting('lastCompleteSync'), syncStamp);
      expect(f.phone.documentFor(f.a), bytes);
      final reopened = (await _read(f.phone)).jobs[f.a]!;
      expect(reopened.documentHash, digest(bytes));
      expect(reopened.draftPhase, DraftPhase.ready);
      expect(reopened.currentVersions, isEmpty);
      expect(_ids(reopened.queuedVersions), {queued['id']});
      expect(reopened.queuedVersions.single.localState, 'queued');
      expect(reopened.queuedVersions.single.decision, isNull);
      expect(f.phone.submissions, hasLength(1));
    },
  );

  test(
    'Partial, complete-but-unpublished and corrupt photos never count complete or mutate during reads',
    () async {
      await f.fillA();
      final hash = digest(f.photo);
      final finalFile = f.phone.evidence.file(hash);
      final partial = File('${finalFile.path}.part');
      expect((await _read(f.phone)).jobs[f.a]!.photoState, PhotoState.complete);
      await finalFile.delete();
      await partial.writeAsBytes(f.photo.take(3).toList(), flush: true);
      final partialRead = (await _read(f.phone)).jobs[f.a]!;
      expect(partialRead.photoState, PhotoState.missingOrPartial);
      expect(partialRead.draftPhase, DraftPhase.incomplete);
      expect(partialRead.problem, isNotNull);
      await partial.writeAsBytes(f.photo, flush: true);
      final unpublished = (await _read(f.phone)).jobs[f.a]!;
      expect(unpublished.photoState, PhotoState.missingOrPartial);
      expect(unpublished.draftPhase, DraftPhase.incomplete);
      expect(await finalFile.exists(), isFalse);
      expect(await partial.readAsBytes(), f.photo);
      await partial.delete();
      await finalFile.writeAsBytes(
        List.filled(f.photo.length, 99),
        flush: true,
      );
      final corrupt = (await _read(f.phone)).jobs[f.a]!;
      expect(corrupt.photoState, PhotoState.missingOrPartial);
      expect(corrupt.problem, isNotNull);
      expect(corrupt.draftPhase, DraftPhase.incomplete);
      await finalFile.writeAsBytes(f.photo, flush: true);
      final recovered = (await _read(f.phone)).jobs[f.a]!;
      expect(recovered.photoState, PhotoState.complete);
      expect(recovered.draftPhase, DraftPhase.ready);
    },
  );

  test(
    'An office received command with missing photo remains undecided and cannot be approved',
    () async {
      await f.fillA();
      await f.sync.sync();
      final command = await f.phone.submit(jobId: f.a);
      final file = f.office.evidence.file(digest(f.photo));
      await file.delete();
      final connection = PinnedConnection(f.sync.pairing!);
      try {
        await connection.request('/submit', command);
      } finally {
        connection.close();
      }
      final snapshot = await _read(f.office);
      expect(_ids(snapshot.undecided), {command['id']});
      expect(snapshot.undecided.single.localState, 'received');
      expect(snapshot.undecided.single.photoState, PhotoState.missingOrPartial);
      expect(snapshot.jobs[f.a]!.photoState, PhotoState.missingOrPartial);
      final before = _rawState(f.office);
      await expectLater(
        f.office.decide(command['id'] as String, approve: true),
        throwsStateError,
      );
      expect(_rawState(f.office), before);
      expect(f.office.receipts, isEmpty);
      await file.writeAsBytes(f.photo, flush: true);
      final ready = await _read(f.office);
      expect(ready.undecided.single.photoState, PhotoState.complete);
      expect(await f.office.approvalProblem(command), isNull);
    },
  );

  test(
    'Selection is excluded from freshness while a nonselected edit changes only its job projection',
    () async {
      final command = await f.submittedA();
      await f.office.decide(command['id'] as String, approve: true);
      await f.sync.sync();
      f.phone.selectJob(f.a);
      final snapshot = await _read(f.phone);
      final token = snapshot.token;
      f.phone.selectJob(f.b);
      expect(await workProgressToken(f.phone), token);
      final selected = await _read(f.phone);
      expect(selected.token, token);
      expect(
        selected.jobs[f.a]!.documentHash,
        snapshot.jobs[f.a]!.documentHash,
      );
      expect(selected.jobs[f.a]!.currentVersions.single.decision, 'approved');
      await f.phone.update({
        'notes': 'Synthetic job B unsent draft.',
      }, jobId: f.b);
      final edited = await _read(f.phone);
      expect(edited.token, isNot(token));
      expect(edited.jobs[f.a]!.documentHash, snapshot.jobs[f.a]!.documentHash);
      expect(edited.jobs[f.a]!.currentVersions.single.decision, 'approved');
      expect(edited.jobs[f.b]!.draftPhase, DraftPhase.incomplete);
      expect(
        edited.jobs[f.b]!.documentHash,
        isNot(snapshot.jobs[f.b]!.documentHash),
      );
      expect(f.phone.activeJobId, f.b);
    },
  );

  test(
    'Captured reader result is rejected by its token after a queued edit completes before consumption',
    () async {
      await f.fillA();
      final originalHash = digest(f.phone.documentFor(f.a)!);
      // Capture is queued first; the real edit is queued second. No timing delay
      // or native/evidence override is needed to model a late UI consumption.
      final reading = readWorkProgress(f.phone);
      final editing = f.phone.update({
        'notes': 'Synthetic late queued edit.',
      }, jobId: f.a);
      await editing;
      final captured = await reading;
      expect(captured.jobs[f.a]!.documentHash, originalHash);
      expect(captured.token, isNot(await workProgressToken(f.phone)));
      final fresh = await _read(f.phone);
      expect(fresh.jobs[f.a]!.documentHash, digest(f.phone.documentFor(f.a)!));
      expect(fresh.token, await workProgressToken(f.phone));
    },
  );

  test(
    'Receipt and same-length evidence corruption both invalidate captured progress tokens',
    () async {
      final command = await f.submittedA();
      final pending = await _read(f.office);
      final receipt = await f.office.decide(
        command['id'] as String,
        approve: true,
      );
      expect(await workProgressToken(f.office), isNot(pending.token));
      final approved = await _read(f.office);
      expect(approved.jobs[f.a]!.currentVersions.single.receipt, receipt);
      final file = f.office.evidence.file(digest(f.photo));
      await file.writeAsBytes(List.filled(f.photo.length, 42), flush: true);
      expect(await workProgressToken(f.office), isNot(approved.token));
      final corrupt = await _read(f.office);
      expect(corrupt.jobs[f.a]!.photoState, PhotoState.missingOrPartial);
      expect(corrupt.jobs[f.a]!.currentVersions.single.receipt, receipt);
      expect(corrupt.token, await workProgressToken(f.office));
      await file.writeAsBytes(f.photo, flush: true);
      expect(await workProgressToken(f.office), approved.token);
    },
  );

  test(
    'Missing and corrupt raw documents are unavailable without hiding another job or changing storage',
    () async {
      final bytes = f.phone.documentFor(f.a)!;
      f.phone.db.execute('DELETE FROM documents WHERE id=?', [f.a]);
      final missing = await _read(f.phone);
      expect(missing.jobs[f.a]!.draftPhase, DraftPhase.unavailable);
      expect(missing.jobs[f.a]!.documentHash, isNull);
      expect(missing.jobs[f.a]!.currentVersions, isEmpty);
      expect(missing.jobs[f.b]!.draftPhase, DraftPhase.prepared);
      f.phone.db.execute('INSERT INTO documents VALUES (?,?)', [
        f.a,
        [0, 1, 2, 3],
      ]);
      final corrupt = await _read(f.phone);
      expect(corrupt.jobs[f.a]!.draftPhase, DraftPhase.unavailable);
      expect(corrupt.jobs[f.a]!.problem, isNotNull);
      expect(corrupt.jobs[f.b]!.draftPhase, DraftPhase.prepared);
      f.phone.db.execute('UPDATE documents SET bytes=? WHERE id=?', [
        bytes,
        f.a,
      ]);
      expect((await _read(f.phone)).jobs[f.a]!.draftPhase, DraftPhase.prepared);
    },
  );

  test(
    'Actual concurrent office and mechanic edits remain conflicted with explicit progress',
    () async {
      await f.fillA();
      await f.sync.sync();
      final base = f.phone.documentFor(f.a)!;
      await f.office.update({
        'notes': 'Synthetic divergent office observation.',
      }, jobId: f.a);
      await f.phone.update(
        {'notes': 'Synthetic divergent mechanic observation.'},
        base: base,
        jobId: f.a,
      );
      await f.sync.sync();
      expect(conflicts(await f.phone.fields(jobId: f.a)), contains('notes'));
      final snapshot = await _read(f.phone);
      expect(snapshot.jobs[f.a]!.draftPhase, DraftPhase.conflicted);
      expect(snapshot.jobs[f.a]!.conflictKeys, contains('notes'));
      expect(snapshot.jobs[f.a]!.problem, isNotNull);
      expect(snapshot.jobs[f.a]!.currentVersions, isEmpty);
      expect(snapshot.jobs[f.b]!.draftPhase, DraftPhase.prepared);
    },
  );

  test(
    'Separate device revisions and future phone clock never invent one current review authority',
    () async {
      await f.fillA(target: f.office);
      final first = await f.office.submit(jobId: f.a);
      await f.office.decide(
        first['id'] as String,
        approve: false,
        reason: 'Synthetic office correction.',
      );
      await f.office.update({
        'notes': 'Synthetic current office observation.',
      }, jobId: f.a);
      final officeCurrent = await f.office.submit(jobId: f.a);
      final approved = await f.office.decide(
        officeCurrent['id'] as String,
        approve: true,
      );
      await f.sync.sync();
      final phoneCurrent = await f.phone.submit(jobId: f.a);
      expect(phoneCurrent['documentHash'], officeCurrent['documentHash']);
      expect(phoneCurrent['device'], isNot(officeCurrent['device']));
      expect(phoneCurrent['submissionRevision'], 1);
      expect(phoneCurrent['predecessorId'], isNull);
      expect(officeCurrent['submissionRevision'], 2);
      expect(
        DateTime.parse(
          phoneCurrent['createdAt'] as String,
        ).isAfter(DateTime.parse(officeCurrent['createdAt'] as String)),
        isTrue,
      );
      await f.sync.sync();
      final snapshot = await _read(f.office);
      final current = snapshot.jobs[f.a]!;
      expect(current.ambiguousCurrentVersions, isTrue);
      expect(_ids(current.currentVersions), {
        officeCurrent['id'],
        phoneCurrent['id'],
      });
      expect(_ids(snapshot.undecided), {phoneCurrent['id']});
      expect(
        current.currentVersions
            .singleWhere((v) => v.id == officeCurrent['id'])
            .receipt,
        approved,
      );
      expect(
        current.currentVersions
            .singleWhere((v) => v.id == phoneCurrent['id'])
            .decision,
        isNull,
      );
      expect(await f.office.approvalProblem(phoneCurrent), isNull);
      await f.office.decide(
        phoneCurrent['id'] as String,
        approve: false,
        reason: 'Synthetic separate actor record returned.',
      );
      final returned = await _read(f.office);
      expect(returned.undecided, isEmpty);
      expect(returned.jobs[f.a]!.ambiguousCurrentVersions, isTrue);
      expect(
        returned.jobs[f.a]!.currentVersions.map((v) => v.decision).toSet(),
        {'approved', 'returned'},
      );
      expect(
        returned.jobs[f.a]!.currentVersions
            .singleWhere((v) => v.id == officeCurrent['id'])
            .receipt,
        approved,
      );
    },
  );

  test(
    'Older undecided version stays returnable after current successor approval and its later return preserves current approval',
    () async {
      final first = await f.submittedA();
      await f.phone.update({
        'notes': 'Synthetic actual successor draft.',
      }, jobId: f.a);
      final second = await f.phone.submit(jobId: f.a);
      await f.sync.sync();
      final pending = await _read(f.office);
      expect(_ids(pending.undecided), {first['id'], second['id']});
      expect(_ids(pending.jobs[f.a]!.currentVersions), {second['id']});
      expect(
        await f.office.approvalProblem(first),
        'Work has changed. Return this version and request a new submission.',
      );
      final before = _rawState(f.office);
      await expectLater(
        f.office.decide(first['id'] as String, approve: true),
        throwsStateError,
      );
      expect(_rawState(f.office), before);
      expect(await f.office.approvalProblem(second), isNull);
      f.clocks.office = f.clocks.office.add(const Duration(minutes: 1));
      final approved = await f.office.decide(
        second['id'] as String,
        approve: true,
      );
      final oneLeft = await _read(f.office);
      expect(_ids(oneLeft.undecided), {first['id']});
      expect(oneLeft.jobs[f.a]!.currentVersions.single.receipt, approved);
      f.clocks.office = f.clocks.office.add(const Duration(minutes: 1));
      final returned = await f.office.decide(
        first['id'] as String,
        approve: false,
        reason: 'Synthetic obsolete version returned.',
      );
      final reviewed = await _read(f.office);
      expect(reviewed.undecided, isEmpty);
      expect(_ids(reviewed.reviewed), {first['id'], second['id']});
      expect(reviewed.jobs[f.a]!.currentVersions.single.receipt, approved);
      expect(
        reviewed.jobs[f.a]!.history
            .singleWhere((v) => v.id == first['id'])
            .receipt,
        returned,
      );
      expect(f.office.receipts.last, returned);
      expect(
        DateTime.parse(
          returned['reviewedAt'] as String,
        ).isAfter(DateTime.parse(approved['reviewedAt'] as String)),
        isTrue,
      );
    },
  );

  test(
    'Pure projection freezes captured input and does not create decisions for changed work',
    () async {
      final command = await f.submittedA();
      final receipt = await f.office.decide(
        command['id'] as String,
        approve: true,
      );
      await f.sync.sync();
      await f.phone.update({
        'notes': 'Synthetic changed pure-projector draft.',
      }, jobId: f.a);
      final context = _copy(f.phone.jobContextFor(f.a));
      final alternatives = _copy(await f.phone.fields(jobId: f.a));
      final commands = f.phone.submissions.map(_copy).toList();
      final receipts = f.phone.receipts.map(_copy).toList();
      final captured = contentHash([context, alternatives, commands, receipts]);
      final progress = projectJobProgress(
        jobId: f.a,
        context: context,
        documentHash: digest(f.phone.documentFor(f.a)!),
        alternatives: alternatives,
        submissions: commands,
        receipts: receipts,
        evidenceComplete: {digest(f.photo): true},
      );
      expect(
        contentHash([context, alternatives, commands, receipts]),
        captured,
      );
      expect(progress.draftPhase, DraftPhase.ready);
      expect(progress.currentVersions, isEmpty);
      expect(progress.history.single.receipt, receipt);
      context['company'] = 'Synthetic mutated caller input';
      (commands.single['values'] as Json)['notes'] =
          'Synthetic mutated caller input';
      receipts.single['decision'] = 'returned';
      expect(progress.context['company'], f.phone.catalog!['company']);
      expect(progress.history.single.submission['values'], command['values']);
      expect(progress.history.single.decision, 'approved');
      expect(
        () => progress.context['company'] = 'mutate',
        throwsUnsupportedError,
      );
      expect(
        () => (progress.history.single.submission['values'] as Json)['notes'] =
            'mutate',
        throwsUnsupportedError,
      );
      final snapshot = await _read(f.phone);
      expect(() => snapshot.jobs.clear(), throwsUnsupportedError);
      expect(() => snapshot.reviewed.clear(), throwsUnsupportedError);
      expect(() => snapshot.jobs[f.a]!.history.clear(), throwsUnsupportedError);
      expect(
        () => snapshot.jobs[f.a]!.conflictKeys.add('notes'),
        throwsUnsupportedError,
      );
    },
  );
}
