import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/approval_rules.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/model.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';

String _durableState(LabStore store) => contentHash({
  for (final table in [
    'settings',
    'documents',
    'submissions',
    'receipts',
    'events',
    'phones',
    'invites',
  ])
    table: store.db
        .select('SELECT * FROM $table ORDER BY rowid')
        .map((row) => Map<String, dynamic>.from(row))
        .toList(),
});

void main() {
  setUpAll(
    () => RustLib.init(
      externalLibrary: ExternalLibrary.open(
        Platform.environment['MAINTENANCE_NATIVE_LIBRARY'] ??
            File('rust/target/debug/librust_lib_sync_lab.so').absolute.path,
      ),
    ),
  );
  late Directory root;
  late LabStore office, phone;
  late String jobId;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('maintenance-ingestion-');
    office = await LabStore.open(
      Directory('${root.path}/office'),
      office: true,
    );
    await office.createCompany('Synthetic ingestion company');
    final equipment = await office.addEquipment(
      name: 'Synthetic guard assembly',
      meterUnit: 'none',
    );
    final template = await office.publishChecklist(
      title: 'Synthetic guard inspection',
      items: [
        {'id': 'guard', 'label': 'Inspect the guard', 'input_type': 'check'},
      ],
    );
    final job = await office.prepareWork(
      equipmentId: equipment['id'] as String,
      templateId: template['id'] as String,
      title: 'Synthetic prepared inspection',
    );
    jobId = job['id'] as String;
    phone = await LabStore.open(Directory('${root.path}/phone'), office: false);
    await phone.importOfficeBundle(await office.publicBundle());
    await phone.update({
      'answer:guard': {'result': 'pass', 'value': ''},
      'notes': 'Synthetic inspected guard is fitted.',
    }, jobId: jobId);
    await phone.attach([1, 3, 5, 7], jobId: jobId);
    await office.evidence.add([1, 3, 5, 7]);
    office.saveDocument(phone.documentFor(jobId)!, jobId: jobId);
  });

  tearDown(() async {
    await phone.close();
    await office.close();
    await root.delete(recursive: true);
  });

  for (final approved in [false, true]) {
    test(
      'unchanged ${approved ? 'approved' : 'returned'} version keeps one immutable identity',
      () async {
        final original = await phone.submit(jobId: jobId);
        await office.acceptSubmission(original, phone.device);
        await office.decide(
          original['id'] as String,
          approve: approved,
          reason: approved ? '' : 'Record a revised synthetic finding.',
        );
        final duplicate = <String, dynamic>{
          ...original,
          'id': 'synthetic-duplicate-version',
          'predecessorId': original['id'],
          'submissionRevision': 2,
        };
        final before = _durableState(office);
        await expectLater(
          office.acceptSubmission(duplicate, phone.device),
          throwsStateError,
        );
        expect(_durableState(office), before);
        await office.acceptSubmission(original, phone.device);
        expect(_durableState(office), before);
        expect(office.submissions, hasLength(1));
        expect(office.receipts, hasLength(1));
        expect(
          () => ApprovalRules.validateSubmissionHistory([original, duplicate]),
          throwsStateError,
        );

        await phone.update({
          'notes': 'A changed synthetic inspection finding.',
        }, jobId: jobId);
        final changed = await phone.submit(jobId: jobId);
        expect(changed['documentHash'], isNot(original['documentHash']));
        expect(changed['submissionRevision'], 2);
        expect(changed['predecessorId'], original['id']);
        office.saveDocument(phone.documentFor(jobId)!, jobId: jobId);
        await office.acceptSubmission(changed, phone.device);
        await office.decide(changed['id'] as String, approve: true);
        ApprovalRules.validateSubmissionHistory([original, changed]);
        expect(office.submissions, hasLength(2));
        expect(office.receipts, hasLength(2));
      },
    );
  }

  test(
    'local status rejects before persistence and clean same-ID retry works',
    () async {
      final original = await phone.submit(jobId: jobId);
      final before = _durableState(office);
      for (final state in ['queued', null]) {
        final poison = <String, dynamic>{...original, '_state': state};
        await expectLater(
          office.acceptSubmission(poison, phone.device),
          throwsStateError,
        );
        await expectLater(
          ApprovalRules.validateSubmission(poison, office.jobContextFor(jobId)),
          throwsStateError,
        );
        expect(_durableState(office), before);
      }
      await office.acceptSubmission(original, phone.device);
      await office.decide(original['id'] as String, approve: true);
      expect(office.submissions, hasLength(1));
      expect(office.receipts, hasLength(1));
      final getterRecord = office.submissions.single;
      await expectLater(
        ApprovalRules.validateSubmission(
          getterRecord,
          office.jobContextFor(jobId),
        ),
        throwsStateError,
      );
      await ApprovalRules.validateSubmission(
        getterRecord,
        office.jobContextFor(jobId),
        allowLocalState: true,
      );
      expect(await office.approvalProblem(getterRecord), isNull);
    },
  );
}
