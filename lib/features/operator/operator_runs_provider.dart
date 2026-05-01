import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
// AppConstants has tClientOrgs, tWorkOrders, tWorkOrderAssignments, tProfiles

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
          .map((r) => OperatorChecklistResponse.fromJson(r as Map<String, dynamic>))
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
  bool get isOpen => status == 'open';
}

/// Fetch operator checklist runs for a specific asset
final operatorRunsForAssetProvider =
    FutureProvider.family<List<OperatorChecklistRun>, String>((ref, assetId) async {
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
    FutureProvider.family<List<MaintenanceRequest>, String>((ref, assetId) async {
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
      .eq('status', 'open')
      .order('created_at', ascending: false);

  return (data as List)
      .map((e) => MaintenanceRequest.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// Fetch open maintenance requests with asset name join (for client dashboard UI).
/// Defined here so the flag screen can invalidate it after submission.
final clientFlaggedIssuesProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return [];

  // Scope to the current client's own assets via client_id
  final data = await supabase
      .from(AppConstants.tMaintenanceRequests)
      .select('id, description, severity, status, created_at, assets(name, id)')
      .eq('status', 'open')
      .eq('client_id', userId)
      .order('created_at', ascending: false)
      .limit(10);
  return List<Map<String, dynamic>>.from(data as List);
});

/// Fetch assets for the operator, scoped to their org if applicable.
/// - If the operator has an org_id, returns assets belonging to the org's owner.
/// - Otherwise, returns all assets (legacy operator role fallback).
final operatorAssignedAssetsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final userId = supabase.auth.currentUser?.id;

  if (userId != null) {
    // Try to get the operator's org_id from their profile
    final profileRow = await supabase
        .from(AppConstants.tProfiles)
        .select('org_id, role')
        .eq('id', userId)
        .maybeSingle();

    final orgId = profileRow?['org_id'] as String?;
    if (orgId != null) {
      // Scoped to org: find the org's owner and return their assets
      final orgRow = await supabase
          .from(AppConstants.tClientOrgs)
          .select('owner_profile_id')
          .eq('id', orgId)
          .maybeSingle();

      final ownerId = orgRow?['owner_profile_id'] as String?;
      if (ownerId != null) {
        final data = await supabase
            .from(AppConstants.tAssets)
            .select('*, profiles(full_name)')
            .eq('client_id', ownerId)
            .order('name');
        return List<Map<String, dynamic>>.from(data as List);
      }
    }

    // Fallback: check work_order_assignments for legacy operator role
    final assignments = await supabase
        .from(AppConstants.tWorkOrderAssignments)
        .select('work_order_id')
        .eq('profile_id', userId);

    final woIds = (assignments as List)
        .map((e) => e['work_order_id'] as String)
        .toSet()
        .toList();

    if (woIds.isNotEmpty) {
      // Get asset IDs from those work orders
      final wos = await supabase
          .from(AppConstants.tWorkOrders)
          .select('asset_id')
          .inFilter('id', woIds);

      final assetIds = (wos as List)
          .map((e) => e['asset_id'] as String)
          .toSet()
          .toList();

      if (assetIds.isNotEmpty) {
        final data = await supabase
            .from(AppConstants.tAssets)
            .select('*, profiles(full_name)')
            .inFilter('id', assetIds)
            .order('name');
        return List<Map<String, dynamic>>.from(data as List);
      }
    }
  }

  // Legacy fallback: return all assets
  final data = await supabase
      .from(AppConstants.tAssets)
      .select('*, profiles(full_name)')
      .order('name');
  return List<Map<String, dynamic>>.from(data as List);
});
