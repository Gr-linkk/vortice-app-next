import 'package:vortice_app/features/checklists/checklist_answer_fields.dart';

/// Common client-side readiness for internal and organization-provider reports.
/// Inspection certificates and server authorization remain in their own paths.
class WorkReportProgress {
  const WorkReportProgress({
    required this.diagnosis,
    required this.repair,
    required this.items,
    required this.answers,
    required this.evidence,
    required this.meter,
    required this.meterRequired,
    this.startingMeter = 0,
  });
  final String diagnosis, repair, meter;
  final List<Map<String, dynamic>> items;
  final Map<String, dynamic> answers;
  final List<String> evidence;
  final bool meterRequired;
  final num startingMeter;
  bool get diagnosisMissing => diagnosis.trim().length < 3;
  bool get repairMissing => repair.trim().length < 3;
  String? meterError(bool es) {
    if (!meterRequired && meter.trim().isEmpty) return null;
    final reading = double.tryParse(meter.trim());
    if (reading == null ||
        !reading.isFinite ||
        reading < startingMeter ||
        reading < 0 ||
        reading >= 1000000000) {
      return es
          ? 'Introduce una lectura válida, igual o mayor que la inicial.'
          : 'Enter a valid reading at least as high as the starting meter.';
    }
    return null;
  }

  bool get complete =>
      !diagnosisMissing &&
      !repairMissing &&
      meterError(false) == null &&
      items.every(
        (item) =>
            maintenanceItemRequirement(item, answers, evidence, false) == null,
      );
}

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
