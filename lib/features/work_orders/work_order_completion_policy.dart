import 'package:vortice_app/models/service_report.dart';
import 'package:vortice_app/models/work_order.dart';
import 'package:vortice_app/sync/sync_status.dart';

/// Work-order completion rules driven by product walkthrough backlog A005/A006.
class WorkOrderCompletionPolicy {
  const WorkOrderCompletionPolicy._();

  static bool canMarkCompleted({
    required WorkOrderStatus status,
    required bool hasSubmittedServiceReport,
  }) {
    if (status != WorkOrderStatus.inProgress) return false;
    return hasSubmittedServiceReport;
  }

  static bool shouldExplainMissingServiceReport({
    required WorkOrderStatus status,
    required bool hasSubmittedServiceReport,
  }) {
    if (status != WorkOrderStatus.inProgress) return false;
    return !hasSubmittedServiceReport;
  }

  static bool workOrderHasSubmittedServiceReport(
    Iterable<ServiceReport> reports,
  ) {
    return reports.any(isSubmittedServiceReport);
  }

  static bool isSubmittedServiceReport(ServiceReport report) {
    if (report.signedAt != null) return true;

    final hasBody = [
      report.complaint,
      report.cause,
      report.correction,
      report.collateral,
      report.comments,
    ].any((value) => value?.trim().isNotEmpty == true);

    return hasBody &&
        report.syncStatus != SyncStatusValues.pendingCreate &&
        report.syncStatus != SyncStatusValues.failed;
  }
}
