import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/work_orders/create_work_order_support.dart';
import 'package:vortice_app/models/asset.dart';
import 'package:vortice_app/models/checklist_template.dart';
import 'package:vortice_app/models/work_order.dart';

ChecklistTemplate _template({
  required String id,
  String checklistType = 'pm',
  String? assetTypeId,
  int? intervalHours,
  String? intervalLabel,
  String name = 'Service',
}) {
  return ChecklistTemplate(
    id: id,
    name: name,
    category: 'maintenance',
    checklistType: checklistType,
    assetTypeId: assetTypeId,
    intervalHours: intervalHours,
    intervalLabel: intervalLabel,
    isActive: true,
  );
}

void main() {
  group('checklistTemplatesForAsset', () {
    test('prefers asset-specific PM templates when available', () {
      const asset = Asset(
        id: 'asset-1',
        clientId: 'client-1',
        name: 'Dredge',
        assetTypeId: 'type-a',
      );
      final templates = [
        _template(id: 'generic', assetTypeId: null, intervalHours: 250),
        _template(id: 'specific', assetTypeId: 'type-a', intervalHours: 100),
      ];

      final result = checklistTemplatesForAsset(templates, asset);

      expect(result.map((t) => t.id), ['specific']);
    });

    test('falls back to generic PM templates', () {
      const asset = Asset(
        id: 'asset-1',
        clientId: 'client-1',
        name: 'Dredge',
        assetTypeId: 'type-b',
      );
      final templates = [
        _template(id: 'generic', assetTypeId: null, intervalHours: 500),
        _template(id: 'other-type', assetTypeId: 'type-a', intervalHours: 100),
      ];

      final result = checklistTemplatesForAsset(templates, asset);

      expect(result.map((t) => t.id), ['generic']);
    });
  });

  group('buildCreateWorkOrderPayload', () {
    test('creates assigned work order when techs are selected', () {
      final payload = buildCreateWorkOrderPayload(
        title: '  Pump service ',
        description: '',
        jobType: WorkOrderJobType.preventative,
        createdBy: 'owner-1',
        clientId: 'client-1',
        assetId: 'asset-1',
        assignedTechIds: ['tech-1'],
        checklistTemplateId: 'tpl-1',
        hoursAtStart: 120,
        notesInternal: 'Parts expected: seal kit',
      );

      expect(payload['title'], 'Pump service');
      expect(payload['description'], isNull);
      expect(payload['status'], WorkOrderStatus.assigned.dbValue);
      expect(payload['assigned_to'], 'tech-1');
      expect(payload['checklist_template_id'], 'tpl-1');
      expect(payload['hours_at_start'], 120);
    });

    test('creates draft work order without assignment', () {
      final payload = buildCreateWorkOrderPayload(
        title: 'Inspection',
        description: 'Annual',
        jobType: WorkOrderJobType.repair,
        createdBy: 'owner-1',
        clientId: 'client-1',
        assetId: 'asset-1',
        assignedTechIds: const [],
      );

      expect(payload['status'], WorkOrderStatus.draft.dbValue);
      expect(payload.containsKey('assigned_to'), isFalse);
    });
  });

  group('parseHoursAtStart', () {
    test('parses numeric hours and ignores blanks', () {
      expect(parseHoursAtStart('125.5'), 125.5);
      expect(parseHoursAtStart(''), isNull);
      expect(parseHoursAtStart('abc'), isNull);
    });
  });

  group('notesInternalFromParts', () {
    test('wraps parts text when present', () {
      expect(notesInternalFromParts('seal kit'), 'Parts expected: seal kit');
      expect(notesInternalFromParts('   '), isNull);
    });
  });
}
