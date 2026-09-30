import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/job_progress.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/maintenance_domain.dart';
import 'package:maintenance_local/model.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';
import 'package:maintenance_local/work_progress_reader.dart';

const _hash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

Json _context() {
  final catalog = makeCatalog(
    id: 'company',
    name: 'Synthetic company',
    coordinatorName: 'Synthetic coordinator',
  );
  final equipment = makeEquipment(
    id: 'equipment',
    name: 'Synthetic equipment',
    meterUnit: 'none',
  );
  final template = makeTemplate(
    id: 'template',
    title: 'Synthetic inspection',
    provenance: {'kind': 'company-authored'},
    items: [
      {'id': 'guard', 'label': 'Inspect guard', 'input_type': 'check'},
      {
        'id': 'pressure',
        'label': 'Read pressure',
        'input_type': 'number',
        'min': 10,
        'max': 20,
      },
      {
        'id': 'optional',
        'label': 'Optional item',
        'input_type': 'check',
        'required': false,
      },
    ],
  );
  catalog['equipment'] = [equipment];
  catalog['templates'] = [template];
  catalog['jobs'] = [
    makeJob(
      id: 'job',
      title: 'Inspect equipment',
      equipment: equipment,
      template: template,
    ),
  ];
  return jobContext(catalog, 'job');
}

Json _alternatives(Json fields) => {
  for (final entry in fields.entries) entry.key: [entry.value],
};

