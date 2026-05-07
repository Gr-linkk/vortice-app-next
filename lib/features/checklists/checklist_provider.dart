import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/features/checklists/checklist_repository.dart';
import 'package:vortice_app/features/checklists/work_order_checklist_snapshot_repository.dart';
import 'package:vortice_app/models/checklist_item.dart';
import 'package:vortice_app/models/checklist_response.dart';
import 'package:vortice_app/models/checklist_template.dart';

final workOrderChecklistSnapshotProvider =
    FutureProvider.family<WorkOrderChecklistSnapshot?, String>(
        (ref, workOrderId) async {
  final snapshot = await workOrderChecklistSnapshotRepository
      .tryFetchByWorkOrderId(workOrderId);
  if (snapshot != null) {
    await ref.read(checklistRepositoryProvider).cacheSnapshot(snapshot);
  }
  return snapshot;
});

final checklistTemplatesProvider =
    FutureProvider<List<ChecklistTemplate>>((ref) async {
  return ref.watch(checklistRepositoryProvider).listTemplates();
});

final checklistItemsProvider =
    FutureProvider.family<List<ChecklistItem>, String>((ref, templateId) async {
  return ref
      .watch(checklistRepositoryProvider)
      .listItemsForTemplate(templateId);
});

final checklistResponsesProvider =
    FutureProvider.family<List<ChecklistResponse>, String>(
        (ref, workOrderId) async {
  return ref
      .watch(checklistRepositoryProvider)
      .listResponsesForWorkOrder(workOrderId);
});

final checklistResponseSyncStatusByItemProvider =
    Provider.family<AsyncValue<Map<String, String>>, String>(
        (ref, workOrderId) {
  return ref.watch(checklistResponsesProvider(workOrderId)).whenData(
        (responses) => {
          for (final response in responses)
            response.checklistItemId: response.syncStatus,
        },
      );
});

/// Returns true if any checklist responses have been submitted for a WO.
final checklistHasResponsesProvider =
    FutureProvider.family<bool, String>((ref, workOrderId) async {
  return ref
      .watch(checklistRepositoryProvider)
      .hasResponsesForWorkOrder(workOrderId);
});

class ChecklistController extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;
  ChecklistController(this._ref) : super(const AsyncData(null));

  Future<void> submitResponse({
    required String workOrderId,
    required String checklistItemId,
    required String completedBy,
    required bool completed,
    String? notes,
    String? photoUrl,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await supabase.from(AppConstants.tChecklistResponses).insert({
        'work_order_id': workOrderId,
        'checklist_item_id': checklistItemId,
        'completed': completed,
        'completed_by': completedBy,
        'completed_at': completed ? DateTime.now().toIso8601String() : null,
        'notes': notes,
        'photo_url': photoUrl,
      });
      _ref.invalidate(checklistResponsesProvider(workOrderId));
    });
  }

  Future<void> submitBatch({
    required String workOrderId,
    required String completedBy,
    required Map<String, String?> responses,
    Map<String, String>? notes,
    Map<String, String?>? photoUrls,
    String? holdForSyncReason,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      try {
        await _ref.read(checklistRepositoryProvider).submitBatchResponses(
              workOrderId: workOrderId,
              completedBy: completedBy,
              responses: responses,
              notes: notes,
              photoUrls: photoUrls,
              holdForSyncReason: holdForSyncReason,
            );
      } finally {
        _ref.invalidate(checklistResponsesProvider(workOrderId));
        _ref.invalidate(checklistHasResponsesProvider(workOrderId));
      }
    });
  }
}

final checklistControllerProvider =
    StateNotifierProvider<ChecklistController, AsyncValue<void>>((ref) {
  return ChecklistController(ref);
});
