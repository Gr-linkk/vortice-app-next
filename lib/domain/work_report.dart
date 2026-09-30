import 'checklist.dart';

/// Readiness of a maintenance report, independent of where it is saved.
/// Approval, inspection certificates and billing have their own authority.
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
  bool get meterValid {
    if (!meterRequired && meter.trim().isEmpty) return true;
    final reading = double.tryParse(meter.trim());
    return reading != null &&
        reading.isFinite &&
        reading >= startingMeter &&
        reading >= 0 &&
        reading < 1000000000;
  }

  bool get complete =>
      !diagnosisMissing &&
      !repairMissing &&
      meterValid &&
      completedWorkItems(items, answers, evidence) == items.length;
}

enum WorkItemRequirement { correction, answer, photo }

/// Recording a finding does not correct a failed maintenance step. A required
/// photo must be the step's linked evidence, not an unrelated report attachment.
WorkItemRequirement? workItemRequirement(
  Map<String, dynamic> item,
  Map<String, dynamic> answers,
  List<String> evidence,
) {
  final answer = answers[item['id']] as Map? ?? {};
  final result = answer['result'] as String?;
  if (result == 'fail') return WorkItemRequirement.correction;
  if (!checklistAnswerValid(
    Map<String, dynamic>.from(item['definition'] as Map? ?? {}),
    result,
    answer['note'] as String? ?? '',
  )) {
    return WorkItemRequirement.answer;
  }
  if (item['requires_photo'] == true &&
      !evidence.contains(answer['photo_path'])) {
    return WorkItemRequirement.photo;
  }
  return null;
}

int completedWorkItems(
  List<Map<String, dynamic>> items,
  Map<String, dynamic> answers,
  List<String> evidence,
) => items
    .where((item) => workItemRequirement(item, answers, evidence) == null)
    .length;
