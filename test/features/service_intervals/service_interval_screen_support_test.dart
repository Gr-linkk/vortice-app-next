import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/service_intervals/service_interval_screen_support.dart';
import 'package:vortice_app/models/asset.dart';
import 'package:vortice_app/models/checklist_template.dart';

ChecklistTemplate _template({
  required String id,
  required String name,
  int? intervalHours,
  String? assetTypeId,
}) {
  return ChecklistTemplate(
    id: id,
    name: name,
    category: 'maintenance',
    checklistType: 'pm',
    intervalHours: intervalHours,
    assetTypeId: assetTypeId,
    isActive: true,
  );
}

void main() {
  group('maintenanceTemplatesForAsset', () {
    test('filters active PM templates for asset type', () {
      final templates = [
        _template(id: 'a', name: 'A', assetTypeId: 'type-1', intervalHours: 100),
        _template(id: 'b', name: 'B', assetTypeId: 'type-2', intervalHours: 200),
        _template(id: 'c', name: 'C', assetTypeId: null, intervalHours: 250),
      ];

      final asset = Asset(
        id: 'asset-1',
        clientId: 'client-1',
        name: 'Dredge',
        assetTypeId: 'type-1',
      );
      final result = maintenanceTemplatesForAsset(templates, asset);

      expect(result.map((t) => t.id), ['a']);
    });
  });

  group('compareTemplatesForMaintenancePlan', () {
    test('sorts by interval hours then name', () {
      final low = _template(id: '1', name: 'B', intervalHours: 100);
      final high = _template(id: '2', name: 'A', intervalHours: 250);

      expect(compareTemplatesForMaintenancePlan(low, high), lessThan(0));
      expect(compareTemplatesForMaintenancePlan(high, low), greaterThan(0));
    });
  });
}
