import 'package:vortice_app/domain/work_report.dart';

export 'package:vortice_app/domain/work_report.dart' show WorkReportProgress;

// Presentation of shared work rules. Business decisions live in domain/.
extension WorkReportProgressLabels on WorkReportProgress {
  String? meterError(bool es, {bool french = false}) => meterValid
      ? null
      : french
      ? 'Saisissez un relevé valide, égal ou supérieur au relevé initial.'
      : es
      ? 'Introduce una lectura válida, igual o mayor que la inicial.'
      : 'Enter a valid reading at least as high as the starting meter.';
}

String? maintenanceItemRequirement(
  Map<String, dynamic> item,
  Map<String, dynamic> answers,
  List<String> evidence,
  bool es, {
  bool french = false,
}) => switch (workItemRequirement(item, answers, evidence)) {
  WorkItemRequirement.correction =>
    french
        ? 'Corrigez et vérifiez cette étape avant de terminer.'
        : es
        ? 'Corrige y verifica este paso antes de completar.'
        : 'Correct and verify this step before completing.',
  WorkItemRequirement.answer =>
    french
        ? 'Saisissez le résultat ou le relevé requis.'
        : es
        ? 'Completa el resultado o la lectura requerida.'
        : 'Enter the required result or reading.',
  WorkItemRequirement.photo =>
    french
        ? 'Ajoutez la photo requise pour cette étape.'
        : es
        ? 'Adjunta la foto requerida para este paso.'
        : 'Attach the required photo for this step.',
  null => null,
};

int maintenanceCompletedItems(
  List<Map<String, dynamic>> items,
  Map<String, dynamic> answers,
  List<String> evidence,
) => completedWorkItems(items, answers, evidence);
