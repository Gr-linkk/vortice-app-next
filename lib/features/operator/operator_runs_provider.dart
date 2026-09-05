import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/features/assets/client_team_asset_access.dart';

/// Represents an operator checklist run with its responses
class OperatorChecklistRun {
  final String id;
  final String assetId;
  final String? engineId;
  final String templateId;
  final String operatorId;
  final String runType;
  final double? tripHours;
  final double? fuelAdded;
  final String? notes;
  final DateTime? completedAt;
  final DateTime createdAt;
  final List<OperatorChecklistResponse> responses;

  const OperatorChecklistRun({
    required this.id,
    required this.assetId,
    this.engineId,
    required this.templateId,
    required this.operatorId,
    required this.runType,
    this.tripHours,
    this.fuelAdded,
    this.notes,
    this.completedAt,
    required this.createdAt,
    required this.responses,
  });

  factory OperatorChecklistRun.fromJson(Map<String, dynamic> json) {
    final responsesJson = json['operator_checklist_responses'] as List? ?? [];
    return OperatorChecklistRun(
      id: json['id'] as String,
      assetId: json['asset_id'] as String,
      engineId: json['engine_id'] as String?,
      templateId: json['template_id'] as String,
      operatorId: json['operator_id'] as String,
      runType: json['run_type'] as String,
      tripHours: (json['trip_hours'] as num?)?.toDouble(),
      fuelAdded: (json['fuel_added'] as num?)?.toDouble(),
      notes: json['notes'] as String?,
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      responses: responsesJson
          .map((r) =>
              OperatorChecklistResponse.fromJson(r as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Count of items that need attention
  int get flaggedCount =>
      responses.where((r) => r.result == 'needs_attention').length;

  /// Whether this run has any flagged items
  bool get hasFlaggedItems => flaggedCount > 0;
}

class OperatorChecklistResponse {
  final String id;
  final String runId;
  final String checklistItemId;
  final String result;
  final String? notes;
  final String? photoUrl;

  const OperatorChecklistResponse({
    required this.id,
    required this.runId,
    required this.checklistItemId,
    required this.result,
    this.notes,
    this.photoUrl,
  });

  factory OperatorChecklistResponse.fromJson(Map<String, dynamic> json) {
    return OperatorChecklistResponse(
      id: json['id'] as String,
      runId: json['run_id'] as String,
      checklistItemId: json['checklist_item_id'] as String,
      result: json['result'] as String,
      notes: json['notes'] as String?,
      photoUrl: json['photo_url'] as String?,
    );
  }
}

/// Represents a maintenance request/flag
class MaintenanceRequest {
  final String id;
  final String assetId;
  final String flaggedBy;
  final String description;
  final String? photoUrl;
  final String severity;
  final String status;
  final String? convertedToWorkOrderId;
  final DateTime? clientNotifiedAt;
  final DateTime? ownerNotifiedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const MaintenanceRequest({
    required this.id,
    required this.assetId,
    required this.flaggedBy,
    required this.description,
    this.photoUrl,
    required this.severity,
    required this.status,
    this.convertedToWorkOrderId,
    this.clientNotifiedAt,
    this.ownerNotifiedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory MaintenanceRequest.fromJson(Map<String, dynamic> json) {
    return MaintenanceRequest(
      id: json['id'] as String,
      assetId: json['asset_id'] as String,
      flaggedBy: json['flagged_by'] as String,
      description: json['description'] as String,
      photoUrl: json['photo_url'] as String?,
      severity: json['severity'] as String? ?? 'normal',
      status: json['status'] as String? ?? 'open',
      convertedToWorkOrderId: json['converted_to_work_order_id'] as String?,
      clientNotifiedAt: json['client_notified_at'] != null
          ? DateTime.parse(json['client_notified_at'] as String)
          : null,
      ownerNotifiedAt: json['owner_notified_at'] != null
          ? DateTime.parse(json['owner_notified_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  bool get isUrgent => severity == 'urgent';
  bool get isOpen => status != 'resolved' && status != 'dismissed';
}

/// Fetch operator checklist runs for a specific asset
final operatorRunsForAssetProvider =
    FutureProvider.family<List<OperatorChecklistRun>, String>(
        (ref, assetId) async {
  final data = await supabase
      .from(AppConstants.tOperatorChecklistRuns)
      .select('*, operator_checklist_responses(*)')
      .eq('asset_id', assetId)
      .order('created_at', ascending: false)
      .limit(20);

  return (data as List)
      .map((e) => OperatorChecklistRun.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// Fetch all maintenance requests for a specific asset
final maintenanceRequestsForAssetProvider =
    FutureProvider.family<List<MaintenanceRequest>, String>(
        (ref, assetId) async {
  final data = await supabase
      .from(AppConstants.tMaintenanceRequests)
      .select()
      .eq('asset_id', assetId)
      .order('created_at', ascending: false);

  return (data as List)
      .map((e) => MaintenanceRequest.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// Fetch all open maintenance requests (for client dashboard)
final openMaintenanceRequestsProvider =
    FutureProvider<List<MaintenanceRequest>>((ref) async {
  final data = await supabase
      .from(AppConstants.tMaintenanceRequests)
      .select()
      .inFilter('status', ['open', 'acknowledged', 'converted', 'in_progress', 'pending_review'])
      .order('created_at', ascending: false);

  return (data as List)
      .map((e) => MaintenanceRequest.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// Fetch open maintenance requests with asset name join (for client dashboard UI).
/// Defined here so the flag screen can invalidate it after submission.
final clientFlaggedIssuesProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final assets = await ref.watch(currentClientFleetAssetsProvider.future);
  final assetIds = assets.map((asset) => asset.id).toList();
  if (assetIds.isEmpty) return [];

  final data = await supabase
      .from(AppConstants.tMaintenanceRequests)
      .select('id, description, severity, status, created_at, assets(name, id)')
      .inFilter('status', ['open', 'acknowledged', 'converted', 'in_progress', 'pending_review'])
      .inFilter('asset_id', assetIds)
      .order('created_at', ascending: false)
      .limit(10);
  return List<Map<String, dynamic>>.from(data as List);
});

/// Fetch assets for the operator, scoped to their client org.
///
/// No org means no inherited fleet visibility. This intentionally avoids the old
/// all-assets fallback.
final operatorAssignedAssetsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final assets = await ref.watch(currentClientFleetAssetsProvider.future);
  return assets.map(clientTeamAssetRow).toList();
});
