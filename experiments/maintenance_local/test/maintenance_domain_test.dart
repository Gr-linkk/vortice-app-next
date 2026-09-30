import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/maintenance_domain.dart';
import 'package:maintenance_local/model.dart';

Json copied(Json value) => jsonDecode(jsonEncode(value)) as Json;

Json catalogFixture({String unit = 'hours'}) {
  final equipment = makeEquipment(
    id: 'excavator',
    name: 'Excavator',
    serial: 'EX-24',
    meterUnit: unit,
  );
  final template = makeTemplate(
    id: 'inspection-v1',
    title: 'Daily inspection',
    provenance: {'kind': 'company-authored', 'reference': ''},
    items: [
      {'id': 'guards', 'label': 'Inspect guards', 'input_type': 'check'},
      {
        'id': 'pressure',
        'label': 'Oil pressure',
        'input_type': 'number',
        'unit': 'bar',
        'min': 10,
        'max': 20,
      },
      {
        'id': 'condition',
        'label': 'Describe condition',
        'input_type': 'text',
        'allow_na': true,
      },
    ],
  );
  final catalog = makeCatalog(
    id: 'company-a',
    name: 'North Construction',
    coordinatorName: 'Sam',
  );
  (catalog['equipment'] as List).add(equipment);
  (catalog['templates'] as List).add(template);
  (catalog['jobs'] as List).add(
    makeJob(
      id: 'inspection-1',
      title: 'Morning inspection',
      equipment: equipment,
      template: template,
    ),
  );
  return catalog;
}

Json alternativesOf(Json fields) => {
  for (final entry in fields.entries) entry.key: [entry.value],
};

Json completed(Json context, {num? meter = 0}) => alternativesOf({
  ...initialJobFields(context),
  'answer:guards': {'result': 'pass', 'value': ''},
  'answer:pressure': {'result': 'pass', 'value': '15'},
  'answer:condition': {'result': 'pass', 'value': 'No visible leaks'},
  'meter': meter,
  'notes': 'Inspected before starting. Follow-up findings stay visible.',
  'photo': 'a' * 64,
});

