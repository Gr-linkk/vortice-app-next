import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/work_orders/work_order_edit_support.dart';

void main() {
  group('employeeDisplayName', () {
    test('uses full name when present', () {
      expect(
        employeeDisplayName({'id': 'tech-1', 'full_name': 'Alex Tech'}),
        'Alex Tech',
      );
    });

    test('falls back to unnamed label', () {
      expect(
        employeeDisplayName({'id': 'tech-1', 'full_name': '  '}),
        'Unnamed tech',
      );
    });
  });

  group('buildUpdateWorkOrderPayload', () {
    test('trims text fields and parses numeric values', () {
      final payload = buildUpdateWorkOrderPayload(
        title: '  Pump service ',
        description: '',
        assignedTechIds: ['tech-1', 'tech-2'],
        scheduledDate: DateTime.utc(2026, 6, 3),
        hoursAtStartText: '100.5',
        hoursAtEndText: '102',
        labourHoursText: '1.5',
        notesInternal: 'internal',
        onHoldReason: '  ',
      );

      expect(payload['title'], 'Pump service');
      expect(payload['description'], isNull);
      expect(payload['assigned_to'], 'tech-1');
      expect(payload['hours_at_start'], 100.5);
      expect(payload['hours_at_end'], 102.0);
      expect(payload['labour_hours'], 1.5);
      expect(payload['notes_internal'], 'internal');
      expect(payload['on_hold_reason'], isNull);
    });
  });

  group('selectedTechnicianNames', () {
    test('returns names for assigned ids only', () {
      final names = selectedTechnicianNames(
        [
          {'id': 'tech-1', 'full_name': 'Alex'},
          {'id': 'tech-2', 'full_name': 'Blair'},
        ],
        ['tech-2'],
      );

      expect(names, ['Blair']);
    });
  });
}
