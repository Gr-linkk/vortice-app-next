import 'dart:convert';
import 'dart:io';
import 'audit_output.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/features/maintenance/maintenance_repository.dart';
import 'package:vortice_app/features/fleet/fleet_repository.dart';
import 'package:vortice_app/features/fleet/fleet_models.dart';
import 'package:vortice_app/sync/field_work_provider.dart';
import 'connected_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'connected direct fault repair and scoped work discovery',
    (tester) async {
      await tester.runAsync(() async {
        final h = ConnectedHarness(tester, report: 'direct012');
        await h.start();
        final marker = 'E2E-012-${const Uuid().v4().substring(0, 8)}';
        final asset = const Uuid().v4(), name = '$marker Pump vessel';
        final manifest = <String, dynamic>{
          'marker': marker,
          'asset': asset,
          'asset_name': name,
        };
        void save() => File(
          auditOutputPath('NOW-012-fixture-$marker.json'),
        ).writeAsStringSync(jsonEncode(manifest));
        save();
        String? fault, job;
        final fleet = SupabaseFleetRepository(supabase);
        final originalError = FlutterError.onError;
        FlutterError.onError = (e) {
          h.issues.add(e.exceptionAsString());
          stdout.writeln(e.exceptionAsString());
        };
        try {
          await h.login('paradise@vortice.dev');

          final workspace = await h.container
              .read(maintenanceRepositoryProvider)
              .workspace();
          await h.container
              .read(maintenanceRepositoryProvider)
              .setup(const Uuid().v4(), 'asset', asset, 0, {
                'name': name,
                'location': '$marker Dock',
                'asset_type_id': (workspace['asset_types'] as List).first['id'],
              });
          final catalog = await h.container
              .read(maintenanceRepositoryProvider)
              .assetContext(asset);
          final mechanic =
              (catalog['assignees'] as List).firstWhere(
                    (p) => p['role'] == 'client_mechanic',
                  )
                  as Map;
          await h.step('operator reports fault through real screen', () async {
            await h.login('operator@vortice.dev');
            await h.go('/fleet/report?assetId=$asset');
            await h.fill(
              h.field('Describe the fault'),
              '$marker Pump seal leak',
            );
            await h.tap(find.byType(FilledButton).last);
            final faults = await fleet.faults(assetId: asset);
            expect(faults.length, 1);
            fault = faults.single.id;
            manifest['fault'] = fault;
            save();
          });
          await h.step('manager plans prefilled repair from fault', () async {
            if (fault == null) throw StateError('No fault');
            await h.login('paradise@vortice.dev');
            await h.go('/fleet/faults/$fault');
            await h.tap(find.text('Plan repair'));
            await h.select('Assigned to', mechanic['name'] as String);
            await h.tap(
              find.widgetWithText(FilledButton, 'Create & open work order'),
            );
            final linked = (await fleet.faults(faultId: fault)).single;
            job = linked.workOrderId;
            expect(job, isNotNull);
            expect(linked.workOrderManaged, isTrue);
            manifest['maintenance_job'] = job;
            save();
            expect(
              (await h.container
                      .read(maintenanceRepositoryProvider)
                      .jobs(jobId: job))
                  .single
                  .status,
              'assigned',
            );
          });
          await h.step('asset Work orders opens only its linked job', () async {
            if (job == null) throw StateError('No job');
            await h.go('/maintenance/assets/$asset');
            expect(find.text('Edit asset'), findsNothing);
            await h.tap(find.text('Work orders'));
            final saved =
                (await h.container
                        .read(maintenanceRepositoryProvider)
                        .jobs(jobId: job))
                    .single;
            await h.tap(find.text(saved.title));
            expect(find.text('Assign work order'), findsNothing);
            await h.screenshot('direct012-asset-work');
          });
          await h.step(
            'mechanic starts work and submits repair report',
            () async {
              if (job == null) throw StateError('No job');
              await h.login('client_mechanic@vortice.dev');
              await h.go('/fleet/faults/$fault');
              await h.tap(find.text('Open work order'));
              await h.tap(find.widgetWithText(FilledButton, 'Start work'));
              final operations = await h.container
                  .read(fieldWorkQueueProvider)!
                  .list();
              expect(
                operations.every((o) => o.synced),
                isTrue,
                reason: operations
                    .map((o) => '${o.status}: ${o.error}')
                    .join('\n'),
              );
              expect(
                (await fleet.faults(faultId: fault)).single.status,
                FaultStatus.inProgress,
              );
              await h.tap(find.text('Continue work report'));
              await h.fill(h.field('Findings'), '$marker Worn seal');
              await h.fill(
                h.field('Work performed and results'),
                '$marker Replaced seal; pressure held at 100 psi',
              );
              final submit = find.widgetWithText(
                FilledButton,
                'Submit for review',
              );
              await h.reveal(submit);
              expect(tester.widget<FilledButton>(submit).onPressed, isNull);
              await h.tap(find.text('Open labour timer'));
              await h.tap(find.widgetWithText(TextButton, 'Pause'));
              await h.tap(find.text('Continue work report'));
              expect(
                tester.widget<TextField>(h.field('Findings')).controller!.text,
                '$marker Worn seal',
              );
              await h.tap(
                find.widgetWithText(FilledButton, 'Submit for review'),
              );
              expect(
                (await h.container
                        .read(maintenanceRepositoryProvider)
                        .jobs(jobId: job))
                    .single
                    .status,
                'pending_review',
              );
              expect(
                (await fleet.faults(faultId: fault)).single.status,
                FaultStatus.inProgress,
              );
            },
          );
          await h.step(
            'manager approval requires separate fault verification',
            () async {
              if (job == null) throw StateError('No job');
              await h.login('paradise@vortice.dev');
              await h.go('/maintenance/jobs/$job');
              await h.tap(find.text('Approve & complete'));
              await h.fill(h.field('Reason / note'), '$marker Repair checked');
              await h.tap(find.widgetWithText(FilledButton, 'Confirm'));
              expect(
                (await fleet.faults(faultId: fault)).single.status,
                FaultStatus.pendingReview,
              );
              await h.go('/fleet/faults/$fault');
              await h.tap(find.text('Verify & resolve'));
              await h.fill(
                h.field('Note / reason'),
                '$marker No leak under load',
              );
              await h.tap(find.byType(FilledButton).last);
              expect(
                (await fleet.faults(faultId: fault)).single.status,
                FaultStatus.resolved,
              );
              expect(find.text('Review asset availability'), findsOneWidget);
              await h.screenshot('direct012-resolved');
            },
          );
          await h.step(
            'operator and other company retain private-work boundaries',
            () async {
              await h.login('operator@vortice.dev');
              await h.go('/fleet/faults/$fault');
              expect(find.text('Open work order'), findsNothing);
              await h.login('client@vortice.dev');
              expect(await fleet.faults(assetId: asset), isEmpty);
              expect(
                await h.container
                    .read(maintenanceRepositoryProvider)
                    .jobs(assetId: asset),
                isEmpty,
              );
              await h.go('/maintenance?assetId=$asset');
              expect(find.text('$marker Pump seal leak'), findsNothing);
            },
          );
        } finally {
          FlutterError.onError = originalError;
          await h.close();
        }
        expect(h.issues, isEmpty, reason: 'See the connected audit output');
      });
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}
