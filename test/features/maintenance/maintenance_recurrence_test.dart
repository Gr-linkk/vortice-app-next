import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/maintenance/maintenance_recurrence.dart';
import 'package:vortice_app/features/maintenance/planning/planning_models.dart';

void main() {
  test(
    'dredge transitions onto regular milestones despite late completion',
    () {
      const rule = MaintenanceRecurrence(
        hours: 250,
        baseline: 6700,
        fixed: true,
        anchorHours: 7000,
      );
      expect(rule.nextHours(6700), 7000);
      expect(rule.nextHours(7020), 7250);
      expect(rule.nextHours(7250), 7500);
      expect(rule.nextHours(7500), 7750);
      expect(rule.nextHours(7900), 8000);
      const otherVessel = MaintenanceRecurrence(
        hours: 300,
        baseline: 1100,
        fixed: true,
        anchorHours: 1200,
      );
      expect(otherVessel.nextHours(1250), 1500);
    },
  );
  test('completion preference follows actual hours and date', () {
    const rule = MaintenanceRecurrence(hours: 250, baseline: 1000, months: 6);
    expect(rule.nextHours(1270), 1520);
    expect(rule.nextDate(DateTime(2026, 10, 20)), DateTime(2027, 4, 20));
  });
  test('fixed calendar preserves original month end across leap year', () {
    final rule = MaintenanceRecurrence(
      hours: 0,
      baseline: 0,
      months: 1,
      fixed: true,
      anchorDate: DateTime(2028, 1, 31),
    );
    expect(rule.nextDate(DateTime(2028, 1, 31)), DateTime(2028, 2, 29));
    expect(rule.nextDate(DateTime(2028, 2, 29)), DateTime(2028, 3, 31));
    expect(rule.nextHours(42), isNull);
    expect(MaintenanceRecurrence.parseDate('2026-02-30'), isNull);
  });
  test(
    'calendar-only and combined plans are due without a misleading setup gap',
    () {
      final dateOnly = PlanningPlan({
        'id': 'p',
        'asset_id': 'a',
        'engine_id': 'e',
        'interval_hours': 0,
        'interval_months': 6,
        'next_due_date': '2026-10-01',
      });
      expect(dateOnly.needsSetup, isFalse);
      expect(dateOnly.dueOn(DateTime(2026, 9, 30)), isFalse);
      expect(dateOnly.dueOn(DateTime(2026, 10, 1)), isTrue);
      final combined = PlanningPlan({
        ...dateOnly.data,
        'interval_hours': 250,
        'current_hours': 1100,
        'next_due_hours': 1250,
      });
      expect(combined.dueOn(DateTime(2026, 10, 1)), isTrue);
    },
  );
}
