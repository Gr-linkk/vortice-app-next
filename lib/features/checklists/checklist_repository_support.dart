import 'package:vortice_app/models/checklist_item.dart';
import 'package:vortice_app/models/checklist_response.dart';
import 'package:vortice_app/sync/sync_status.dart';

bool isAllowedChecklistItemDescription(String descriptionEn) {
  final text = descriptionEn.toLowerCase();
  if (text.contains('client sign')) return false;
  if (text.contains('customer sign')) return false;
  if (text.contains('sign-off')) return false;
  if (text.contains('sign off')) return false;
  if (text.contains('signature')) return false;
  return true;
}

bool isAllowedChecklistItem(ChecklistItem item) =>
    isAllowedChecklistItemDescription(item.descriptionEn);

bool shouldPreserveLocalChecklistResponse(ChecklistResponse response) =>
    response.syncStatus != SyncStatusValues.synced;

List<ChecklistResponse> mergeResponsesPreferUnsynced({
  required List<ChecklistResponse> remoteResponses,
  required List<ChecklistResponse> localResponses,
}) {
  final byItem = <String, ChecklistResponse>{
    for (final response in remoteResponses) response.checklistItemId: response,
  };

  for (final response in localResponses) {
    if (shouldPreserveLocalChecklistResponse(response)) {
      byItem[response.checklistItemId] = response;
    }
  }

  return byItem.values.toList();
}

Iterable<ChecklistResponse> remoteChecklistResponsesSafeToUpsert({
  required List<ChecklistResponse> remoteResponses,
  required Map<String, ChecklistResponse> localUnsyncedByItem,
}) =>
    remoteResponses.where(
      (response) => !localUnsyncedByItem.containsKey(response.checklistItemId),
    );

String pendingChecklistSyncStatus({required bool hasExisting}) =>
    hasExisting ? SyncStatusValues.pendingUpdate : SyncStatusValues.pendingCreate;

ChecklistResponse buildChecklistResponse({
  required String id,
  required String workOrderId,
  required String checklistItemId,
  required String completedBy,
  required String status,
  required DateTime completedAt,
  DateTime? createdAt,
  DateTime? updatedAt,
  String? notes,
  String? photoUrl,
  String syncStatus = SyncStatusValues.synced,
  DateTime? lastSyncedAt,
  String? lastError,
}) =>
    ChecklistResponse(
      id: id,
      workOrderId: workOrderId,
      checklistItemId: checklistItemId,
      completed: status == 'pass',
      notes: notes?.isNotEmpty == true ? notes : null,
      photoUrl: photoUrl,
      responseStatus: status,
      completedBy: completedBy,
      completedAt: completedAt,
      createdAt: createdAt,
      syncStatus: syncStatus,
      updatedAt: updatedAt,
      lastSyncedAt: lastSyncedAt,
      lastError: lastError,
    );

Map<String, dynamic> checklistResponseToRemoteRow(ChecklistResponse response) =>
    {
      'id': response.id,
      'work_order_id': response.workOrderId,
      'checklist_item_id': response.checklistItemId,
      'completed': response.completed,
      'response_status': response.responseStatus,
      'completed_by': response.completedBy,
      'completed_at': response.completedAt?.toIso8601String(),
      if (response.notes?.isNotEmpty == true) 'notes': response.notes,
      if (response.photoUrl != null) 'photo_url': response.photoUrl,
    };
