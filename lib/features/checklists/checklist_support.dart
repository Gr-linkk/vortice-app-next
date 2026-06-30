import 'package:vortice_app/features/checklists/checklist_attachment_support.dart';
import 'package:vortice_app/models/checklist_template.dart';
import 'package:vortice_app/sync/sync_status.dart';

String checklistRunKey({String? workOrderId, String? assetId}) =>
    workOrderId ?? 'asset_$assetId';

String checklistDraftKey(String runKey) => 'checklist_draft_$runKey';

String checklistPhotoCacheKey(String runKey) => 'checklist_photo_cache_$runKey';

bool requiresAttentionDetail(
  Map<String, String?> responses,
  Map<String, String> notes,
  ChecklistItemPhotoLists photos,
  ChecklistItemPhotoUrlLists photoUrls,
) {
  for (final entry in responses.entries) {
    final status = entry.value;
    if (status != 'monitor' && status != 'alert' && status != 'action') {
      continue;
    }
    final hasNote = notes[entry.key]?.trim().isNotEmpty == true;
    final hasPhoto = checklistItemHasPhotoEvidence(
      photos: photos,
      photoUrls: photoUrls,
      itemId: entry.key,
    );
    if (!hasNote && !hasPhoto) return true;
  }
  return false;
}

String formatChecklistDateTime(DateTime value) {
  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}

int compareTemplatesByServiceHours(ChecklistTemplate a, ChecklistTemplate b) {
  final hoursCompare = (a.intervalHours ?? 1 << 30).compareTo(
    b.intervalHours ?? 1 << 30,
  );
  if (hoursCompare != 0) return hoursCompare;
  return a.name.compareTo(b.name);
}

bool isVisibleChecklistSyncStatus(String status) =>
    status != SyncStatusValues.synced;

String? syncStatusChipLabel(String? status) {
  switch (status) {
    case SyncStatusValues.pendingCreate:
    case SyncStatusValues.pendingUpdate:
    case SyncStatusValues.pendingDelete:
    case SyncStatusValues.syncing:
      return 'Pending sync';
    case SyncStatusValues.failed:
      return 'Sync failed';
    case SyncStatusValues.conflict:
      return 'Conflict';
    default:
      return null;
  }
}

String compactChecklistSyncError(String error) {
  final normalized = error.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.isEmpty) return 'Sync failed. Reconnect and retry.';

  if (normalized.contains('row-level security') ||
      normalized.contains('42501') ||
      normalized.contains('Forbidden')) {
    return 'Sync blocked by server permissions. Retry after access is fixed.';
  }

  if (normalized.contains('TimeoutException') ||
      normalized.toLowerCase().contains('timeout')) {
    return 'Sync timed out. Check connection and retry.';
  }

  if (normalized.length <= 120) return normalized;
  return '${normalized.substring(0, 117)}...';
}

String checklistSyncBannerMessage({
  required bool hasConflict,
  required String? lastError,
}) {
  if (hasConflict) return 'Checklist has sync conflicts.';
  if (lastError?.trim().isNotEmpty == true) {
    return compactChecklistSyncError(lastError!);
  }
  return 'Saved locally. Sync pending.';
}

Map<String, dynamic> encodeChecklistDraft({
  required String? templateId,
  required Map<String, String?> responses,
  required Map<String, String> notes,
  required Map<String, String?> photoUrls,
  required DateTime completedAt,
  required double? currentHours,
  required String? generalNotes,
  required ChecklistItemPhotoLists photos,
}) {
  return {
    'templateId': templateId,
    'responses': responses,
    'notes': notes,
    'photoUrls': legacyPhotoUrlMapFromLists(
      photoUrlListsFromLegacyMap(photoUrls),
    ),
    'completedAt': completedAt.toIso8601String(),
    'currentHours': currentHours,
    'generalNotes': generalNotes,
    'photos': encodePhotoListsCache(photos),
  };
}
