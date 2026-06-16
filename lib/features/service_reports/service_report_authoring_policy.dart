bool hasServiceReportAuthoringWorkOrder(String? workOrderId) =>
    workOrderId != null && workOrderId.trim().isNotEmpty;

bool canOpenServiceReportAuthoring({
  required bool canCreate,
  required String? workOrderId,
}) =>
    canCreate && hasServiceReportAuthoringWorkOrder(workOrderId);

String? serviceReportAuthoringRedirect({
  required String historyRoute,
  required String? workOrderId,
}) {
  if (hasServiceReportAuthoringWorkOrder(workOrderId)) return null;
  return historyRoute;
}
