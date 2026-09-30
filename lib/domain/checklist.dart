/// Checklist value rules shared by authoring, execution and review.
/// No widget, storage or transport dependencies.
String checklistInputType(Map<String, dynamic> definition) =>
    definition['input_type'] as String? ?? 'check';

String checklistRecordedValue(Map<String, dynamic> definition, String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return '';
  final unit = checklistInputType(definition) == 'number'
      ? definition['unit'] as String?
      : null;
  return unit == null || unit.trim().isEmpty ? text : '$text ${unit.trim()}';
}

String? checklistValueResult(
  Map<String, dynamic> definition,
  String value, {
  String failure = 'action',
}) {
  if (value.trim().isEmpty) return null;
  if (checklistInputType(definition) != 'number') return 'pass';
  final number = double.tryParse(value.trim().replaceAll(',', '.'));
  if (number == null || !number.isFinite) return null;
  final min = (definition['min'] as num?)?.toDouble();
  final max = (definition['max'] as num?)?.toDouble();
  return (min != null && number < min) || (max != null && number > max)
      ? failure
      : 'pass';
}

bool checklistAnswerValid(
  Map<String, dynamic> definition,
  String? result,
  String value,
) {
  if (!const {
    'pass',
    'fail',
    'monitor',
    'alert',
    'action',
    'na',
    'n/a',
  }.contains(result)) {
    return false;
  }
  if (result == 'na' || result == 'n/a') return definition['allow_na'] != false;
  if (checklistInputType(definition) == 'check') return true;
  final expected = checklistValueResult(definition, value);
  return expected != null &&
      (expected != 'action' || result == 'action' || result == 'fail');
}
