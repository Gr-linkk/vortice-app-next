import 'dart:convert';
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/device_authority.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/local_sync.dart';
import 'package:maintenance_local/model.dart';
import 'package:maintenance_local/office_backup.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';
import 'package:sqlite3/sqlite3.dart';

// These fixtures deliberately reuse item IDs across different equipment/jobs.
// Visible answer equality must not become authority to merge or review a job.
const _items = <Json>[
  {'id': 'guard', 'label': 'Inspect the belt guard', 'input_type': 'check'},
  {
    'id': 'pressure',
    'label': 'Record hydraulic pressure',
    'input_type': 'number',
    'unit': 'psi',
    'min': 10,
    'max': 30,
  },
  {'id': 'finding', 'label': 'Describe the inspection', 'input_type': 'text'},
  {
    'id': 'optional',
    'label': 'Inspect the optional attachment',
    'input_type': 'check',
    'allow_na': true,
  },
];

Json _copy(Json value) => jsonDecode(canonical(value)) as Json;
String _id(Json record) => record['id'] as String;

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
  late DateTime clock;
  final stores = <LabStore>[];

  Directory path(String name) => Directory('${root.path}/$name');
  Future<LabStore> open(String name, {required bool office}) async {
    final store = await LabStore.open(
      path(name),
      office: office,
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
    root = await Directory.systemTemp.createTemp('maintenance-workflow-test-');
    clock = DateTime.utc(2026, 9, 30, 8);
  });

  tearDown(() async {
    for (final store in stores) {
      await store.close();
    }
    stores.clear();
    await root.delete(recursive: true);
  });

  Future<LabStore> company([String name = 'office']) async {
    final store = await open(name, office: true);
    await store.createCompany(
      'Synthetic Harbour Maintenance',
      coordinatorName: 'Synthetic coordinator',
    );
    return store;
  }

  Future<Json> prepare(
    LabStore office, {
    String name = 'Synthetic hydraulic power unit',
    String meterUnit = 'hours',
    List<Json> items = _items,
    String title = 'Inspect before maintenance',
  }) async {
    final equipment = await office.addEquipment(
      name: name,
      serial: 'SYNTHETIC-${office.equipment.length + 1}',
      meterUnit: meterUnit,
    );
    final template = await office.publishChecklist(
      title: 'Synthetic inspection procedure',
      items: items,
      provenance: {
        'kind': 'local-reference',
        'reference': 'Synthetic local procedure, page 3; no remote fetch',
      },
    );
    return office.prepareWork(
      equipmentId: _id(equipment),
      templateId: _id(template),
      title: title,
    );
  }

  Future<String> fill(
    LabStore store,
    String jobId, {
    num? meter = 17.5,
    String notes = 'Synthetic finding: guard inspection is recorded.',
    List<int> photo = const [3, 17, 29, 41, 53],
  }) async {
    await store.update({
      'answer:guard': {'result': 'pass', 'value': ''},
      'answer:pressure': {'result': 'pass', 'value': '20'},
      'answer:finding': {'result': 'pass', 'value': 'Guard fitted and secure.'},
      'answer:optional': {'result': 'na', 'value': ''},
      'meter': meter,
      'notes': notes,
    }, jobId: jobId);
    return store.attach(photo, jobId: jobId);
  }

  test(
    'A new company is blank and only the office can author its catalog',
    () async {
      final office = await company();
      expect(office.catalog!['company'], 'Synthetic Harbour Maintenance');
      expect(office.catalog!['coordinatorName'], 'Synthetic coordinator');
      expect(office.equipment, isEmpty);
      expect(office.templates, isEmpty);
      expect(office.jobs, isEmpty);
      expect(office.activeJobId, isNull);
      expect(office.document, isNull);

      final job = await prepare(office);
      final phone = await open('phone', office: false);
      await phone.importOfficeBundle(await office.publicBundle());
      final catalog = canonical(phone.catalog);
      await expectLater(
        phone.createCompany('Phone invented company'),
        throwsStateError,
      );
      await expectLater(
        phone.addEquipment(name: 'Phone invented equipment'),
        throwsStateError,
      );
      await expectLater(
        phone.publishChecklist(title: 'Phone procedure', items: _items),
        throwsStateError,
      );
      await expectLater(
        phone.prepareWork(
          equipmentId: job['equipmentId'] as String,
          templateId: office.templates.single['id'] as String,
          title: 'Phone invented work',
        ),
        throwsStateError,
      );
      expect(canonical(phone.catalog), catalog);
      expect(phone.jobs.map(_id), [_id(job)]);
    },
  );

  test(
    'Invalid office authoring leaves the durable catalog unchanged',
    () async {
      final office = await company();
      final before = canonical(office.catalog);
      for (final unit in [
        'Hours',
        'seconds',
        '',
        'hours; DROP TABLE documents',
      ]) {
        await expectLater(
          office.addEquipment(name: 'Synthetic unit', meterUnit: unit),
          throwsStateError,
        );
        expect(canonical(office.catalog), before);
      }
      for (final items in <List<Json>>[
        [],
        [
          {'id': 'same', 'label': 'First', 'input_type': 'check'},
          {'id': 'same', 'label': 'Second', 'input_type': 'check'},
        ],
        [
          {
            'id': 'reversed',
            'label': 'Reading',
            'input_type': 'number',
            'min': 30,
            'max': 10,
          },
        ],
        [
          {
            'id': 'invalid',
            'label': 'Reading',
            'input_type': 'number',
            'max': double.infinity,
          },
        ],
      ]) {
        await expectLater(
          office.publishChecklist(
            title: 'Invalid synthetic procedure',
            items: items,
          ),
          throwsA(anyOf(isA<StateError>(), isA<JsonUnsupportedObjectError>())),
        );
        expect(canonical(office.catalog), before);
      }
      await expectLater(
        office.prepareWork(
          equipmentId: 'absent-equipment',
          templateId: 'absent-template',
          title: 'No authority',
        ),
        throwsStateError,
      );
      expect(canonical(office.catalog), before);
      expect(office.db.select('SELECT * FROM documents'), isEmpty);
    },
  );

  test(
    'Prepared work freezes procedure and equipment even after later publications',
    () async {
      final office = await company();
      final first = await prepare(office);
      final firstId = _id(first);
      final frozen = canonical(office.jobContextFor(firstId));
      final original = _copy(first);

      // Mutating caller-owned results must not edit the office publication/job.
      (first['checklistSnapshot'] as Json)['title'] = 'Caller changed this map';
      (first['equipmentSnapshot'] as Json)['name'] =
          'Caller invented an asset name';
      expect(canonical(office.jobContextFor(firstId)), frozen);

      final later = await prepare(
        office,
        name: 'Synthetic tracked excavator',
        meterUnit: 'km',
        title: 'Later procedure work',
        items: [
          {
            'id': 'later',
            'label': 'Later published instruction',
            'input_type': 'check',
          },
        ],
      );
      expect(canonical(office.jobContextFor(firstId)), frozen);
      expect(office.jobs.first, original);
      expect(office.templates, hasLength(2));
      expect(
        office.jobContextFor(_id(later))['snapshotHash'],
        isNot(original['snapshotHash']),
      );
      expect(
        (await office.fields(jobId: firstId)).keys,
        contains('answer:pressure'),
      );
      expect(
        (await office.fields(jobId: firstId)).keys,
        isNot(contains('answer:later')),
      );
      await close(office);
      final reopened = await open('office', office: true);
      expect(canonical(reopened.jobContextFor(firstId)), frozen);
    },
  );

  test(
    'Job selection never redirects explicit drafts, photos, submissions, or decisions',
    () async {
      final office = await company();
      final a = _id(await prepare(office, name: 'Synthetic asset A'));
      final b = _id(await prepare(office, name: 'Synthetic asset B'));
      final photoA = await fill(
        office,
        a,
        meter: 101,
        notes: 'Synthetic job A.',
        photo: [1, 2, 3],
      );
      office.selectJob(b);
      final photoB = await fill(
        office,
        b,
        meter: 202,
        notes: 'Synthetic job B.',
        photo: [4, 5, 6],
      );
      await office.update({'notes': 'A saved while B is selected.'}, jobId: a);
      expect(office.activeJobId, b);
      expect(valuesOf(await office.fields())['notes'], 'Synthetic job B.');
      expect(
        valuesOf(await office.fields(jobId: a))['notes'],
        'A saved while B is selected.',
      );
      expect(valuesOf(await office.fields(jobId: a))['photo'], photoA);
      expect(valuesOf(await office.fields(jobId: b))['photo'], photoB);
      expect(
        digest(office.documentFor(a)!),
        isNot(digest(office.documentFor(b)!)),
      );

      final submissionA = await office.submit(jobId: a);
      final submissionB = await office.submit(jobId: b);
      final receiptA = await office.decide(
        submissionA['id'] as String,
        approve: true,
      );
      final receiptB = await office.decide(
        submissionB['id'] as String,
        approve: true,
      );
      expect(submissionA['jobId'], a);
      expect(submissionB['jobId'], b);
      expect(submissionA['equipmentId'], isNot(submissionB['equipmentId']));
      expect(submissionA['context'], office.jobContextFor(a));
      expect(submissionB['context'], office.jobContextFor(b));
      expect(receiptA['values'], submissionA['values']);
      expect(receiptB['values'], submissionB['values']);
      expect(office.receipts, hasLength(2));
      expect(() => office.selectJob('absent-job'), throwsStateError);
      expect(office.activeJobId, b);
    },
  );

  test(
    'Unknown usage stays unknown; zero is a real reading and frozen units are enforced',
    () async {
      final office = await company();
      final jobId = _id(await prepare(office));
      expect(valuesOf(await office.fields(jobId: jobId))['meter'], isNull);
      await fill(office, jobId, meter: null);
      await expectLater(office.submit(jobId: jobId), throwsStateError);
      expect(office.submissions, isEmpty);
      final before = digest(office.documentFor(jobId)!);
      for (final patch in <Json>[
        {'unit': 'km'},
        {'meter': -0.1},
        {'meter': 1e12 + 1},
        {'meter': '0'},
        {
          'answer:unpublished': {'result': 'pass', 'value': ''},
        },
      ]) {
        await expectLater(office.update(patch, jobId: jobId), throwsStateError);
        expect(digest(office.documentFor(jobId)!), before);
      }
      await office.update({'meter': 0}, jobId: jobId);
      final submission = await office.submit(jobId: jobId);
      expect((submission['values'] as Json)['meter'], 0);
      expect((submission['values'] as Json)['unit'], 'hours');
      expect(await office.approvalProblem(submission), isNull);
    },
  );

  test(
    'Numeric range failures require an honest finding and disallowed N/A is rejected',
    () async {
      final office = await company();
      final jobId = _id(await prepare(office));
      await fill(office, jobId);
      for (final value in ['9.99', '30.01', 'NaN', 'Infinity', '20 psi', '']) {
        await office.update({
          'answer:pressure': {'result': 'pass', 'value': value},
        }, jobId: jobId);
        await expectLater(office.submit(jobId: jobId), throwsStateError);
        expect(office.submissions, isEmpty);
      }
      await office.update({
        'answer:pressure': {'result': 'action', 'value': '35'},
      }, jobId: jobId);
      await office.update({
        'answer:guard': {'result': 'na', 'value': ''},
      }, jobId: jobId);
      await expectLater(office.submit(jobId: jobId), throwsStateError);
      await office.update({
        'answer:guard': {'result': 'action', 'value': ''},
      }, jobId: jobId);
      final finding = await office.submit(jobId: jobId);
      final receipt = await office.decide(
        finding['id'] as String,
        approve: true,
      );
      expect((receipt['values'] as Json)['answer:pressure'], {
        'result': 'action',
        'value': '35',
      });
      expect((receipt['values'] as Json)['answer:guard'], {
        'result': 'action',
        'value': '',
      });
      expect(receipt.containsKey('repairCompleted'), isFalse);
      expect(receipt.containsKey('equipmentAvailable'), isFalse);
    },
  );

  test(
    'Equipment with no usage meter submits without inventing zero',
    () async {
      final office = await company();
      final jobId = _id(await prepare(office, meterUnit: 'none'));
      await fill(office, jobId, meter: null);
      final original = await office.submit(jobId: jobId);
      expect((original['values'] as Json)['meter'], isNull);
      expect((original['values'] as Json)['unit'], 'none');
      await office.update({'meter': 0}, jobId: jobId);
      await expectLater(office.submit(jobId: jobId), throwsStateError);
      expect(office.submissions, hasLength(1));
    },
  );

  test(
    'Thirty offline days and a restart preserve company, job IDs, exact queue payloads, and photos',
    () async {
      final office = await company();
      final a = _id(await prepare(office, name: 'Synthetic offline asset A'));
      final b = _id(await prepare(office, name: 'Synthetic offline asset B'));
      var phone = await open('phone', office: false);
      await phone.importOfficeBundle(await office.publicBundle());
      final device = phone.device;
      final catalog = canonical(phone.catalog);
      final photoA = await fill(
        phone,
        a,
        meter: 0,
        photo: List.generate(300013, (i) => (i * 19 + 7) % 251),
      );
      final photoB = await fill(phone, b, meter: 42, photo: [9, 8, 7, 6]);
      final submissionA = await phone.submit(jobId: a);
      final submissionB = await phone.submit(jobId: b);
      final hashes = {
        a: digest(phone.documentFor(a)!),
        b: digest(phone.documentFor(b)!),
      };
      final evidence = await phone.evidence.manifest();
      phone.selectJob(a);
      await close(phone);
      clock = clock.add(const Duration(days: 30));
      phone = await open('phone', office: false);
      expect(phone.device, device);
      expect(canonical(phone.catalog), catalog);
      expect(phone.activeJobId, a);
      expect(phone.jobs.map(_id), [a, b]);
      expect(phone.submissions.map((p) => p['_state']), ['queued', 'queued']);
      expect(canonical(await phone.submit(jobId: a)), canonical(submissionA));
      expect(canonical(await phone.submit(jobId: b)), canonical(submissionB));
      expect(digest(phone.documentFor(a)!), hashes[a]);
      expect(digest(phone.documentFor(b)!), hashes[b]);
      expect(valuesOf(await phone.fields(jobId: a))['meter'], 0);
      expect(await phone.evidence.manifest(), evidence);
      expect(await phone.evidence.complete(photoA), isTrue);
      expect(await phone.evidence.complete(photoB), isTrue);
      expect(
        await phone.evidence.file(photoA).readAsBytes(),
        List.generate(300013, (i) => (i * 19 + 7) % 251),
      );
      expect(submissionA['createdAt'], '2026-09-30T08:00:00.000Z');
      expect(submissionB['createdAt'], submissionA['createdAt']);
    },
  );

  test(
    'An edit and revert cannot approve an older identical-looking submission',
    () async {
      final office = await company();
      final jobId = _id(await prepare(office));
      await fill(office, jobId);
      final original = await office.submit(jobId: jobId);
      final values = canonical(original['values']);
      await office.update({
        'notes': 'A later saved observation.',
      }, jobId: jobId);
      await office.update({
        'notes': (original['values'] as Json)['notes'],
      }, jobId: jobId);
      expect(canonical(valuesOf(await office.fields(jobId: jobId))), values);
      expect(
        digest(office.documentFor(jobId)!),
        isNot(original['documentHash']),
      );
      expect(await office.approvalProblem(original), isNotNull);
      await expectLater(
        office.decide(original['id'] as String, approve: true),
        throwsStateError,
      );
      expect(office.receipts, isEmpty);
      final current = await office.submit(jobId: jobId);
      expect(current['id'], isNot(original['id']));
      expect(current['documentHash'], digest(office.documentFor(jobId)!));
      expect(current['submissionRevision'], 2);
      expect(current['predecessorId'], original['id']);
      await office.decide(current['id'] as String, approve: true);
      expect(office.receipts.single['submissionId'], current['id']);
    },
  );

  test(
    'Return and resubmit preserve both decisions and exact predecessor history',
    () async {
      final office = await company();
      final jobId = _id(await prepare(office));
      await fill(office, jobId);
      final original = await office.submit(jobId: jobId);
      await expectLater(
        office.decide(original['id'] as String, approve: false),
        throwsStateError,
      );
      final returned = await office.decide(
        original['id'] as String,
        approve: false,
        reason: 'Record the loose guard finding.',
      );
      expect(
        await office.decide(
          original['id'] as String,
          approve: false,
          reason: 'Record the loose guard finding.',
        ),
        returned,
      );
      await office.update({
        'answer:guard': {'result': 'action', 'value': ''},
        'notes':
            'Synthetic follow-up: guard loose, isolate before further use.',
      }, jobId: jobId);
      final resubmitted = await office.submit(jobId: jobId);
      expect(resubmitted['submissionRevision'], 2);
      expect(resubmitted['predecessorId'], original['id']);
      expect(resubmitted['revision'], original['revision']);
      expect(resubmitted['context'], original['context']);
      final approved = await office.decide(
        resubmitted['id'] as String,
        approve: true,
      );
      await expectLater(
        office.decide(original['id'] as String, approve: true),
        throwsStateError,
      );
      expect(office.submissions.map((s) => s['id']), [
        original['id'],
        resubmitted['id'],
      ]);
      expect(office.receipts, [returned, approved]);
      expect((returned['values'] as Json)['answer:guard'], {
        'result': 'pass',
        'value': '',
      });
      expect((approved['values'] as Json)['answer:guard'], {
        'result': 'action',
        'value': '',
      });
      expect(
        office.db.select("SELECT * FROM events WHERE kind='reviewed'"),
        hasLength(2),
      );
      await close(office);
      final reopened = await open('office', office: true);
      expect(reopened.receipts, [returned, approved]);
    },
  );

  test(
    'Missing or corrupted complete-photo files block approval without creating a receipt',
    () async {
      final office = await company();
      final jobId = _id(await prepare(office));
      final hash = await fill(office, jobId);
      final submission = await office.submit(jobId: jobId);
      final file = office.evidence.file(hash);
      final bytes = await file.readAsBytes();
      await file.delete();
      await expectLater(
        office.decide(submission['id'] as String, approve: true),
        throwsStateError,
      );
      expect(office.receipts, isEmpty);
      await file.writeAsBytes([99, 98, 97], flush: true);
      expect(await office.evidence.complete(hash), isFalse);
      await expectLater(
        office.decide(submission['id'] as String, approve: true),
        throwsStateError,
      );
      expect(office.receipts, isEmpty);
      await file.writeAsBytes(bytes, flush: true);
      await office.decide(submission['id'] as String, approve: true);
      expect(office.receipts, hasLength(1));
    },
  );

  test(
    'Real catalog backup restores every job, version, draft, evidence reference, and authority fence',
    () async {
      final office = await company();
      // The synthetic office must establish its identity before it acquires
      // phones or signed history, just as ordinary startup does.
      final identity = await OfficeIdentity.load(office);
      final a = _id(await prepare(office, name: 'Synthetic recovery asset A'));
      final b = _id(await prepare(office, name: 'Synthetic recovery asset B'));
      await office.addEquipment(
        name: 'Synthetic unused spare',
        meterUnit: 'mi',
      );
      await office.publishChecklist(
        title: 'Synthetic unpublished-to-work procedure',
        items: _items,
      );
      await fill(office, a, photo: [1, 3, 5]);
      final submittedA = await office.submit(jobId: a);
      await office.decide(submittedA['id'] as String, approve: true);
      await office.attach([2, 4, 6], jobId: a);
      await fill(office, b, photo: [7, 9, 11]);
      final submittedB = await office.submit(jobId: b);
      await office.decide(
        submittedB['id'] as String,
        approve: false,
        reason: 'Synthetic follow-up needed.',
      );
      await office.attach([8, 10, 12], jobId: b);
      await office.evidence.add([13, 15, 17]);
      office.selectJob(a);
      final authority = DeviceAuthority(office);
      final activeToken = secret(),
          pendingToken = secret(),
          revokedToken = secret();
      for (final entry in {
        'active-phone': activeToken,
        'pending-phone': pendingToken,
        'revoked-phone': revokedToken,
      }.entries) {
        authority.request({
          'device': entry.key,
          'label': 'Synthetic ${entry.key}',
          'token': entry.value,
          'invitation': authority.invite(),
        });
      }
      authority.confirm('active-phone');
      authority.revoke('revoked-phone');
      final catalog = canonical(office.catalog);
      final documents = {
        for (final id in [a, b]) id: digest(office.documentFor(id)!),
      };
      final summary = await OfficeBackup.create(office, path('backup'));
      expect(summary.submissions, 2);
      expect(summary.receipts, 2);
      expect(summary.evidenceFiles, 5);
      authority.revoke('active-phone'); // The copied authority is now stale.
      await OfficeBackup.inspect(path('backup'));
      final result = await OfficeBackup.restore(
        path('backup'),
        path('restored'),
        expectedFingerprint: identity.fingerprint,
      );
      expect(result.phonesToReconfirm, 2);
      final copy = await open('restored', office: true);
      expect(copy.device, office.device);
      expect(canonical(copy.catalog), catalog);
      expect(copy.activeJobId, a);
      expect(copy.jobs.map(_id), [a, b]);
      expect(copy.equipment, hasLength(3));
      expect(copy.templates, hasLength(3));
      for (final id in [a, b]) {
        expect(copy.jobContextFor(id), office.jobContextFor(id));
        expect(await copy.fields(jobId: id), await office.fields(jobId: id));
        expect(digest(copy.documentFor(id)!), documents[id]);
      }
      expect(copy.submissions, office.submissions);
      expect(copy.receipts, office.receipts);
      expect(await copy.requiredEvidence(), await office.requiredEvidence());
      expect(await copy.evidence.manifest(), await office.evidence.manifest());
      expect(
        (await OfficeIdentity.load(copy)).fingerprint,
        identity.fingerprint,
      );
      final restoredAuthority = DeviceAuthority(copy);
      for (final token in [activeToken, pendingToken, revokedToken]) {
        expect(
          () => restoredAuthority.authenticate('Bearer $token'),
          throwsStateError,
        );
      }
      restoredAuthority.confirm('active-phone');
      expect(
        restoredAuthority.authenticate('Bearer $activeToken'),
        'active-phone',
      );
      restoredAuthority.confirm('revoked-phone');
      expect(
        () => restoredAuthority.authenticate('Bearer $revokedToken'),
        throwsStateError,
      );
      expect(copy.db.select('SELECT * FROM invites'), isEmpty);
    },
  );

  test(
    'A rehashed backup with missing or substituted job documents is semantically rejected',
    () async {
      final office = await company();
      final a = _id(await prepare(office, name: 'Synthetic integrity asset A'));
      final b = _id(await prepare(office, name: 'Synthetic integrity asset B'));
      await fill(office, a, photo: [1, 2, 3]);
      await fill(office, b, photo: [4, 5, 6]);
      await OfficeIdentity.load(office);
      for (final mutation in ['missing', 'substituted']) {
        final backup = path('backup-$mutation');
        await OfficeBackup.create(office, backup);
        final db = sqlite3.open('${backup.path}/workspace.sqlite');
        try {
          if (mutation == 'missing') {
            db.execute('DELETE FROM documents WHERE id=?', [a]);
          } else {
            db.execute('UPDATE documents SET bytes=? WHERE id=?', [
              office.documentFor(b),
              a,
            ]);
          }
        } finally {
          db.close();
        }
        // Keep the envelope internally consistent to probe catalog/document
        // authority checks, rather than ordinary checksum damage detection.
        final manifestFile = File('${backup.path}/manifest.json');
        final manifest = jsonDecode(await manifestFile.readAsString()) as Json;
        final bytes = await File(
          '${backup.path}/workspace.sqlite',
        ).readAsBytes();
        (manifest['files'] as Json)['workspace.sqlite'] = {
          'hash': digest(bytes),
          'size': bytes.length,
        };
        await manifestFile.writeAsString(canonical(manifest), flush: true);
        await expectLater(OfficeBackup.inspect(backup), throwsStateError);
        await expectLater(
          OfficeBackup.restore(backup, path('restore-$mutation')),
          throwsStateError,
        );
        expect(await path('restore-$mutation').exists(), isFalse);
        expect(
          digest(office.documentFor(a)!),
          isNot(digest(office.documentFor(b)!)),
        );
        expect(office.jobs.map(_id), [a, b]);
      }
    },
  );
}
