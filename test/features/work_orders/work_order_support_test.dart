import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/work_orders/work_order_support.dart';
import 'package:vortice_app/models/profile.dart';
import 'package:vortice_app/models/work_order.dart';

WorkOrder _order(String id, {String? assignedTo}) => WorkOrder(
      id: id,
      title: 'Service',
      status: WorkOrderStatus.draft,
      jobType: WorkOrderJobType.preventative,
      createdBy: 'owner-1',
      clientId: 'client-1',
      assetId: 'asset-1',
      assignedTo: assignedTo,
    );

void main() {
  group('shouldBypassWorkOrderAssignmentFilter', () {
    test('allows owners and employees to see all orders', () {
      expect(shouldBypassWorkOrderAssignmentFilter(UserRole.owner), isTrue);
      expect(shouldBypassWorkOrderAssignmentFilter(UserRole.employee), isTrue);
      expect(shouldBypassWorkOrderAssignmentFilter(UserRole.client), isFalse);
    });
  });

  group('filterWorkOrdersForAssignee', () {
    test('filters by assignment table ids when present', () {
      final orders = [_order('wo-1'), _order('wo-2'), _order('wo-3')];
      final filtered = filterWorkOrdersForAssignee(
        orders: orders,
        assignedIds: {'wo-1', 'wo-3'},
        profileId: 'tech-1',
      );

      expect(filtered.map((o) => o.id), ['wo-1', 'wo-3']);
    });

    test('falls back to legacy assigned_to column', () {
      final orders = [
        _order('wo-1', assignedTo: 'tech-1'),
        _order('wo-2', assignedTo: 'tech-2'),
      ];
      final filtered = filterWorkOrdersForAssignee(
        orders: orders,
        assignedIds: const {},
        profileId: 'tech-1',
      );

      expect(filtered.map((o) => o.id), ['wo-1']);
    });
  });

  group('parseLatestEngineHours', () {
    test('uses first row with hours and prefers hours_at_end', () {
      final snapshot = parseLatestEngineHours([
        {'id': 'wo-1', 'title': 'No hours'},
        {
          'id': 'wo-2',
          'title': 'Latest',
          'hours_at_start': 100,
          'hours_at_end': 105,
        },
      ]);

      expect(snapshot.hours, 105);
      expect(snapshot.workOrderId, 'wo-2');
      expect(snapshot.title, 'Latest');
    });

    test('returns empty snapshot when no hour values exist', () {
      final snapshot = parseLatestEngineHours([
        {'id': 'wo-1', 'title': 'No hours'},
      ]);

      expect(snapshot.hours, isNull);
      expect(snapshot.workOrderId, isNull);
    });
  });

  group('formatProfileName', () {
    test('trims and falls back when blank', () {
      expect(formatProfileName('  Alex  '), 'Alex');
      expect(formatProfileName('   '), 'Unnamed tech');
      expect(formatProfileName(null, fallback: null), isNull);
    });
  });
}
