import 'package:vortice_app/models/asset.dart';
import 'package:vortice_app/features/checklists/asset_checklist_template_filter.dart';
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
      .where(
        (template) => checklistTemplateMatches(
          template,
          kind: 'pm',
          assetId: asset?.id,
          assetTypeId: asset?.assetTypeId,
          clientId: asset?.clientId,
        ),
      )
      .toList();
  maintenanceTemplates.sort(compareTemplatesForMaintenancePlan);
  return maintenanceTemplates;
}
