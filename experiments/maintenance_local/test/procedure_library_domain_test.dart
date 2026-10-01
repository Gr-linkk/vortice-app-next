import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/maintenance_domain.dart';
import 'package:maintenance_local/model.dart';
import 'package:maintenance_local/procedure_library.dart';

import 'support/procedure_library_fixture.dart';

Json _draft() {
  final source = procedurePublicationFixture();
  return copiedProcedureDraft(
    draftId: 'draft-a',
    publication: source,
    itemIds: [
      for (var i = 0; i < (source['items'] as List).length; i++) 'copy-$i',
    ],
  );
}

void main() {
  test('copy pins verified source and uses independent step identities', () {
    final source = procedurePublicationFixture();
    final before = canonical(source);
    final draft = copiedProcedureDraft(
      draftId: 'draft-a',
      publication: source,
      itemIds: ['copy-0', 'copy-1', 'copy-2', 'copy-3', 'copy-4'],
    );
    validateProcedureDraft(draft);
    expect(draft.keys.toSet(), {
      'id',
      'revision',
      'title',
      'items',
      'provenance',
      'source',
    });
    expect(draft['revision'], 1);
    expect(draft['source'], {
      'publicationId': source['id'],
      'version': 7,
      'hash': source['hash'],
      'title': source['title'],
    });
    expect(draft['provenance']['kind'], 'local-reference');
    final reference = draft['provenance']['reference'] as String;
    expect(reference, contains(source['id'] as String));
    expect(reference, contains('7'));
    expect(reference, contains(source['hash'] as String));
    final copiedItems = procedureItems(draft);
    expect(copiedItems.map((item) => item['id']), [
      'copy-0',
      'copy-1',
      'copy-2',
      'copy-3',
      'copy-4',
    ]);
    for (var i = 0; i < copiedItems.length; i++) {
      final copied = {...copiedItems[i]}..remove('id');
      final original = {...procedureItems(source)[i]}..remove('id');
      expect(copied, original);
    }
    draft['items'][0]['label'] = 'Caller edit';
    draft['source']['title'] = 'Caller changed attribution';
    draft['provenance']['reference'] = 'Caller changed reference';
    expect(canonical(source), before);
  });

  test('a forged publication cannot become trusted copied provenance', () {
    final source = procedurePublicationFixture();
    final invalid = <Json>[
      procedureCopy(source)..['hash'] = '0' * 64,
      procedureCopy(source)..['version'] = 0,
      procedureCopy(source)..['familyId'] = 'unsupported-family',
      procedureCopy(source)..['items'][0]['label'] = 'Unhashed instruction',
    ];
    for (final publication in invalid) {
      expect(
        () => copiedProcedureDraft(
          draftId: 'draft-a',
          publication: publication,
          itemIds: ['copy-0', 'copy-1', 'copy-2', 'copy-3', 'copy-4'],
        ),
        throwsStateError,
      );
    }
  });

  test(
    'copies reject incomplete, duplicate, old or invalid step identities',
    () {
      final source = procedurePublicationFixture();
      for (final ids in <List<String>>[
        [],
        ['copy-0'],
        ['copy-0', 'copy-0', 'copy-2', 'copy-3', 'copy-4'],
        ['guard', 'copy-1', 'copy-2', 'copy-3', 'copy-4'],
        ['copy-0', 'copy-1', 'copy-2', 'copy-3', 'bad id'],
        ['copy-0', 'copy-1', 'copy-2', 'copy-3', 'copy-4', 'extra'],
      ]) {
        expect(
          () => copiedProcedureDraft(
            draftId: 'draft-a',
            publication: source,
            itemIds: ids,
          ),
          throwsStateError,
          reason: '$ids',
        );
      }
    },
  );

  test('editing preserves pinned source, IDs and detached input ownership', () {
    final draft = _draft();
    final before = canonical(draft);
    final items = procedureItems(draft);
    items[0]['label'] = 'Edited instruction';
    final edited = editedProcedureDraft(
      draft,
      title: 'Revised title',
      items: items,
    );
    expect(edited['revision'], 2);
    expect(edited['title'], 'Revised title');
    expect(edited['source'], draft['source']);
    expect(edited['provenance'], draft['provenance']);
    expect(
      procedureItems(edited).map((item) => item['id']),
      procedureItems(draft).map((item) => item['id']),
    );
    expect(canonical(draft), before);
    items[0]['label'] = 'Later caller edit';
    expect(edited['items'][0]['label'], 'Edited instruction');
    edited['source']['title'] = 'Later attribution edit';
    edited['provenance']['reference'] = 'Later reference edit';
    expect(canonical(draft), before);
  });

  test('unfinished title, steps and labels save but cannot be published', () {
    final original = _draft();
    final unfinished = <Json>[
      editedProcedureDraft(
        original,
        title: '',
        items: procedureItems(original),
      ),
      editedProcedureDraft(original, title: 'Typed title', items: []),
      editedProcedureDraft(
        original,
        title: 'Typed title',
        items: [
          {'id': 'copy-0', 'label': '', 'input_type': 'check'},
        ],
      ),
    ];
    for (final draft in unfinished) {
      validateProcedureDraft(draft);
      expect(
        () =>
            publicationFromProcedureDraft(draft, publicationId: 'independent'),
        throwsStateError,
      );
    }
  });

  test(
    'publication uses v1 and retains absent, null, empty and zero values',
    () {
      final draft = _draft();
      final before = canonical(draft);
      final publication = publicationFromProcedureDraft(
        draft,
        publicationId: 'independent-publication',
      );
      expect(publication.keys.toSet(), {
        'id',
        'title',
        'version',
        'provenance',
        'items',
        'hash',
      });
      expect(publication['version'], 1);
      expect(publication['id'], 'independent-publication');
      expect(publication['provenance'], draft['provenance']);
      expect(publication['items'], draft['items']);
      final items = procedureItems(publication);
      expect(items[0]['required'], isFalse);
      expect(items[0]['allow_na'], isTrue);
      expect(items[1]['unit'], 'bar');
      expect(items[1]['min'], 0);
      expect(items[1].containsKey('max'), isTrue);
      expect(items[1]['max'], isNull);
      expect(items[2].containsKey('unit'), isTrue);
      expect(items[2]['unit'], isNull);
      expect(items[2]['min'], isNull);
      expect(items[2]['max'], 0);
      expect(items[3].containsKey('unit'), isFalse);
      expect(items[3].containsKey('min'), isFalse);
      expect(items[3].containsKey('max'), isFalse);
      expect(items[4]['unit'], '');
      final unhashed = {...publication}..remove('hash');
      expect(publication['hash'], contentHash(unhashed));
      final catalog = makeCatalog(
        id: 'company',
        name: 'Synthetic',
        coordinatorName: 'Sam',
      );
      (catalog['templates'] as List).add(publication);
      validateCatalog(catalog);
      publication['items'][1]['min'] = 55;
      publication['provenance']['reference'] = 'Caller edit';
      expect(canonical(draft), before);
    },
  );

  test('finalized drafts cannot edit or produce another publication', () {
    final finalized = _draft()..['publishedTemplateId'] = 'independent';
    validateProcedureDraft(finalized);
    expect(
      () => editedProcedureDraft(
        finalized,
        title: 'Later',
        items: procedureItems(finalized),
      ),
      throwsStateError,
    );
    expect(
      () => publicationFromProcedureDraft(finalized, publicationId: 'another'),
      throwsStateError,
    );
  });

  test(
    'strict draft validation rejects unsupported or ambiguous definitions',
    () {
      final valid = _draft();
      final invalid = <Json>[
        procedureCopy(valid)..remove('source'),
        procedureCopy(valid)..['familyId'] = 'future-family',
        procedureCopy(valid)..['revision'] = 0,
        procedureCopy(valid)..['revision'] = 1.0,
        procedureCopy(valid)..['title'] = 'x' * 201,
        procedureCopy(valid)
          ..['items'] = List.generate(
            201,
            (i) => {'id': 's-$i', 'label': '', 'input_type': 'check'},
          ),
        procedureCopy(valid)..['source']['hash'] = 'bad',
        procedureCopy(valid)..['source']['version'] = 0,
        procedureCopy(valid)..['source']['editable'] = true,
        procedureCopy(valid)..['provenance']['kind'] = 'company-authored',
        procedureCopy(valid)..['items'][0]['id'] = 'bad id',
        procedureCopy(valid)..['items'][1]['id'] = 'copy-0',
        procedureCopy(valid)..['items'][0]['input_type'] = 'choice',
        procedureCopy(valid)..['items'][0]['required'] = null,
        procedureCopy(valid)..['items'][0]['allow_na'] = 'false',
        procedureCopy(valid)..['items'][0]['hidden'] = true,
        procedureCopy(valid)..['items'][1]['unit'] = 'x' * 41,
        procedureCopy(valid)..['items'][1]['min'] = '0',
        procedureCopy(valid)..['items'][1]['max'] = -1,
        procedureCopy(valid)..['items'][0]['min'] = 0,
        procedureCopy(valid)..['items'][1]['min'] = double.nan,
        procedureCopy(valid)..['items'][1]['max'] = double.infinity,
        procedureCopy(valid)..['items'][1]['min'] = -1000000000001,
      ];
      for (var i = 0; i < invalid.length; i++) {
        expect(
          () => validateProcedureDraft(invalid[i]),
          throwsStateError,
          reason: 'malformed draft $i',
        );
      }
      expect(canonical(valid), canonical(_draft()));
    },
  );
}
