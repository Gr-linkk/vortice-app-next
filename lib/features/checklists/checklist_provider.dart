import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/models/checklist_item.dart';
import 'package:vortice_app/models/checklist_response.dart';
import 'package:vortice_app/models/checklist_template.dart';

class WorkOrderChecklistSnapshot {
  final String workOrderId;
  final String? templateId;
  final int? templateVersion;
  final String templateName;
  final String? templateDescription;
  final String checklistType;
  final String? assetTypeId;
  final int? intervalHours;
  final String? intervalLabel;
  final List<ChecklistItem> items;

  const WorkOrderChecklistSnapshot({
    required this.workOrderId,
    required this.templateId,
    required this.templateVersion,
    required this.templateName,
    required this.templateDescription,
    required this.checklistType,
    required this.assetTypeId,
    required this.intervalHours,
    required this.intervalLabel,
    required this.items,
  });

  ChecklistTemplate asTemplate() => ChecklistTemplate(
        id: templateId ?? 'snapshot:$workOrderId',
        assetTypeId: assetTypeId,
        checklistType: checklistType,
        intervalHours: intervalHours,
        intervalLabel: intervalLabel,
        name: templateName,
        description: templateDescription,
        version: templateVersion ?? 1,
        isActive: true,
      );

  factory WorkOrderChecklistSnapshot.fromJson(Map<String, dynamic> json) {
    final itemsJson = (json['items_json'] as List?) ?? const [];
    return WorkOrderChecklistSnapshot(
      workOrderId: json['work_order_id'] as String,
      templateId: json['template_id'] as String?,
      templateVersion: (json['template_version'] as num?)?.toInt(),
      templateName: json['template_name'] as String? ?? 'Checklist',
      templateDescription: json['template_description'] as String?,
      checklistType: json['checklist_type'] as String? ?? 'pm',
      assetTypeId: json['asset_type_id'] as String?,
      intervalHours: (json['interval_hours'] as num?)?.toInt(),
      intervalLabel: json['interval_label'] as String?,
      items: itemsJson
          .whereType<Map>()
          .map((raw) => Map<String, dynamic>.from(raw))
          .map(ChecklistItem.fromJson)
          .toList(),
    );
  }
}

final workOrderChecklistSnapshotProvider =
    FutureProvider.family<WorkOrderChecklistSnapshot?, String>(
        (ref, workOrderId) async {
  try {
    final data = await supabase
        .from('work_order_checklist_snapshots')
        .select()
        .eq('work_order_id', workOrderId)
        .maybeSingle();
    if (data == null) return null;
    return WorkOrderChecklistSnapshot.fromJson(data);
  } catch (_) {
    return null;
  }
});

final checklistTemplatesProvider =
    FutureProvider<List<ChecklistTemplate>>((ref) async {
  final data = await supabase
      .from(AppConstants.tChecklistTemplates)
      .select()
      .order('name');
  return (data as List)
      .map((e) => ChecklistTemplate.fromJson(e as Map<String, dynamic>))
      .toList();
});

final checklistItemsProvider =
    FutureProvider.family<List<ChecklistItem>, String>((ref, templateId) async {
  final data = await supabase
      .from(AppConstants.tChecklistItems)
      .select()
      .eq('template_id', templateId)
      .order('sort_order');
  return (data as List)
      .map((e) => ChecklistItem.fromJson(e as Map<String, dynamic>))
      .toList();
});

final checklistResponsesProvider =
    FutureProvider.family<List<ChecklistResponse>, String>(
        (ref, workOrderId) async {
  final data = await supabase
      .from(AppConstants.tChecklistResponses)
      .select()
      .eq('work_order_id', workOrderId);
  return (data as List)
      .map((e) => ChecklistResponse.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// Returns true if any checklist responses have been submitted for a WO.
final checklistHasResponsesProvider =
    FutureProvider.family<bool, String>((ref, workOrderId) async {
  final data = await supabase
      .from(AppConstants.tChecklistResponses)
      .select('id')
      .eq('work_order_id', workOrderId)
      .limit(1);
  return (data as List).isNotEmpty;
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
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final now = DateTime.now().toIso8601String();
      final rows = responses.entries
          .where((e) => e.value != null) // only answered items
          .map((e) => {
                'work_order_id': workOrderId,
                'checklist_item_id': e.key,
                'completed': e.value == 'pass',
                'response_status': e.value,
                'completed_by': completedBy,
                'completed_at': now,
                if (notes?[e.key]?.isNotEmpty == true) 'notes': notes![e.key],
                if (photoUrls?[e.key] != null) 'photo_url': photoUrls![e.key],
              })
          .toList();
      if (rows.isNotEmpty) {
        await supabase.from(AppConstants.tChecklistResponses).insert(rows);
      }
      _ref.invalidate(checklistResponsesProvider(workOrderId));
      _ref.invalidate(checklistHasResponsesProvider(workOrderId));
    });
  }
}

final checklistControllerProvider =
    StateNotifierProvider<ChecklistController, AsyncValue<void>>((ref) {
  return ChecklistController(ref);
});
