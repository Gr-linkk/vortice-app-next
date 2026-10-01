import 'dart:convert';

import 'maintenance_domain.dart';
import 'model.dart';

const _draftKeys = {'id', 'revision', 'title', 'items', 'provenance', 'source'};
const _sourceKeys = {'publicationId', 'version', 'hash', 'title'};
const _stepKeys = {
  'id',
  'label',
  'input_type',
  'unit',
  'min',
  'max',
  'required',
  'allow_na',
};
const _stepTypes = {'check', 'number', 'text'};
const _maxRevision = 1000000;
final _identity = RegExp(r'^[a-zA-Z0-9_-]{1,100}$');

Never _invalid(String message) => throw StateError(message);

Json _copy(Json value) => jsonDecode(jsonEncode(value)) as Json;

Json _map(dynamic value, String label) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    _invalid('Invalid $label.');
  }
  return Map<String, dynamic>.from(value);
}

void _shape(
  Json value,
  Set<String> required,
  Set<String> allowed,
  String label,
) {
  if (value.keys.toSet().difference(allowed).isNotEmpty ||
      required.difference(value.keys.toSet()).isNotEmpty) {
    _invalid('Unsupported $label shape.');
  }
}

void _id(dynamic value, String label) {
  if (value is! String || !_identity.hasMatch(value)) {
    _invalid('Invalid $label identity.');
  }
}

void _text(dynamic value, String label, int limit, {bool empty = false}) {
  if (value is! String ||
      value.length > limit ||
      (!empty && value.trim().isEmpty)) {
    _invalid('Invalid $label.');
  }
}

List<Json> _items(dynamic value) {
  if (value is! List || value.length > 200) {
    _invalid('Use at most 200 procedure steps.');
  }
  return value.map((item) => _map(item, 'procedure step')).toList();
}

Json _provenance(Json source) => {
  'kind': 'local-reference',
  'reference':
      'Independent copy of local publication ${source['publicationId']}, '
      'version ${source['version']}, hash ${source['hash']}. '
      'Source title: ${source['title']}',
};

void _validateSource(Json source) {
  _shape(source, _sourceKeys, _sourceKeys, 'procedure source');
  _id(source['publicationId'], 'source publication');
  _text(source['title'], 'source publication title', 200);
  if (source['version'] is! int ||
      source['version'] < 1 ||
      source['version'] > 1000000 ||
      source['hash'] is! String ||
      !hashPattern.hasMatch(source['hash'])) {
    _invalid('Invalid source publication version or hash.');
  }
}

void _validateItem(Json item) {
  _shape(item, {'id', 'label', 'input_type'}, _stepKeys, 'procedure step');
  _id(item['id'], 'procedure step');
  _text(item['label'], 'procedure step label', 1000, empty: true);
  if (!_stepTypes.contains(item['input_type']) ||
      (item.containsKey('required') && item['required'] is! bool) ||
      (item.containsKey('allow_na') && item['allow_na'] is! bool)) {
    _invalid('Invalid procedure step definition.');
  }
  if (item['unit'] != null) {
    _text(item['unit'], 'reading unit', 40, empty: true);
  }
  for (final key in ['min', 'max']) {
    final value = item[key];
    if (value != null &&
        (item['input_type'] != 'number' ||
            value is! num ||
            !value.isFinite ||
            value.abs() > 1e12)) {
      _invalid('Invalid procedure reading limit.');
    }
  }
  if (item['min'] != null &&
      item['max'] != null &&
      (item['min'] as num) > (item['max'] as num)) {
    _invalid('Procedure reading limits are reversed.');
  }
}

void _requireEditable(Json draft) {
  if (draft.containsKey('publishedTemplateId')) {
    _invalid('This draft was published. Make an independent copy to edit it.');
  }
}

