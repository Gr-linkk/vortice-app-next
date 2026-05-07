import 'package:vortice_app/models/work_order.dart';

class MaintenanceWorkOrderDraft {
  static const assetIdParam = 'assetId';
  static const checklistTemplateIdParam = 'checklistTemplateId';
  static const titleParam = 'title';
  static const descriptionParam = 'description';
  static const jobTypeParam = 'jobType';
  static const serviceRequestIdParam = 'serviceRequestId';

  final String? assetId;
  final String? checklistTemplateId;
  final String? serviceRequestId;
  final String title;
  final String description;
  final WorkOrderJobType jobType;

  const MaintenanceWorkOrderDraft({
    this.assetId,
    this.checklistTemplateId,
    this.serviceRequestId,
    this.title = '',
    this.description = '',
    this.jobType = WorkOrderJobType.repair,
  });

  factory MaintenanceWorkOrderDraft.preventativeMaintenance({
    required String assetId,
    required double intervalHours,
    required double? currentHours,
    required double? nextDueHours,
    String? intervalLabel,
    String? checklistTemplateId,
    String? checklistTemplateName,
  }) {
    final title = intervalLabel ??
        checklistTemplateName ??
        '${intervalHours.toInt()}h Service';
    final description = StringBuffer(
        'Preventative maintenance generated from Maintenance Plan.');
    if (currentHours != null) {
      description
          .write(' Last known hours: ${currentHours.toStringAsFixed(0)}h.');
    }
    if (nextDueHours != null) {
      description
          .write(' Next service due: ${nextDueHours.toStringAsFixed(0)}h.');
    }

    return MaintenanceWorkOrderDraft(
      assetId: assetId,
      checklistTemplateId: checklistTemplateId,
      title: title,
      description: description.toString(),
      jobType: WorkOrderJobType.preventative,
    );
  }

  factory MaintenanceWorkOrderDraft.fromQueryParameters(
    Map<String, String> params,
  ) {
    final checklistTemplateId = params[checklistTemplateIdParam];
    final jobType =
        params[jobTypeParam] == WorkOrderJobType.preventative.dbValue ||
                checklistTemplateId != null
            ? WorkOrderJobType.preventative
            : WorkOrderJobType.repair;

    return MaintenanceWorkOrderDraft(
      assetId: params[assetIdParam],
      checklistTemplateId: checklistTemplateId,
      serviceRequestId: params[serviceRequestIdParam],
      title: params[titleParam] ?? '',
      description: params[descriptionParam] ?? '',
      jobType: jobType,
    );
  }

  Map<String, String> toQueryParameters() => <String, String>{
        if (assetId != null) assetIdParam: assetId!,
        if (title.isNotEmpty) titleParam: title,
        if (description.isNotEmpty) descriptionParam: description,
        if (checklistTemplateId != null)
          checklistTemplateIdParam: checklistTemplateId!,
        if (serviceRequestId != null) serviceRequestIdParam: serviceRequestId!,
        jobTypeParam: jobType.dbValue,
      };

  bool get isPreventative => jobType == WorkOrderJobType.preventative;
}
