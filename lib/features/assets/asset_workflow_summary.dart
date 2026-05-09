import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/features/assets/asset_workflow_policy.dart';
import 'package:vortice_app/features/checklists/saved_checklists_provider.dart';
import 'package:vortice_app/features/service_intervals/service_interval_provider.dart';
import 'package:vortice_app/features/service_requests/service_request_provider.dart';
import 'package:vortice_app/models/profile.dart';
import 'package:vortice_app/models/saved_checklist.dart';
import 'package:vortice_app/models/service_request.dart';

final assetWorkflowSummaryProvider = FutureProvider.family
    .autoDispose<AssetWorkflowSummary, ({String assetId, UserRole? role})>(
        (ref, args) async {
  final role = args.role;
  final assetId = args.assetId;

  final canSeeMaintenanceChecklist = _canSeeMaintenanceChecklistSummary(role);
  final canSeeOperationsChecklist =
      AssetWorkflowPolicy.canSeeChecklistHistory(role);

  final latestMaintenance = canSeeMaintenanceChecklist
      ? latestChecklistSummary(
          await ref.watch(
            savedChecklistsForAssetProvider(
              (assetId: assetId, type: SavedChecklistType.maintenance),
            ).future,
          ),
        )
      : null;

  final latestOperations = canSeeOperationsChecklist
      ? latestChecklistSummary(
          await ref.watch(
            savedChecklistsForAssetProvider(
              (assetId: assetId, type: SavedChecklistType.operations),
            ).future,
          ),
        )
      : null;

  final pmSummary = AssetWorkflowPolicy.canSeeMaintenancePlan(role)
      ? duePmSummary(
          await ref.watch(serviceIntervalSummariesProvider(assetId).future),
        )
      : const AssetPmDueSummary.hidden();

  final serviceRequestCount = _canSeeStaffServiceRequests(role)
      ? countNewServiceRequestsForAsset(
          await ref.watch(staffServiceRequestsProvider.future),
          assetId,
        )
      : null;

  return AssetWorkflowSummary(
    canSeeMaintenanceChecklist: canSeeMaintenanceChecklist,
    canSeeOperationsChecklist: canSeeOperationsChecklist,
    latestMaintenanceChecklist: latestMaintenance,
    latestOperationsChecklist: latestOperations,
    pmDueSummary: pmSummary,
    openServiceRequestCount: serviceRequestCount,
  );
});

class AssetWorkflowSummary {
  const AssetWorkflowSummary({
    required this.canSeeMaintenanceChecklist,
    required this.canSeeOperationsChecklist,
    required this.latestMaintenanceChecklist,
    required this.latestOperationsChecklist,
    required this.pmDueSummary,
    required this.openServiceRequestCount,
  });

  final bool canSeeMaintenanceChecklist;
  final bool canSeeOperationsChecklist;
  final AssetChecklistSummary? latestMaintenanceChecklist;
  final AssetChecklistSummary? latestOperationsChecklist;
  final AssetPmDueSummary pmDueSummary;
  final int? openServiceRequestCount;

  bool get hasVisibleActivity =>
      latestMaintenanceChecklist != null ||
      latestOperationsChecklist != null ||
      pmDueSummary.visible ||
      openServiceRequestCount != null;
}

class AssetChecklistSummary {
  const AssetChecklistSummary({
    required this.name,
    required this.submittedAt,
  });

  final String name;
  final DateTime submittedAt;
}

class AssetPmDueSummary {
  const AssetPmDueSummary({
    required this.visible,
    required this.dueOrOverdueCount,
    required this.labels,
  });

  const AssetPmDueSummary.hidden()
      : visible = false,
        dueOrOverdueCount = 0,
        labels = const [];

  final bool visible;
  final int dueOrOverdueCount;
  final List<String> labels;
}

AssetChecklistSummary? latestChecklistSummary(List<SavedChecklist> rows) {
  if (rows.isEmpty) return null;
  final latest = rows.reduce(
    (a, b) => a.submittedAt.isAfter(b.submittedAt) ? a : b,
  );
  return AssetChecklistSummary(
    name: latest.templateName,
    submittedAt: latest.submittedAt,
  );
}

AssetPmDueSummary duePmSummary(List<ServiceIntervalSummary> summaries) {
  final due = summaries.where(isDueOrOverduePmInterval).toList();
  return AssetPmDueSummary(
    visible: true,
    dueOrOverdueCount: due.length,
    labels: due
        .map((summary) => summary.interval.label ?? _fallbackPmLabel(summary))
        .toList(),
  );
}

bool isDueOrOverduePmInterval(ServiceIntervalSummary summary) {
  final remaining = summary.hoursRemaining;
  return remaining != null && remaining <= 0;
}

int countNewServiceRequestsForAsset(
  List<ServiceRequest> requests,
  String assetId,
) {
  return requests
      .where(
        (request) =>
            request.assetId == assetId &&
            request.status == ServiceRequestStatus.newRequest,
      )
      .length;
}

String _fallbackPmLabel(ServiceIntervalSummary summary) {
  return '${summary.interval.intervalHours.toInt()}h Service';
}

bool _canSeeMaintenanceChecklistSummary(UserRole? role) {
  return role == UserRole.owner ||
      role == UserRole.employee ||
      role == UserRole.client ||
      role == UserRole.clientAdmin ||
      role == UserRole.clientMechanic;
}

bool _canSeeStaffServiceRequests(UserRole? role) {
  return role == UserRole.owner || role == UserRole.employee;
}
