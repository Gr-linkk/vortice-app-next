import 'package:vortice_app/features/maintenance/maintenance_models.dart';
import 'package:vortice_app/models/service_report.dart';

typedef ServiceReportScope = ({String? assetId, String? workOrderId});

/// A report stays in its original workflow and retains that workflow's access.
class ServiceReportEntry {
  const ServiceReportEntry.legacy(ServiceReport report)
    : legacy = report,
      maintenance = null;
  const ServiceReportEntry.maintenance(MaintenanceJob job)
    : maintenance = job,
      legacy = null;

  final ServiceReport? legacy;
  final MaintenanceJob? maintenance;

  String get key => legacy?.id ?? 'maintenance:${maintenance!.id}';
  DateTime? get date {
    if (legacy != null) return legacy!.createdAt;
    final job = maintenance!;
    DateTime? latest;
    for (final event in maintenanceRows(job.data['events'])) {
      if (!{'save_report', 'submit', 'approve'}.contains(event['kind'])) {
        continue;
      }
      final date = DateTime.tryParse(event['created_at']?.toString() ?? '');
      if (date != null && (latest == null || date.isAfter(latest))) {
        latest = date;
      }
    }
    return latest ??
        DateTime.tryParse(job.data['created_at']?.toString() ?? '');
  }

  String route(String prefix) => maintenance != null
      ? '/maintenance/jobs/${maintenance!.id}'
      : '$prefix/service-reports/${legacy!.id}';
}

List<ServiceReportEntry> combineServiceReports(
  List<ServiceReport> legacy,
  List<MaintenanceJob> maintenance,
) {
  final managedIds = maintenance.map((job) => job.id).toSet();
  final entries = [
    for (final report in legacy)
      if (!managedIds.contains(report.workOrderId))
        ServiceReportEntry.legacy(report),
    for (final job in maintenance)
      if (job.report.isNotEmpty) ServiceReportEntry.maintenance(job),
  ];
  final epoch = DateTime.fromMillisecondsSinceEpoch(0);
  entries.sort((a, b) {
    final dates = (b.date ?? epoch).compareTo(a.date ?? epoch);
    return dates == 0 ? a.key.compareTo(b.key) : dates;
  });
  return entries;
}