void main() {
  test(
    'a frozen work context survives newer publications and equipment edits',
    () {
      final catalog = catalogFixture();
      final original = jobContext(catalog, 'inspection-1');
      final frozenBytes = canonical(original);
      (catalog['equipment'] as List).single['name'] = 'Renamed excavator';
      final replacement = makeTemplate(
        id: 'inspection-v2',
        title: 'Revised inspection',
        version: 2,
        provenance: {'kind': 'company-authored'},
        items: [
          {'id': 'new-step', 'label': 'New instruction', 'input_type': 'check'},
        ],
      );
      (catalog['templates'] as List).add(replacement);
      expect(canonical(jobContext(catalog, 'inspection-1')), frozenBytes);
      original['equipment']['name'] = 'Caller changed its copy';
      original['job']['equipmentSnapshot']['name'] =
          'Caller changed nested job';
      expect(canonical(jobContext(catalog, 'inspection-1')), frozenBytes);
      expect(
        jobContext(catalog, 'inspection-1')['equipment']['name'],
        'Excavator',
      );
    },
  );

  test('uncached original publication remains usable as pinned provenance', () {
    final catalog = catalogFixture();
    final before = canonical(jobContext(catalog, 'inspection-1'));
    (catalog['templates'] as List).clear();
    validateCatalog(catalog);
    expect(canonical(jobContext(catalog, 'inspection-1')), before);
    expect(
      incompleteJob(
        completed(jobContext(catalog, 'inspection-1')),
        jobContext(catalog, 'inspection-1'),
      ),
      isNull,
    );
  });

  test('snapshots, units and context fields are checked together', () {
    final catalog = catalogFixture();
    final changed = copied(catalog);
    changed['jobs'][0]['checklistSnapshot']['items'][0]['label'] =
        'Changed later';
    expect(() => validateCatalog(changed), throwsStateError);
    final changedUnit = copied(catalog);
    changedUnit['jobs'][0]['meterUnit'] = 'km';
    expect(() => validateCatalog(changedUnit), throwsStateError);
    final context = jobContext(catalog, 'inspection-1');
    for (final field in ['revision', 'snapshotHash', 'jobId', 'equipmentId']) {
      final forged = copied(context)..[field] = 'different';
      expect(() => validateJobContext(forged), throwsStateError, reason: field);
    }
    final contextEquipment = copied(context);
    contextEquipment['equipment']['name'] = 'Unfrozen field';
    expect(() => initialJobFields(contextEquipment), throwsStateError);
  });

  test(
    'explicit zero is valid while an unknown required meter stays unknown',
    () {
      final context = jobContext(catalogFixture(), 'inspection-1');
      final draft = initialJobFields(context);
      expect(draft['meter'], isNull);
      expect(incompleteJob(completed(context, meter: 0), context), isNull);
      expect(
        incompleteJob(completed(context, meter: null), context),
        contains('do not guess'),
      );
      for (final meter in [-1, double.nan, double.infinity, 1000000000001]) {
        expect(
          () => validateJobDocument(completed(context, meter: meter), context),
          throwsStateError,
          reason: '$meter',
        );
      }
      final wrongUnit = completed(context)..['unit'] = ['km'];
      expect(() => validateJobDocument(wrongUnit, context), throwsStateError);
    },
  );

  test('calendar-only equipment needs no fabricated meter or hours unit', () {
    final context = jobContext(catalogFixture(unit: 'none'), 'inspection-1');
    expect(context['meterRequired'], isFalse);
    expect(initialJobFields(context)['unit'], 'none');
    expect(incompleteJob(completed(context, meter: null), context), isNull);
    expect(
      incompleteJob(completed(context, meter: 0), context),
      contains('leave the reading unknown'),
    );
  });

  test(
    'shared numeric limits reject an out-of-range pass but retain a finding',
    () {
      final context = jobContext(catalogFixture(unit: 'km'), 'inspection-1');
      for (final value in ['10', '20', '15,5']) {
        final answers = completed(context);
        answers['answer:pressure'] = [
          {'result': 'pass', 'value': value},
        ];
        expect(incompleteJob(answers, context), isNull, reason: value);
      }
      final outside = completed(context);
      outside['answer:pressure'] = [
        {'result': 'pass', 'value': '25'},
      ];
      expect(incompleteJob(outside, context), contains('valid answer'));
      for (final result in ['action', 'attention']) {
        outside['answer:pressure'] = [
          {'result': result, 'value': '25'},
        ];
        outside['answer:guards'] = [
          {'result': result, 'value': 'Loose guard recorded'},
        ];
        expect(incompleteJob(outside, context), isNull, reason: result);
      }
      for (final value in ['', 'NaN', 'Infinity', 'not a reading']) {
        outside['answer:pressure'] = [
          {'result': 'action', 'value': value},
        ];
        expect(
          incompleteJob(outside, context),
          contains('valid answer'),
          reason: value,
        );
      }
    },
  );

  test(
    'typed incomplete drafts remain durable without becoming submittable',
    () {
      final context = jobContext(catalogFixture(), 'inspection-1');
      final draft = completed(context);
      draft['answer:pressure'] = [
        {'result': null, 'value': '-'},
      ];
      validateJobDocument(draft, context);
      expect(incompleteJob(draft, context), contains('valid answer'));
      draft['answer:pressure'] = [
        {'result': 'pass', 'value': '15'},
      ];
      draft['answer:condition'] = [
        {'result': 'pass', 'value': '   '},
      ];
      expect(incompleteJob(draft, context), contains('valid answer'));
      draft['answer:condition'] = [
        {'result': 'na', 'value': ''},
      ];
      expect(incompleteJob(draft, context), isNull);
      draft['answer:guards'] = [
        {'result': 'na', 'value': ''},
      ];
      expect(incompleteJob(draft, context), contains('valid answer'));
    },
  );

  test(
    'a merge cannot silently combine answer result and value or omit a field',
    () {
      final context = jobContext(catalogFixture(), 'inspection-1');
      final conflict = completed(context);
      conflict['answer:guards'] = [
        {'result': 'pass', 'value': ''},
        {'result': 'action', 'value': 'Needs tightening'},
      ];
      expect(incompleteJob(conflict, context), contains('conflicting answers'));
      final partial = completed(context)..remove('answer:guards');
      expect(() => validateJobDocument(partial, context), throwsStateError);
      final unknown = completed(context)..['answer:unknown'] = [null];
      expect(() => validateJobDocument(unknown, context), throwsStateError);
      final nested = completed(context);
      nested['answer:guards'] = [
        {'result': 'pass', 'value': '', 'operator': 'forged'},
      ];
      expect(() => validateJobDocument(nested, context), throwsStateError);
      final emptyAlternative = completed(context)..['meter'] = [];
      expect(
        () => validateJobDocument(emptyAlternative, context),
        throwsStateError,
      );
    },
  );

  test('identical checklist shapes cannot authorize another job document', () {
    final catalog = catalogFixture();
    final firstJob = catalog['jobs'][0] as Json;
    (catalog['jobs'] as List).add(
      makeJob(
        id: 'inspection-2',
        title: 'Second inspection',
        equipment: firstJob['equipmentSnapshot'] as Json,
        template: firstJob['checklistSnapshot'] as Json,
      ),
    );
    final first = jobContext(catalog, 'inspection-1');
    final second = jobContext(catalog, 'inspection-2');
    expect(first['snapshotHash'], second['snapshotHash']);
    expect(
      () => validateJobDocument(completed(first), second),
      throwsStateError,
    );
    final changed = completed(first)..['_snapshotHash'] = ['b' * 64];
    expect(() => validateJobDocument(changed, first), throwsStateError);
    final conflicted = completed(first)
      ..['_jobId'] = ['inspection-1', 'inspection-2'];
    expect(() => validateJobDocument(conflicted, first), throwsStateError);
    final missing = completed(first)..remove('_snapshotHash');
    expect(() => validateJobDocument(missing, first), throwsStateError);
  });

  test(
    'notes and photo are required without treating a hash as stored bytes',
    () {
      final context = jobContext(catalogFixture(), 'inspection-1');
      final draft = completed(context)..['notes'] = ['  '];
      expect(incompleteJob(draft, context), contains('work notes'));
      draft['notes'] = ['Findings recorded'];
      draft['photo'] = [null];
      expect(incompleteJob(draft, context), contains('photo'));
      draft['photo'] = ['not-an-evidence-hash'];
      expect(() => validateJobDocument(draft, context), throwsStateError);
      // Byte existence/integrity is the authority adapter's separate acceptance
      // contract. The pure layer accepts only the reference's bounded shape.
      draft['photo'] = ['f' * 64];
      expect(incompleteJob(draft, context), isNull);
    },
  );

  test(
    'provenance cannot silently claim a verified manual or hosted source',
    () {
      Json template(Json provenance) => makeTemplate(
        id: 'procedure',
        title: 'Inspection',
        provenance: provenance,
        items: [
          {'id': 'check', 'label': 'Inspect', 'input_type': 'check'},
        ],
      );
      expect(
        () => template({'kind': 'verified-manual', 'reference': 'Manual p12'}),
        throwsStateError,
      );
      expect(
        () => template({'kind': 'company-authored', 'verified': true}),
        throwsStateError,
      );
      expect(
        () => template({'kind': 'manual-reference', 'reference': ''}),
        throwsStateError,
      );
      expect(
        template({
          'kind': 'manual-reference',
          'reference': 'Local manual p12',
        })['provenance'],
        {'kind': 'manual-reference', 'reference': 'Local manual p12'},
      );
    },
  );

  test(
    'catalogs reject unsupported versions, duplicate ids and unowned jobs',
    () {
      final catalog = catalogFixture();
      final future = copied(catalog)..['version'] = 2;
      expect(() => validateCatalog(future), throwsStateError);
      final duplicate = copied(catalog);
      duplicate['equipment'].add(copied(duplicate['equipment'][0] as Json));
      expect(() => validateCatalog(duplicate), throwsStateError);
      final unowned = copied(catalog);
      unowned['equipment'].clear();
      expect(() => validateCatalog(unowned), throwsStateError);
      expect(() => jobContext(catalog, 'other-job'), throwsStateError);
      expect(
        () => makeEquipment(id: '../escape', name: 'Unsafe id'),
        throwsStateError,
      );
    },
  );
}
