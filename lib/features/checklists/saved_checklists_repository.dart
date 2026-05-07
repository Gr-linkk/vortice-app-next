import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/models/checklist_item.dart';
import 'package:vortice_app/models/checklist_template.dart';
import 'package:vortice_app/models/saved_checklist.dart';

final savedChecklistsRepositoryProvider = Provider<SavedChecklistsRepository>(
  (ref) => SavedChecklistsRepository(),
);

class SavedChecklistsRepository {
  Future<List<SavedChecklist>> listForAsset(
    String assetId, {
    SavedChecklistType? checklistType,
  }) async {
    var query = supabase
        .from(AppConstants.tSavedChecklists)
        .select()
        .eq('asset_id', assetId);

    if (checklistType != null) {
      query = query.eq('checklist_type', checklistType.name);
    }

    final data = await query.order('submitted_at', ascending: false);
    return (data as List)
        .map((row) => SavedChecklist.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<void> createSavedChecklist({
    required String assetId,
    required String clientId,
    required ChecklistTemplate template,
    required List<ChecklistItem> items,
    required Map<String, String?> responses,
    required Map<String, String> notes,
    required Map<String, String?> photoUrls,
    required String sourceType,
    required String checklistType,
    required String completedBy,
    String? submittedByRole,
    DateTime? submittedAt,
    double? currentHours,
    String? generalNotes,
    String? workOrderId,
    String? assignmentId,
    Map<String, dynamic>? extraHeader,
  }) async {
    final submitted = submittedAt ?? DateTime.now();
    final answeredItems = items
        .where((item) => responses[item.id] != null)
        .map(
          (item) => {
            'id': item.id,
            'description_en': item.descriptionEn,
            'description_es': item.descriptionEs,
            'category': item.category,
            'sort_order': item.sortOrder,
            'response': _normalizeResponseStatus(responses[item.id]!),
            'note': notes[item.id],
            'photo_url': photoUrls[item.id],
          },
        )
        .toList(growable: false);

    final normalizedType = checklistType == 'operations' ||
            checklistType == 'operator_daily' ||
            checklistType == 'pre_ops'
        ? SavedChecklistType.operations
        : SavedChecklistType.maintenance;

    final snapshot = <String, dynamic>{
      'asset_id': assetId,
      'template': {
        'id': template.id,
        'name': template.name,
        'checklist_type': template.checklistType,
        'version': template.version,
        'category': template.category,
        'interval_label': template.intervalLabel,
        'interval_hours': template.intervalHours,
      },
      'header': {
        'asset_id': assetId,
        'checklist_name': template.name,
        'completed_by': completedBy,
        'submitted_at': submitted.toIso8601String(),
        'current_hours': currentHours,
        'general_notes': generalNotes,
        if (extraHeader != null) ...extraHeader,
      },
      'items': answeredItems,
      'source': {
        'source_type': sourceType,
        'work_order_id': workOrderId,
        'assignment_id': assignmentId,
      },
      'submitted_by_role': submittedByRole,
    };

    await supabase.from(AppConstants.tSavedChecklists).insert({
      'asset_id': assetId,
      'client_id': clientId,
      'template_id': template.id,
      'template_name': template.name,
      'checklist_type': normalizedType.name,
      'source_type': sourceType,
      'submitted_by': completedBy,
      'submitted_by_role': submittedByRole,
      'submitted_at': submitted.toIso8601String(),
      'current_hours': currentHours,
      'general_notes': generalNotes,
      'work_order_id': workOrderId,
      'assignment_id': assignmentId,
      'snapshot': snapshot,
    });
  }

  String _normalizeResponseStatus(String status) {
    switch (status.toLowerCase()) {
      case 'alert':
      case 'monitor':
        return 'monitor';
      case 'action':
        return 'action';
      case 'pass':
        return 'pass';
      case 'na':
      case 'n/a':
        return 'n/a';
      default:
        return status;
    }
  }
}
