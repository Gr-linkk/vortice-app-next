import 'package:vortice_app/models/checklist_template.dart';

List<ChecklistTemplate> templatesForAssetChecklist({
  required List<ChecklistTemplate> templates,
  required String? assetTypeId,
}) {
  if (assetTypeId == null || assetTypeId.trim().isEmpty) {
    return const [];
  }

  return templates
      .where((template) => template.isActive)
      .where((template) => template.assetTypeId == assetTypeId)
      .toList(growable: false);
}
