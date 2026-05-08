import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/features/checklists/saved_checklists_repository.dart';
import 'package:vortice_app/models/checklist_item.dart';
import 'package:vortice_app/models/checklist_template.dart';

final savedChecklistHistoryWriterProvider =
    Provider<SavedChecklistHistoryWriter>(
  (ref) => SavedChecklistHistoryWriter(
    ref.watch(savedChecklistsRepositoryProvider),
  ),
);

class SavedChecklistHistoryWriter {
  const SavedChecklistHistoryWriter(this._repository);

  final SavedChecklistsRepository _repository;

  Future<void> recordMaintenanceWorkOrderHistory({
    required String assetId,
    required String clientId,
    required String workOrderId,
    required ChecklistTemplate template,
    required List<ChecklistItem> items,
    required Map<String, String?> responses,
    required Map<String, String> notes,
    required Map<String, String?> photoUrls,
    required String completedBy,
    required String? submittedByRole,
    required DateTime submittedAt,
    required double? currentHours,
    required String? generalNotes,
  }) {
    return _repository.createSavedChecklist(
      assetId: assetId,
      clientId: clientId,
      template: template,
      items: items,
      responses: responses,
      notes: notes,
      photoUrls: photoUrls,
      sourceType: 'work_order',
      checklistType: 'maintenance',
      completedBy: completedBy,
      submittedByRole: submittedByRole,
      submittedAt: submittedAt,
      currentHours: currentHours,
      generalNotes: generalNotes,
      workOrderId: workOrderId,
      extraHeader: {
        'work_order_id': workOrderId,
      },
    );
  }

  Future<void> recordOperationsRunHistory({
    required String assetId,
    required String clientId,
    required String runId,
    required String runType,
    required ChecklistTemplate template,
    required List<ChecklistItem> items,
    required Map<String, String?> responses,
    required Map<String, String> notes,
    required String completedBy,
    required String? submittedByRole,
    required DateTime submittedAt,
    required double? currentHours,
    required String? generalNotes,
  }) {
    return _repository.createSavedChecklist(
      assetId: assetId,
      clientId: clientId,
      template: template,
      items: items,
      responses: responses,
      notes: notes,
      photoUrls: const {},
      sourceType: 'operator',
      checklistType: 'operations',
      completedBy: completedBy,
      submittedByRole: submittedByRole,
      submittedAt: submittedAt,
      currentHours: currentHours,
      generalNotes: generalNotes,
      extraHeader: {
        'run_id': runId,
        'run_type': runType,
      },
    );
  }
}
