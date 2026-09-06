import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/maintenance/maintenance_repository.dart';
import 'package:vortice_app/sync/field_work_queue.dart';

void main() {
  final server = {
    'id': 'job',
    'asset_id': 'asset',
    'revision': 0,
    'status': 'assigned',
    'can_work': true,
    'labour': [],
  };
  FieldOperation action(
    String id,
    int revision,
    String action, {
    String status = 'pending',
    Map<String, dynamic> data = const {},
  }) => FieldOperation(
    id: id,
    kind: 'apply_maintenance_field_action',
    subject: 'job',
    status: status,
    payload: {
      'p_revision': revision,
      'p_action': action,
      'p_data': data,
      'p_recorded_at': revision == 0
          ? '2026-09-06T09:00:00Z'
          : '2026-09-06T10:00:00Z',
    },
  );
  test(
    'offline start, pause, report and part stay usable without modifying server snapshot',
    () {
      final job = projectMaintenanceFieldWork(server, [
        action('start', 0, 'start', data: {'_actor': 'mechanic'}),
        action('pause', 1, 'pause'),
        action(
          'part',
          2,
          'add_part',
          data: {'description': 'Seal', 'quantity': '2', 'unit_cost': '5'},
        ),
        action(
          'report',
          3,
          'save_report',
          data: {
            'diagnosis': 'Leak',
            'repair': 'Repaired',
            'answers': {},
            'evidence_paths': [],
          },
        ),
      ]);
      expect(job.revision, 4);
      expect(job.completedLabourHours, 1);
      expect(job.partsCost, 10);
      expect(job.report['diagnosis'], 'Leak');
      expect(job.data['local_pending'], true);
      expect(server['revision'], 0);
      expect(server['labour'], isEmpty);
    },
  );
  test(
    'acknowledged work remains visible if the next read must use an older cache',
    () {
      final job = projectMaintenanceFieldWork(server, [
        action('start', 0, 'start', status: 'synced'),
      ]);
      expect(job.status, 'in_progress');
      expect(job.revision, 1);
      expect(job.data['local_pending'], isNull);
      final refreshed = projectMaintenanceFieldWork(job.data, [
        action('start', 0, 'start', status: 'synced'),
      ]);
      expect(refreshed.labour.length, 1);
    },
  );
  test(
    'rejected change blocks later local projection and never implies approval',
    () {
      final job = projectMaintenanceFieldWork(server, [
        action('start', 0, 'start', status: 'failed'),
        action('report', 1, 'submit'),
      ]);
      expect(job.status, 'assigned');
      expect(job.data['local_conflict'], true);
      expect(job.revision, 0);
    },
  );
}
