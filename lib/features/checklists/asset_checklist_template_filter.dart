import 'package:vortice_app/models/checklist_template.dart';

List<ChecklistTemplate> templatesForAssetChecklist({
  required List<ChecklistTemplate> templates,
  required String? assetTypeId,
}) {
  if (assetTypeId == null || assetTypeId.trim().isEmpty) {
    return const [];
  }

  final filtered = templates
      .where((template) => template.isActive)
      .where((template) => template.assetTypeId == assetTypeId)
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
