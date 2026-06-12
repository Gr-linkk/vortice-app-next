import 'package:flutter/material.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/models/asset.dart';
import 'package:vortice_app/models/checklist_template.dart';
import 'package:vortice_app/models/work_order.dart';

Widget createWorkOrderSectionHeader(String title) {
  return Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 4),
    child: Text(
      title,
      style: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
      ),
    ),
  );
}

List<ChecklistTemplate> checklistTemplatesForAsset(
  List<ChecklistTemplate> templates,
  Asset? asset,
) {
  final activeMaintenance = templates
      .where((template) =>
          template.isActive &&
          (template.checklistType == 'pm' ||
              template.checklistType == 'maintenance'))
      .toList();

  final assetTypeId = asset?.assetTypeId;
  if (assetTypeId != null) {
    final assetSpecific = activeMaintenance
        .where((template) => template.assetTypeId == assetTypeId)
        .toList()
      ..sort(compareChecklistTemplates);
    if (assetSpecific.isNotEmpty) return assetSpecific;
  }

  return activeMaintenance
      .where((template) => template.assetTypeId == null)
      .toList()
    ..sort(compareChecklistTemplates);
}

int compareChecklistTemplates(ChecklistTemplate a, ChecklistTemplate b) {
  final aHours = a.intervalHours ?? hoursFromTemplate(a) ?? (1 << 30);
  final bHours = b.intervalHours ?? hoursFromTemplate(b) ?? (1 << 30);
  final hoursCompare = aHours.compareTo(bHours);
  if (hoursCompare != 0) return hoursCompare;

  final labelCompare =
      (a.intervalLabel ?? '').compareTo(b.intervalLabel ?? '');
  if (labelCompare != 0) return labelCompare;

  return a.name.compareTo(b.name);
}

int? hoursFromTemplate(ChecklistTemplate template) {
  final candidates =
      [template.intervalLabel, template.name].whereType<String>().join(' ');
  final match = RegExp(r'(\d+)\s*(?:hr|hour|hours|h)\b', caseSensitive: false)
      .firstMatch(candidates);
  return match == null ? null : int.tryParse(match.group(1)!);
}

String checklistTemplateLabel(ChecklistTemplate template) {
  final prefix = template.intervalLabel?.trim().isNotEmpty == true
      ? template.intervalLabel!.trim()
      : template.intervalHours != null
          ? '${template.intervalHours} HR'
          : null;
  if (prefix == null || template.name.contains(prefix)) return template.name;
  return '$prefix — ${template.name}';
}

double? parseHoursAtStart(String hoursText) {
  final trimmed = hoursText.trim();
  if (trimmed.isEmpty) return null;
  return double.tryParse(trimmed);
}

String? notesInternalFromParts(String partsText) {
  final parts = partsText.trim();
  if (parts.isEmpty) return null;
  return 'Parts expected: $parts';
}

Map<String, dynamic> buildCreateWorkOrderPayload({
  required String title,
  required String description,
  required WorkOrderJobType jobType,
  required String createdBy,
  required String clientId,
  required String assetId,
  required List<String> assignedTechIds,
  String? engineId,
  String? checklistTemplateId,
  DateTime? scheduledDate,
  double? hoursAtStart,
  String? notesInternal,
}) {
  return {
    'title': title.trim(),
    'description': description.trim().isNotEmpty ? description.trim() : null,
    'job_type': jobType.dbValue,
    'status': assignedTechIds.isNotEmpty
        ? WorkOrderStatus.assigned.dbValue
        : WorkOrderStatus.draft.dbValue,
    'created_by': createdBy,
    'client_id': clientId,
    'asset_id': assetId,
    if (engineId != null) 'engine_id': engineId,
    if (assignedTechIds.isNotEmpty) 'assigned_to': assignedTechIds.first,
    if (checklistTemplateId != null)
      'checklist_template_id': checklistTemplateId,
    'scheduled_date': scheduledDate?.toIso8601String().split('T').first,
    if (hoursAtStart != null) 'hours_at_start': hoursAtStart,
    if (notesInternal != null) 'notes_internal': notesInternal,
  };
}
