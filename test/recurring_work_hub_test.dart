import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/maintenance/planning/planning_models.dart';

void main() {
  test(
    'km due work enters the same overdue filter before calendar deadline',
    () {
      final job = PlanningJob({
        'id': 'truck-work',
        'asset_id': 'truck',
        'status': 'draft',
        'due_date': '2027-09-12',
        'due_meter': 62000,
        'current_meter': 62000,
        'meter_unit': 'km',
      });
      expect(job.matchesFilter('overdue', null, DateTime(2026, 9, 12)), isTrue);
      expect(job.unscheduled, isTrue);
      job.data['cycle_approved_at'] = '2026-09-12T15:00:00Z';
      expect(job.meterDue, isFalse);
      job.data['status'] = 'closed';
      expect(job.matchesFilter('overdue', null, DateTime(2028)), isFalse);
      expect(job.matchesFilter('completed', null, DateTime(2028)), isTrue);
    },
  );

  test('returned work has one consistent filter and searchable label', () {
    final job = PlanningJob({
      'id': 'returned-work',
      'asset_id': 'asset',
      'status': 'in_progress',
      'returned_at': '2026-09-12T12:00:00Z',
    });
    expect(job.lifecycleLabel(false), 'Returned');
    expect(job.matchesFilter('returned', null, DateTime(2026)), isTrue);
    expect(job.matchesSearch('returned', false), isTrue);
    job.data['returned_at'] = null;
    job.data['status'] = 'pending_review';
    expect(job.matchesFilter('returned', null, DateTime(2026)), isFalse);
    expect(job.lifecycleLabel(false), 'Awaiting review');
  });
}
