import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/maintenance/maintenance_job_screen.dart';
import 'package:vortice_app/sync/field_work_provider.dart';
import 'package:vortice_app/sync/field_work_queue.dart';
import 'maintenance_screen_test.dart' show FixtureMaintenance, pumpMaintenance;

class NoRemotePhoto extends FixtureMaintenance {
  int requests = 0;
  @override
  Future<String> evidenceUrl(String path) {
    requests++;
    return Future.error(StateError('No connection for a signed photo URL'));
  }
}

void main() {
  testWidgets(
    'local evidence renders without starting an unobserved remote request',
    (tester) async {
      final repository = NoRemotePhoto();
      await pumpMaintenance(
        tester,
        const MaintenanceEvidence(path: 'job/actor/photo.png'),
        repository,
        overrides: [
          fieldOperationsProvider.overrideWith(
            (ref) => Stream.value([
              const FieldOperation(
                id: 'photo',
                kind: 'upload',
                subject: 'job',
                payload: {
                  'bucket': 'maintenance-evidence',
                  'path': 'job/actor/photo.png',
                  'bytes':
                      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/l9sAAAAASUVORK5CYII=',
                },
              ),
            ]),
          ),
        ],
      );
      expect(find.byType(Image), findsOneWidget);
      expect(repository.requests, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
