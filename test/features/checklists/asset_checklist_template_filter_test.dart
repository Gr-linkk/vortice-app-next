import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/checklists/asset_checklist_template_filter.dart';
import 'package:vortice_app/models/checklist_template.dart';

void main() {
  test('shows only active templates assigned to the selected asset type', () {
    final templates = [
      _template(id: 'generic', name: 'Generic Marine'),
      _template(
          id: 'dredge-preop', name: 'Dredge Pre-Op', assetTypeId: 'dredge'),
      _template(
        id: 'dredge-250',
        name: 'Dredge 250HR',
        assetTypeId: 'dredge',
        intervalHours: 250,
      ),
      _template(id: 'tug-preop', name: 'Tug Pre-Op', assetTypeId: 'tug'),
      _template(
        id: 'inactive-dredge',
        name: 'Inactive Dredge',
        assetTypeId: 'dredge',
        isActive: false,
      ),
    ];

    final filtered = templatesForAssetChecklist(
      templates: templates,
      assetTypeId: 'dredge',
    );

    expect(filtered.map((template) => template.id), [
      'dredge-250',
      'dredge-preop',
    ]);
  });

  test('returns no templates when the asset type is unavailable', () {
    expect(
      templatesForAssetChecklist(
        templates: [_template(id: 'generic', name: 'Generic Marine')],
        assetTypeId: null,
      ),
      isEmpty,
    );
  });
}

ChecklistTemplate _template({
  required String id,
  required String name,
  String? assetTypeId,
  int? intervalHours,
  bool isActive = true,
}) =>
    ChecklistTemplate(
      id: id,
      assetTypeId: assetTypeId,
      name: name,
      intervalHours: intervalHours,
      isActive: isActive,
    );
