import 'package:vortice_app/models/asset.dart';
import 'package:vortice_app/models/checklist_template.dart';

int compareTemplatesForMaintenancePlan(
  ChecklistTemplate a,
  ChecklistTemplate b,
) {
  final hoursCompare = (a.intervalHours ?? 1 << 30).compareTo(
    b.intervalHours ?? 1 << 30,
  );
  if (hoursCompare != 0) return hoursCompare;
  return a.name.compareTo(b.name);
}

List<ChecklistTemplate> maintenanceTemplatesForAsset(
  List<ChecklistTemplate> templates,
  Asset? asset,
) {
  final maintenanceTemplates = templates
      .where((template) => template.isActive && template.checklistType == 'pm')
      .toList();
  final assetTypeId = asset?.assetTypeId;
  if (assetTypeId == null) {
    maintenanceTemplates.sort(compareTemplatesForMaintenancePlan);
    return maintenanceTemplates;
  }

  final matching = maintenanceTemplates
      .where((template) => template.assetTypeId == assetTypeId)
      .toList();
  matching.sort(compareTemplatesForMaintenancePlan);
  return matching.isNotEmpty ? matching : maintenanceTemplates
    ..sort(compareTemplatesForMaintenancePlan);
}
