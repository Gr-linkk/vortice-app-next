import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/account_storage.dart';
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
    item.definition['authored'] == true ||
    _isAllowedSnapshotText(item.descriptionEn);

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
    final account = supabase.auth.currentUser!.id;
    final data =
        await AccountJsonCache(
          account,
          () => supabase.auth.currentUser?.id,
        ).readThrough(
          'work_checklist_snapshot:$workOrderId',
          () => supabase
              .from(AppConstants.tWorkOrderChecklistSnapshots)
              .select()
              .eq('work_order_id', workOrderId)
              .maybeSingle()
              .timeout(const Duration(seconds: 6)),
        );
    if (data == null) return null;
    return WorkOrderChecklistSnapshot.fromJson(
      Map<String, dynamic>.from(data as Map),
    );
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

  /// The work-order transaction freezes the snapshot and template version.
  /// Read that authoritative copy; clients must never overwrite job history.
  Future<Map<String, dynamic>?> trySyncForWorkOrderTemplate({
    required String workOrderId,
    required String? templateId,
  }) async {
    if (templateId == null) return null;
    try {
      return await supabase
          .from(AppConstants.tWorkOrderChecklistSnapshots)
          .select()
          .eq('work_order_id', workOrderId)
          .maybeSingle();
    } catch (_) {
      return null;
    }
  }
}

const workOrderChecklistSnapshotRepository =
    WorkOrderChecklistSnapshotRepository();
