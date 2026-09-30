import 'dart:convert';

import 'package:maintenance_rules/checklist.dart';
import 'model.dart';

/// The first company workflow records inspections. An honest finding may be
/// submitted and reviewed; acceptance never declares a repair complete, advances
/// maintenance, or returns equipment to service. These rules contain no runtime
/// authority: adapters must compare the entire context with the office catalog.
const maintenanceMeterUnits = {'hours', 'km', 'mi', 'none'};
const _itemTypes = {'check', 'number', 'text'};
const _provenanceKinds = {
  'company-authored',
  'local-reference',
  'manual-reference',
};
final _idPattern = RegExp(r'^[a-zA-Z0-9_-]{1,100}$');

Json _copy(Json value) => jsonDecode(jsonEncode(value)) as Json;

Never _invalid(String message) => throw StateError(message);

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
  if (value is! String || !_idPattern.hasMatch(value)) {
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

List<Json> _rows(dynamic value, String label, int limit) {
  if (value is! List || value.length > limit) _invalid('Invalid $label.');
  return value.map((row) => _map(row, label)).toList();
}

void _unique(List<Json> rows, String label) {
  if (rows.map((row) => row['id']).toSet().length != rows.length) {
    _invalid('Duplicate $label identity.');
  }
}

Json makeCatalog({
  required String id,
  required String name,
  required String coordinatorName,
}) {
  final catalog = <String, dynamic>{
    'version': 1,
    'companyId': id,
    'company': name.trim(),
    'coordinatorName': coordinatorName.trim(),
    'equipment': <Json>[],
    'templates': <Json>[],
    'jobs': <Json>[],
  };
  validateCatalog(catalog);
  return catalog;
}

Json makeEquipment({
  required String id,
  required String name,
  String serial = '',
  String meterUnit = 'hours',
}) {
  final equipment = <String, dynamic>{
    'id': id,
    'name': name.trim(),
    'serial': serial.trim(),
    'meterUnit': meterUnit,
  };
  _validateEquipment(equipment);
  return equipment;
}

Json makeTemplate({
  required String id,
  required String title,
  required List<Json> items,
  required Json provenance,
  int version = 1,
}) {
  final template = <String, dynamic>{
    'id': id,
    'title': title.trim(),
    'version': version,
    'provenance': _copy(provenance),
    'items': [
      for (final item in items)
        {
          ..._copy(item),
          'required': item['required'] ?? true,
          'allow_na': item['allow_na'] ?? false,
        },
    ],
  };
  template['hash'] = contentHash(template);
  _validateTemplate(template);
  return template;
}

Json makeJob({
  required String id,
  required String title,
  required Json equipment,
  required Json template,
}) {
  _validateEquipment(equipment);
  _validateTemplate(template);
  final job = <String, dynamic>{
    'id': id,
    'equipmentId': equipment['id'],
    'title': title.trim(),
    'equipmentSnapshot': _copy(equipment),
    'checklistSnapshot': _copy(template),
    'snapshotHash': contentHash(template),
    'meterUnit': equipment['meterUnit'],
    'meterRequired': equipment['meterUnit'] != 'none',
    'revision': 1,
  };
  _validateJob(job);
  return job;
}

void _validateEquipment(Json equipment) {
  const keys = {'id', 'name', 'serial', 'meterUnit'};
  _shape(equipment, keys, keys, 'equipment');
  _id(equipment['id'], 'equipment');
  _text(equipment['name'], 'equipment name', 200);
  _text(equipment['serial'], 'equipment serial', 200, empty: true);
  if (!maintenanceMeterUnits.contains(equipment['meterUnit'])) {
    _invalid('Unsupported equipment meter unit.');
  }
}

void _validateItem(Json item) {
  _shape(
    item,
    {'id', 'label', 'input_type'},
    {'id', 'label', 'input_type', 'unit', 'min', 'max', 'required', 'allow_na'},
    'checklist step',
  );
  _id(item['id'], 'checklist step');
  _text(item['label'], 'checklist step label', 1000);
  if (!_itemTypes.contains(item['input_type']) ||
      (item.containsKey('required') && item['required'] is! bool) ||
      (item.containsKey('allow_na') && item['allow_na'] is! bool)) {
    _invalid('Invalid checklist step definition.');
  }
  if (item['unit'] != null) {
    _text(item['unit'], 'reading unit', 40, empty: true);
  }
  for (final key in ['min', 'max']) {
    final limit = item[key];
    if (limit != null &&
        (item['input_type'] != 'number' ||
            limit is! num ||
            !limit.isFinite ||
            limit.abs() > 1e12)) {
      _invalid('Invalid checklist reading limit.');
    }
  }
  if (item['min'] != null &&
      item['max'] != null &&
      (item['min'] as num) > (item['max'] as num)) {
    _invalid('Checklist reading limits are reversed.');
  }
}

void _validateTemplate(Json template) {
  const keys = {'id', 'title', 'version', 'provenance', 'items', 'hash'};
  _shape(template, keys, keys, 'published checklist');
  _id(template['id'], 'published checklist');
  _text(template['title'], 'checklist title', 200);
  if (template['version'] is! int ||
      template['version'] < 1 ||
      template['version'] > 1000000) {
    _invalid('Invalid checklist publication version.');
  }
  final provenance = _map(template['provenance'], 'checklist provenance');
  _shape(provenance, {'kind'}, {'kind', 'reference'}, 'checklist provenance');
  if (!_provenanceKinds.contains(provenance['kind'])) {
    _invalid(
      'Checklist provenance must describe authorship or a local reference.',
    );
  }
  if (provenance['reference'] != null) {
    _text(provenance['reference'], 'checklist reference', 2000, empty: true);
  }
  if (provenance['kind'] != 'company-authored' &&
      (provenance['reference'] is! String ||
          (provenance['reference'] as String).trim().isEmpty)) {
    _invalid('Describe the local checklist reference.');
  }
  final items = _rows(template['items'], 'checklist steps', 200);
  if (items.isEmpty) _invalid('A published checklist needs at least one step.');
  for (final item in items) {
    _validateItem(item);
  }
  _unique(items, 'checklist step');
  final unhashed = {...template}..remove('hash');
  if (template['hash'] is! String ||
      !hashPattern.hasMatch(template['hash']) ||
      template['hash'] != contentHash(unhashed)) {
    _invalid('The published checklist failed its integrity check.');
  }
}

void _validateJob(Json job) {
  const keys = {
    'id',
    'equipmentId',
    'title',
    'equipmentSnapshot',
    'checklistSnapshot',
    'snapshotHash',
    'meterUnit',
    'meterRequired',
    'revision',
  };
  _shape(job, keys, keys, 'prepared work order');
  _id(job['id'], 'work order');
  _id(job['equipmentId'], 'work equipment');
  _text(job['title'], 'work order title', 200);
  final equipment = _map(job['equipmentSnapshot'], 'equipment snapshot');
  final snapshot = _map(job['checklistSnapshot'], 'checklist snapshot');
  _validateEquipment(equipment);
  _validateTemplate(snapshot);
  if (equipment['id'] != job['equipmentId'] ||
      job['meterUnit'] != equipment['meterUnit'] ||
      job['meterRequired'] != (job['meterUnit'] != 'none') ||
      job['revision'] is! int ||
      job['revision'] != 1 ||
      job['snapshotHash'] != contentHash(snapshot)) {
    _invalid('The prepared work context failed its integrity check.');
  }
}

/// A new authoritative company catalog owns its equipment. Frozen checklist
/// source references remain self-contained: their original publication does not
/// need to be present in the optional local publication list.
void validateCatalog(Json catalog) {
  const keys = {
    'version',
    'companyId',
    'company',
    'coordinatorName',
    'equipment',
    'templates',
    'jobs',
  };
  _shape(catalog, keys, keys, 'company catalog');
  if (catalog['version'] is! int || catalog['version'] != 1) {
    _invalid('Unsupported company catalog version.');
  }
  _id(catalog['companyId'], 'company');
  _text(catalog['company'], 'company name', 200);
  _text(catalog['coordinatorName'], 'coordinator name', 200);
  final equipment = _rows(catalog['equipment'], 'equipment', 10000);
  final templates = _rows(catalog['templates'], 'published checklists', 10000);
  final jobs = _rows(catalog['jobs'], 'prepared work orders', 10000);
  for (final row in equipment) {
    _validateEquipment(row);
  }
  for (final row in templates) {
    _validateTemplate(row);
  }
  for (final row in jobs) {
    _validateJob(row);
  }
  _unique(equipment, 'equipment');
  _unique(templates, 'publication');
  _unique(jobs, 'work order');
  final equipmentIds = equipment.map((row) => row['id']).toSet();
  if (jobs.any((job) => !equipmentIds.contains(job['equipmentId']))) {
    _invalid('A work order belongs to equipment outside this company catalog.');
  }
}

Json jobContext(Json catalog, String jobId) {
  validateCatalog(catalog);
  final matches = (catalog['jobs'] as List).where((job) => job['id'] == jobId);
  if (matches.length != 1) {
    _invalid('This work order is not in the company catalog.');
  }
  final job = _copy(_map(matches.single, 'prepared work order'));
  return {
    'companyId': catalog['companyId'],
    'company': catalog['company'],
    'coordinatorName': catalog['coordinatorName'],
    'jobId': job['id'],
    'equipmentId': job['equipmentId'],
    'equipment': _copy(job['equipmentSnapshot'] as Json),
    'job': job,
    'meterUnit': job['meterUnit'],
    'meterRequired': job['meterRequired'],
    'checklistSnapshot': _copy(job['checklistSnapshot'] as Json),
    'snapshotHash': job['snapshotHash'],
    'revision': job['revision'],
  };
}

void validateJobContext(Json context) {
  const keys = {
    'companyId',
    'company',
    'coordinatorName',
    'jobId',
    'equipmentId',
    'equipment',
    'job',
    'meterUnit',
    'meterRequired',
    'checklistSnapshot',
    'snapshotHash',
    'revision',
  };
  _shape(context, keys, keys, 'work context');
  _id(context['companyId'], 'company');
  _text(context['company'], 'company name', 200);
  _text(context['coordinatorName'], 'coordinator name', 200);
  final job = _map(context['job'], 'prepared work order');
  _validateJob(job);
  if (context['jobId'] != job['id'] ||
      context['equipmentId'] != job['equipmentId'] ||
      context['meterUnit'] != job['meterUnit'] ||
      context['meterRequired'] != job['meterRequired'] ||
      context['snapshotHash'] != job['snapshotHash'] ||
      context['revision'] != job['revision'] ||
      canonical(context['equipment']) != canonical(job['equipmentSnapshot']) ||
      canonical(context['checklistSnapshot']) !=
          canonical(job['checklistSnapshot'])) {
    _invalid('The work context differs from its frozen preparation.');
  }
}

List<Json> _contextItems(Json context) => _rows(
  (context['checklistSnapshot'] as Map)['items'],
  'checklist steps',
  200,
);

Json initialJobFields(Json context) {
  validateJobContext(context);
  return {
    '_jobId': context['jobId'],
    '_snapshotHash': context['snapshotHash'],
    for (final item in _contextItems(context)) 'answer:${item['id']}': null,
    'meter': null,
    'unit': context['meterUnit'],
    'notes': '',
    'photo': null,
  };
}

/// Structural draft validation permits an unanswered/partially typed response.
/// Submission applies the shared numeric/text rules in [incompleteJob]. Answers
/// are one atomic scalar so a merge cannot fabricate a result/value combination.
void validateJobDocument(Json alternatives, Json context) {
  final initial = initialJobFields(context);
  _shape(
    alternatives,
    initial.keys.toSet(),
    initial.keys.toSet(),
    'work document',
  );
  for (final entry in alternatives.entries) {
    if (entry.value is! List ||
        (entry.value as List).isEmpty ||
        (entry.value as List).length > 32) {
      _invalid('Invalid alternatives in ${entry.key}.');
    }
    if (entry.key == '_jobId' || entry.key == '_snapshotHash') {
      if ((entry.value as List).length != 1 ||
          (entry.value as List).single != initial[entry.key]) {
        _invalid('The work document belongs to a different prepared job.');
      }
      continue;
    }
    for (final value in entry.value as List) {
      if (entry.key.startsWith('answer:')) {
        if (value == null) continue;
        final answer = _map(value, 'checklist answer');
        _shape(
          answer,
          {'result', 'value'},
          {'result', 'value'},
          'checklist answer',
        );
        if (!{
          null,
          'pass',
          'action',
          'attention',
          'na',
        }.contains(answer['result'])) {
          _invalid('Unsupported checklist answer result.');
        }
        _text(answer['value'], 'checklist answer value', 4000, empty: true);
      } else {
        final valid = switch (entry.key) {
          'meter' =>
            value == null ||
                (value is num && value.isFinite && value >= 0 && value <= 1e12),
          'unit' => value == context['meterUnit'],
          'notes' => value is String && value.length <= 10000,
          'photo' =>
            value == null || (value is String && hashPattern.hasMatch(value)),
          _ => false,
        };
        if (!valid) _invalid('Invalid value for ${entry.key}.');
      }
    }
  }
}

String? incompleteJob(Json alternatives, Json context) {
  validateJobDocument(alternatives, context);
  if (conflicts(alternatives).isNotEmpty) {
    return 'Resolve conflicting answers before submitting.';
  }
  final values = valuesOf(alternatives);
  for (final item in _contextItems(context)) {
    final raw = values['answer:${item['id']}'];
    if (raw == null && item['required'] == false) continue;
    if (raw == null) return 'Answer ${item['label']}.';
    final answer = _map(raw, 'checklist answer');
    final result = answer['result'] == 'attention'
        ? 'action'
        : answer['result'];
    final definition = {...item, 'allow_na': item['allow_na'] == true};
    if (!checklistAnswerValid(
      definition,
      result as String?,
      answer['value'] as String,
    )) {
      return 'Record a valid answer for ${item['label']}.';
    }
    if (item['input_type'] == 'number' && result != 'na') {
      final number = double.tryParse(
        (answer['value'] as String).trim().replaceAll(',', '.'),
      );
      if (number == null || !number.isFinite || number.abs() > 1e12) {
        return 'Record a valid answer for ${item['label']}.';
      }
    }
  }
  if (context['meterRequired'] == true && values['meter'] == null) {
    return 'Record the meter reading; do not guess.';
  }
  if (context['meterRequired'] == false && values['meter'] != null) {
    return 'This equipment has no usage meter; leave the reading unknown.';
  }
  if ((values['notes'] as String).trim().isEmpty) {
    return 'Add work notes, including anything needing attention.';
  }
  if (values['photo'] == null) return 'Attach a photo of the inspection.';
  return null;
}
