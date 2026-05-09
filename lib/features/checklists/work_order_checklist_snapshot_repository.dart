import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/models/checklist_item.dart';
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
          .where(_isAllowedSnapshotItem)
          .toList(),
    );
  }
}

bool _isAllowedSnapshotItem(ChecklistItem item) =>
    _isAllowedSnapshotText(item.descriptionEn);

bool _isAllowedSnapshotItemJson(Map<String, dynamic> item) =>
    _isAllowedSnapshotText(item['description_en'] as String? ?? '');

bool _isAllowedSnapshotText(String value) {
  final text = value.toLowerCase();
  if (text.contains('client sign')) return false;
  if (text.contains('customer sign')) return false;
  if (text.contains('sign-off')) return false;
  if (text.contains('sign off')) return false;
  if (text.contains('signature')) return false;
  return true;
}

class WorkOrderChecklistSnapshotRepository {
  const WorkOrderChecklistSnapshotRepository();

  Future<WorkOrderChecklistSnapshot?> fetchByWorkOrderId(
    String workOrderId,
  ) async {
    final data = await supabase
        .from(AppConstants.tWorkOrderChecklistSnapshots)
        .select()
        .eq('work_order_id', workOrderId)
        .maybeSingle();
    if (data == null) return null;
    return WorkOrderChecklistSnapshot.fromJson(data);
  }

  Future<WorkOrderChecklistSnapshot?> tryFetchByWorkOrderId(
    String workOrderId,
  ) async {
    try {
      return await fetchByWorkOrderId(workOrderId);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> buildPayload({
    required String workOrderId,
    required String templateId,
  }) async {
    final template = await supabase
        .from(AppConstants.tChecklistTemplates)
        .select(
          'id, asset_type_id, checklist_type, interval_hours, interval_label, name, description, version, updated_at',
        )
        .eq('id', templateId)
        .maybeSingle();
    if (template == null) return null;

    final itemRows = await supabase
        .from(AppConstants.tChecklistItems)
        .select(
          'id, template_id, description_en, description_es, category, requires_photo, sort_order, created_at',
        )
        .eq('template_id', templateId)
        .order('sort_order');
    final items = (itemRows as List)
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .where(_isAllowedSnapshotItemJson)
        .toList();

    return {
      'work_order_id': workOrderId,
      'template_id': template['id'],
      'template_version': (template['version'] as num?)?.toInt(),
      'template_name': template['name'],
      'template_description': template['description'],
      'checklist_type': template['checklist_type'] ?? 'pm',
      'asset_type_id': template['asset_type_id'],
      'interval_hours': template['interval_hours'],
      'interval_label': template['interval_label'],
      'source_template_updated_at': template['updated_at'],
      'items_json': items,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }

  Future<Map<String, dynamic>?> upsertForWorkOrderTemplate({
    required String workOrderId,
    required String templateId,
  }) async {
    final payload = await buildPayload(
      workOrderId: workOrderId,
      templateId: templateId,
    );
    if (payload == null) return null;

    await supabase
        .from(AppConstants.tWorkOrderChecklistSnapshots)
        .upsert(payload, onConflict: 'work_order_id');
    return payload;
  }

  Future<void> deleteForWorkOrder(String workOrderId) async {
    await supabase
        .from(AppConstants.tWorkOrderChecklistSnapshots)
        .delete()
        .eq('work_order_id', workOrderId);
  }

  Future<Map<String, dynamic>?> trySyncForWorkOrderTemplate({
    required String workOrderId,
    required String? templateId,
  }) async {
    try {
      if (templateId == null) {
        await deleteForWorkOrder(workOrderId);
        return null;
      }
      return await upsertForWorkOrderTemplate(
        workOrderId: workOrderId,
        templateId: templateId,
      );
    } catch (_) {
      // Snapshot support is best-effort until every environment has the table.
      return null;
    }
  }
}

const workOrderChecklistSnapshotRepository =
    WorkOrderChecklistSnapshotRepository();
