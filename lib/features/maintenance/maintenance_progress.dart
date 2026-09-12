import 'package:vortice_app/features/checklists/checklist_answer_fields.dart';

/// Matches checked completion: a failure remains open until corrected, even if
/// a linked fault was requested. Standalone runs never enter this calculation.
String? maintenanceItemRequirement(
  Map<String, dynamic> item,
  Map<String, dynamic> answers,
  List<String> evidence,
  bool es,
) {
  final answer = answers[item['id']] as Map? ?? {};
  final result = answer['result'] as String?;
  if (result == 'fail') {
    return es
        ? 'Corrige y verifica este paso antes de completar.'
        : 'Correct and verify this step before completing.';
  }
  if (!checklistAnswerValid(
    Map<String, dynamic>.from(item['definition'] as Map? ?? {}),
    result,
    answer['note'] as String? ?? '',
  )) {
    return es
        ? 'Completa el resultado o la lectura requerida.'
        : 'Enter the required result or reading.';
  }
  if (item['requires_photo'] == true &&
      !evidence.contains(answer['photo_path'])) {
    return es
        ? 'Adjunta la foto requerida para este paso.'
        : 'Attach the required photo for this step.';
  }
  return null;
}

int maintenanceCompletedItems(
  List<Map<String, dynamic>> items,
  Map<String, dynamic> answers,
  List<String> evidence,
) => items
    .where(
      (item) =>
          maintenanceItemRequirement(item, answers, evidence, false) == null,
    )
    .length;
