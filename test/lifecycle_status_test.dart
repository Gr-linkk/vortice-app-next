import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/maintenance/maintenance_models.dart';
import 'package:vortice_app/features/maintenance/planning/planning_models.dart';
import 'package:vortice_app/features/maintenance/work_list_provider.dart';

void main() {
  MaintenanceJob job(String status, [Map<String, dynamic> fields = const {}]) =>
      MaintenanceJob({'id': 'work', 'asset_id': 'asset', 'status': status, ...fields});

  test('assignment and deadlines never imply a booking', () {
    expect(job('draft').lifecycleLabel(false), 'Unassigned');
    expect(job('assigned').lifecycleLabel(false), 'Unscheduled');
    expect(job('assigned', {'due_date': '2026-09-18', 'scheduled_date': '2026-09-18'}).lifecycleLabel(false), 'Unscheduled');
    expect(job('draft', {'planned_start': '2026-09-18T10:00:00Z'}).lifecycleLabel(false), 'Scheduled');
    expect(job('assigned', {'planned_start': '2026-09-18T10:00:00Z'}).lifecycleLabel(false), 'Scheduled');
    expect(job('assigned', {'service_date': '2026-09-18'}).lifecycleLabel(false), 'Scheduled');
    expect(maintenanceStatus('assigned', false), 'Assigned');
  });

  test('review and completion supersede a stale return timestamp', () {
    final fields = {'returned_at': '2026-09-17T15:00:00Z'};
    expect(job('in_progress', fields).lifecycleLabel(false), 'Returned');
    expect(job('on_hold', fields).lifecycleLabel(false), 'Returned');
    expect(job('pending_review', fields).lifecycleLabel(false), 'Awaiting review');
    expect(job('pending_review', fields).returned, isFalse);
    for (final status in ['closed', 'invoiced']) {
      expect(job(status, fields).lifecycleLabel(false), 'Completed');
      expect(job(status, fields).returned, isFalse);
    }
    expect(job('in_progress').lifecycleLabel(false), 'In progress');
    expect(job('on_hold').lifecycleLabel(false), 'Blocked');
  });

  test('planning and Home entries display the same booked state', () {
    final planned = PlanningJob({'id': 'work', 'asset_id': 'asset', 'status': 'assigned', 'planned_start': '2026-09-18T10:00:00Z'});
    final entry = WorkListEntry(id: planned.id, title: '', assetName: '', status: planned.status, route: planned.route, assignedToMe: true, service: false, hasBooking: planned.hasBooking, returned: planned.returned);
    expect(entry.lifecycleLabel(false), planned.lifecycleLabel(false));
    expect(planned.matchesSearch('scheduled', false), isTrue);
    expect(planned.lifecycle, 'scheduled');
    expect(entry.lifecycleLabel(true), 'Programado');
    planned.data['status'] = 'invoiced';
    expect(planned.matchesSearch('completed', false), isTrue);
    expect(planned.matchesSearch('invoiced', false), isTrue);
  });
}
