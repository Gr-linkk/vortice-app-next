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

  const ServiceReportSubmitOutcome({
    required this.pendingReportId,
    required this.shouldResetForm,
    required this.shouldPop,
    required this.showPhotosPendingWarning,
  });
}

ServiceReportSubmitOutcome? resolveServiceReportSubmitOutcome({
  required String? reportId,
  required bool photosUploaded,
  required bool hadPhotos,
}) {
  if (reportId == null) return null;

  if (photosUploaded) {
    return const ServiceReportSubmitOutcome(
      pendingReportId: null,
      shouldResetForm: true,
      shouldPop: true,
      showPhotosPendingWarning: false,
    );
  }

  return ServiceReportSubmitOutcome(
    pendingReportId: reportId,
    shouldResetForm: false,
    shouldPop: false,
    showPhotosPendingWarning: hadPhotos,
  );
}