void main() {
  late Json context, view;
  setUp(() {
    context = _context();
    view = _alternatives(initialJobFields(context));
  });
  JobProgress project({
    String? hash = _hash,
    Json? fields,
    List<Json> history = const [],
    List<Json> receipts = const [],
    bool photoComplete = true,
  }) => projectJobProgress(
    jobId: 'job',
    context: context,
    documentHash: hash,
    alternatives: fields ?? view,
    submissions: history,
    receipts: receipts,
    evidenceComplete: {_hash: photoComplete},
  );
  void fill() {
    view['answer:guard'] = [
      {'result': 'pass', 'value': ''},
    ];
    view['answer:pressure'] = [
      {'result': 'action', 'value': '25'},
    ];
    view['notes'] = ['A synthetic pressure finding.'];
    view['photo'] = [_hash];
  }

  test('prepared, partial and ready use shared required-answer rules', () {
    expect(project().draftPhase, DraftPhase.prepared);
    expect(project().requiredTotal, 2);
    view['answer:guard'] = [
      {'result': 'pass', 'value': ''},
    ];
    expect(project().draftPhase, DraftPhase.incomplete);
    expect(project().requiredAnswered, 1);
    fill();
    expect(project().draftPhase, DraftPhase.ready);
    expect(project().requiredAnswered, 2);
    expect(project().problem, isNull);
  });

  test('wrong numeric result and missing complete photo stay incomplete', () {
    fill();
    view['answer:pressure'] = [
      {'result': 'pass', 'value': '25'},
    ];
    expect(project().requiredAnswered, 1);
    expect(project().draftPhase, DraftPhase.incomplete);
    fill();
    final partial = project(photoComplete: false);
    expect(partial.draftPhase, DraftPhase.incomplete);
    expect(partial.photoState, PhotoState.missingOrPartial);
    expect(partial.problem, isNotNull);
  });

  test(
    'photo conflicts choose no winner and malformed markers are unavailable',
    () {
      fill();
      view['photo'] = [_hash, null];
      final conflict = project();
      expect(conflict.draftPhase, DraftPhase.conflicted);
      expect(conflict.photoState, PhotoState.conflicted);
      expect(conflict.conflictKeys, ['photo']);
      view['_jobId'] = ['different-job'];
      expect(project().draftPhase, DraftPhase.unavailable);
      expect(project(hash: null).draftPhase, DraftPhase.unavailable);
    },
  );

  test('exact versions and historical decisions do not order actor chains', () {
    fill();
    final first = <String, dynamic>{
      'id': 'one',
      'jobId': 'job',
      'device': 'phone-a',
      'documentHash': _hash,
      'submissionRevision': 9,
      '_state': 'received',
      'values': {'photo': _hash},
    };
    final second = <String, dynamic>{
      ...first,
      'id': 'two',
      'device': 'phone-b',
      'submissionRevision': 1,
      '_state': 'queued',
    };
    final receipt = <String, dynamic>{
      'submissionId': 'one',
      'decision': 'approved',
      'values': {'notes': 'Frozen notes'},
    };
    final p = project(history: [first, second], receipts: [receipt]);
    expect(p.currentVersions.map((v) => v.id), ['one', 'two']);
    expect(p.ambiguousCurrentVersions, isTrue);
    expect(p.queuedVersions.single.id, 'two');
    expect(p.approvedVersions.single.id, 'one');
    final changed = project(
      hash: 'different-document',
      history: [first],
      receipts: [receipt],
    );
    expect(changed.currentVersions, isEmpty);
    expect(changed.approvedVersions.single.id, 'one');
    expect(changed.draftPhase, DraftPhase.ready);
      first['values']['photo'] = 'Changed caller photo';
    receipt['values']['notes'] = 'Mutated caller data';
    context['equipment']['name'] = 'Mutated caller equipment';
    expect(p.history.first.submission['values']['photo'], _hash);
    expect(p.history.first.receipt!['values']['notes'], 'Frozen notes');
    expect(p.context['equipment']['name'], 'Synthetic equipment');
    expect(() => p.context['equipment']['name'] = 'x', throwsUnsupportedError);
    expect(() => p.history.clear(), throwsUnsupportedError);
  });

  group('bulk reader', () {
    setUpAll(
      () => RustLib.init(
        externalLibrary: ExternalLibrary.open(
          Platform.environment['MAINTENANCE_NATIVE_LIBRARY'] ??
              File('rust/target/debug/librust_lib_sync_lab.so').absolute.path,
        ),
      ),
    );
    late Directory root;
    late LabStore store;
    late String firstId, secondId;
    setUp(() async {
      root = await Directory.systemTemp.createTemp(
        'maintenance-progress-reader-',
      );
      store = await LabStore.open(root, office: true);
      await store.createCompany('Synthetic reader company');
      final equipment = await store.addEquipment(
        name: 'Synthetic reader equipment',
        meterUnit: 'none',
      );
      final template = await store.publishChecklist(
        title: 'Synthetic reader checklist',
        items: [
          {'id': 'guard', 'label': 'Inspect guard', 'input_type': 'check'},
        ],
      );
      Future<String> prepare(String title) async =>
          (await store.prepareWork(
                equipmentId: equipment['id'] as String,
                templateId: template['id'] as String,
                title: title,
              ))['id']
              as String;
      firstId = await prepare('First inspection');
      secondId = await prepare('Second inspection');
    });
    tearDown(() async {
      await store.close();
      await root.delete(recursive: true);
    });

    test(
      'selection is excluded and late captured reads cannot inherit edits',
      () async {
        final first = await readWorkProgress(store);
        store.selectJob(firstId);
        expect(await workProgressToken(store), first.token);
        store.selectJob(secondId);
        expect(await workProgressToken(store), first.token);
        final pending = readWorkProgress(store);
        await store.update({
          'notes': 'Later nonselected saved work.',
        }, jobId: firstId);
        final captured = await pending;
        expect(
          captured.jobs[firstId]!.documentHash,
          first.jobs[firstId]!.documentHash,
        );
        expect(await workProgressToken(store), isNot(captured.token));
      },
    );

    test(
      'complete partial remains untouched and integrity changes freshness',
      () async {
        final bytes = [1, 2, 3, 4];
        final hash = digest(bytes);
        await store.update({
          'answer:guard': {'result': 'pass', 'value': ''},
          'notes': 'Synthetic complete inspection.',
          'photo': hash,
        }, jobId: firstId);
        await store.evidence.root.create();
        final part = File('${store.evidence.root.path}/$hash.part');
        await part.writeAsBytes(bytes);
        final rawBefore = canonical(
          store.db
              .select('SELECT * FROM documents')
              .map((row) => Map<String, dynamic>.from(row))
              .toList(),
        );
        final incomplete = await readWorkProgress(store);
        expect(
          incomplete.jobs[firstId]!.photoState,
          PhotoState.missingOrPartial,
        );
        expect(await part.exists(), isTrue);
        expect(await store.evidence.file(hash).exists(), isFalse);
        expect(
          canonical(
            store.db
                .select('SELECT * FROM documents')
                .map((row) => Map<String, dynamic>.from(row))
                .toList(),
          ),
          rawBefore,
        );
        await store.evidence.file(hash).writeAsBytes(bytes);
        final complete = await readWorkProgress(store);
        expect(complete.jobs[firstId]!.draftPhase, DraftPhase.ready);
        expect(complete.token, isNot(incomplete.token));
        await store.evidence.file(hash).writeAsBytes([4, 3, 2, 1]);
        expect(await workProgressToken(store), isNot(complete.token));
        await store.evidence.file(hash).writeAsBytes(bytes);
        expect(await workProgressToken(store), complete.token);
        expect(await part.readAsBytes(), bytes);
      },
    );
  });
}
