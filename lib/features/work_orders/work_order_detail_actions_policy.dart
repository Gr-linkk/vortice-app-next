import 'package:vortice_app/models/work_order.dart';

class WorkOrderDetailActionsPolicy {
  const WorkOrderDetailActionsPolicy._();

  static bool showsActionsSection({
    required bool canManageStatus,
    required bool canOpenChecklist,
  }) =>
      canManageStatus || canOpenChecklist;

  static bool canUseChecklist({
    required bool isOwnerOrEmployee,
    required bool isAssignedContributor,
    required bool pmChecklistsAllowed,
  }) =>
      (isOwnerOrEmployee || isAssignedContributor) && pmChecklistsAllowed;

  static bool canOpenChecklist({
    required bool canUseChecklist,
    required String? checklistTemplateId,
    required WorkOrderStatus status,
  }) =>
      canUseChecklist &&
      checklistTemplateId != null &&
      status != WorkOrderStatus.closed &&
      status != WorkOrderStatus.invoiced;

  static bool canStartWorkOrder({
    required bool canManageStatus,
    required WorkOrderStatus status,
  }) =>
      canManageStatus &&
      (status == WorkOrderStatus.draft || status == WorkOrderStatus.assigned);

  static bool canCompleteWorkOrder({
    required bool canManageStatus,
    required WorkOrderStatus status,
  }) =>
      canManageStatus && status == WorkOrderStatus.inProgress;

  static bool canReopenWorkOrder({
    required bool canManageStatus,
    required WorkOrderStatus status,
  }) =>
      canManageStatus && status == WorkOrderStatus.closed;

  static bool canGenerateInvoice({
    required bool isOwner,
    required WorkOrderStatus status,
  }) =>
      isOwner &&
      (status == WorkOrderStatus.pendingReview ||
          status == WorkOrderStatus.closed);
}
