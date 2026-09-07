import 'package:vortice_app/models/checklist_template.dart';

bool checklistTemplateMatches(
  ChecklistTemplate template, {
  required String kind,
  String? assetId,
  String? assetTypeId,
  String? clientId,
  String? engineId,
}) =>
    template.isActive &&
    template.checklistType == kind &&
    (template.assetTypeId == null || template.assetTypeId == assetTypeId) &&
    (template.clientId == null || template.clientId == clientId) &&
    (template.scopeAssetId == null || template.scopeAssetId == assetId) &&
    (template.scopeEngineId == null || template.scopeEngineId == engineId);

List<ChecklistTemplate> templatesForAssetChecklist({
  required List<ChecklistTemplate> templates,
  required String? assetTypeId,
  String? assetId,
  String? clientId,
}) {
  if ((assetTypeId == null || assetTypeId.trim().isEmpty) && assetId == null) {
    return const [];
  }

  final filtered = templates
      .where(
        (template) => checklistTemplateMatches(
          template,
          kind: 'pm',
          assetId: assetId,
          assetTypeId: assetTypeId,
          clientId: clientId,
        ),
      )
      .toList();
  filtered.sort(_compareByServiceHoursThenName);
  return filtered;
}

int _compareByServiceHoursThenName(ChecklistTemplate a, ChecklistTemplate b) {
  final hoursCompare = (a.intervalHours ?? 1 << 30).compareTo(
    b.intervalHours ?? 1 << 30,
  );
  if (hoursCompare != 0) return hoursCompare;
  return a.name.compareTo(b.name);
}
