const serviceReportMissingWorkOrderMessage =
    'Select a work order before submitting the report.';

String? validateServiceReportWorkOrderSelection(String? selectedWorkOrderId) {
  if (selectedWorkOrderId == null || selectedWorkOrderId.isEmpty) {
    return serviceReportMissingWorkOrderMessage;
  }
  return null;
}

class ServiceReportSubmitOutcome {
  final String? pendingReportId;
  final bool shouldResetForm;
  final bool shouldPop;
  final bool showPhotosPendingWarning;
  final bool showReportPendingWarning;

  const ServiceReportSubmitOutcome({
    required this.pendingReportId,
    required this.shouldResetForm,
    required this.shouldPop,
    required this.showPhotosPendingWarning,
    this.showReportPendingWarning = false,
  });
}

ServiceReportSubmitOutcome? resolveServiceReportSubmitOutcome({
  required String? reportId,
  required bool photosUploaded,
  required bool hadPhotos,
  bool reportSynced = true,
}) {
  if (reportId == null) return null;

  if (photosUploaded) {
    return ServiceReportSubmitOutcome(
      pendingReportId: null,
      shouldResetForm: true,
      shouldPop: true,
      showPhotosPendingWarning: false,
      showReportPendingWarning: !reportSynced,
    );
  }

  return ServiceReportSubmitOutcome(
    pendingReportId: reportId,
    shouldResetForm: false,
    shouldPop: false,
    showPhotosPendingWarning: hadPhotos,
  );
}
