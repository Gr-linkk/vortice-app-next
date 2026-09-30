import '../model.dart';

Json jsonMap(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

String equipmentName(Object? equipment) => equipment is Map
    ? (equipment['name'] ?? 'Equipment').toString()
    : (equipment ?? 'Equipment').toString();

String jobTitle(Object? job) => job is Map
    ? (job['title'] ?? 'Equipment inspection').toString()
    : (job ?? 'Equipment inspection').toString();

List<Json> inspectionItems(Json context) =>
    (jsonMap(context['checklistSnapshot'])['items'] as List? ?? [])
        .map(jsonMap)
        .toList();

String resultLabel(Object? result) => switch (result) {
  'pass' => 'Pass',
  'action' || 'attention' => 'Needs action',
  'na' => 'Not applicable',
  _ => 'Not answered',
};

String stepDefinition(Json item) {
  final type = item['input_type'] ?? 'check';
  final unit = (item['unit'] ?? '').toString();
  final parts = <String>[
    type == 'number'
        ? 'Reading${unit.isEmpty ? '' : ' ($unit)'}'
        : type == 'text'
        ? 'Written response'
        : 'Inspection check',
    item['required'] == false ? 'Optional' : 'Required',
  ];
  if (item['min'] != null && item['max'] != null) {
    parts.add(
      'Expected ${item['min']}–${item['max']}${unit.isEmpty ? '' : ' $unit'}',
    );
  } else if (item['min'] != null) {
    parts.add('Minimum ${item['min']}${unit.isEmpty ? '' : ' $unit'}');
  } else if (item['max'] != null) {
    parts.add('Maximum ${item['max']}${unit.isEmpty ? '' : ' $unit'}');
  }
  if (item['allow_na'] == true) parts.add('Not applicable allowed');
  return parts.join(' · ');
}

String meterUnitLabel(Object? unit) => switch (unit) {
  'km' => 'km',
  'mi' => 'miles',
  'none' => 'No meter',
  _ => 'hours',
};

String answerSummary(Object? answer, Json item) {
  final value = jsonMap(answer);
  final response = (value['value'] ?? '').toString();
  final unit = (item['unit'] ?? '').toString();
  return '${resultLabel(value['result'])}'
      '${response.isEmpty ? '' : ' · $response${unit.isEmpty ? '' : ' $unit'}'}';
}