/// Copies a checked immutable publication into an independently identified draft.
/// Neither this draft nor its future publication can change the source version.
Json copiedProcedureDraft({
  required String draftId,
  required Json publication,
  required List<String> itemIds,
}) {
  // Reuse the exact published-template/hash validator without normalizing the
  // supplied publication and accidentally accepting altered source data.
  validateCatalog({
    'version': 1,
    'companyId': 'procedure-source-validation',
    'company': 'Procedure library',
    'coordinatorName': 'Procedure library',
    'equipment': <Json>[],
    'templates': [publication],
    'jobs': <Json>[],
  });
  _id(draftId, 'procedure draft');
  if (draftId == publication['id']) {
    _invalid('The copied draft needs an independent identity.');
  }
  final originalItems = _items(publication['items']);
  if (itemIds.length != originalItems.length ||
      itemIds.toSet().length != itemIds.length ||
      itemIds.any(originalItems.map((item) => item['id']).toSet().contains)) {
    _invalid('Give every copied step a new independent identity.');
  }
  final source = <String, dynamic>{
    'publicationId': publication['id'],
    'version': publication['version'],
    'hash': publication['hash'],
    'title': publication['title'],
  };
  final draft = <String, dynamic>{
    'id': draftId,
    'revision': 1,
    'title': publication['title'],
    'items': [
      for (var index = 0; index < originalItems.length; index++)
        {..._copy(originalItems[index]), 'id': itemIds[index]},
    ],
    'provenance': _provenance(source),
    'source': source,
  };
  validateProcedureDraft(draft);
  return _copy(draft);
}

/// Checks durable draft shape while retaining honest unfinished input.
/// Source attribution is checked for consistency; its content hash is verified
/// against the original publication when the copy is first created.
void validateProcedureDraft(Json draft) {
  _shape(draft, _draftKeys, {
    ..._draftKeys,
    'publishedTemplateId',
  }, 'procedure draft');
  _id(draft['id'], 'procedure draft');
  _text(draft['title'], 'procedure draft title', 200, empty: true);
  if (draft['revision'] is! int ||
      draft['revision'] < 1 ||
      draft['revision'] > _maxRevision) {
    _invalid('Invalid procedure draft revision.');
  }
  final source = _map(draft['source'], 'procedure source');
  _validateSource(source);
  if (draft['id'] == source['publicationId']) {
    _invalid('The copied draft needs an independent identity.');
  }
  final provenance = _map(draft['provenance'], 'procedure provenance');
  const provenanceKeys = {'kind', 'reference'};
  _shape(provenance, provenanceKeys, provenanceKeys, 'procedure provenance');
  _text(provenance['reference'], 'procedure reference', 2000);
  if (provenance['kind'] != 'local-reference' ||
      provenance['reference'] != _provenance(source)['reference']) {
    _invalid('The procedure source attribution cannot change.');
  }
  final items = _items(draft['items']);
  for (final item in items) {
    _validateItem(item);
  }
  if (items.map((item) => item['id']).toSet().length != items.length) {
    _invalid('Duplicate procedure step identity.');
  }
  if (draft.containsKey('publishedTemplateId')) {
    _id(draft['publishedTemplateId'], 'published checklist');
    if (draft['publishedTemplateId'] == source['publicationId']) {
      _invalid('The copied publication needs an independent identity.');
    }
  }
}

/// Returns the next detached draft revision, preserving its pinned attribution.
/// The persistence adapter must compare this draft's revision atomically first.
Json editedProcedureDraft(
  Json draft, {
  required String title,
  required List<Json> items,
}) {
  validateProcedureDraft(draft);
  _requireEditable(draft);
  if (draft['revision'] == _maxRevision) {
    _invalid('The procedure draft revision limit was reached.');
  }
  final next = <String, dynamic>{
    ..._copy(draft),
    'revision': (draft['revision'] as int) + 1,
    'title': title,
    'items': items,
  };
  validateProcedureDraft(next);
  return _copy(next);
}

/// Creates an independent v1 using the existing stricter publication contract.
/// Finalization and exact retry receipts remain the office adapter's authority.
Json publicationFromProcedureDraft(
  Json draft, {
  required String publicationId,
}) {
  validateProcedureDraft(draft);
  _requireEditable(draft);
  if (publicationId == draft['source']['publicationId']) {
    _invalid('The copied publication needs an independent identity.');
  }
  return makeTemplate(
    id: publicationId,
    title: draft['title'] as String,
    items: _items(draft['items']),
    provenance: _map(draft['provenance'], 'procedure provenance'),
  );
}
