import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/features/maintenance/maintenance_repository.dart';
import 'package:vortice_app/features/fleet/fleet_repository.dart';
import 'package:vortice_app/features/coordination/coordination_repository.dart';
import 'connected_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'connected maintenance, faults, availability and handover',
    (tester) async {
      await tester.runAsync(() async {
        final h = ConnectedHarness(tester, report: 'operations');
        await h.start();
        final marker = 'E2E-010-${const Uuid().v4().substring(0, 8)}';
        final asset = const Uuid().v4(), name = '$marker Operations vessel';
        final manifest = <String, dynamic>{
          'marker': marker,
          'asset': asset,
          'asset_name': name,
        };
        void save() => File(
          'outputs/NOW-010-fixture-$marker.json',
        ).writeAsStringSync(jsonEncode(manifest));
        save();
        String? job, fault;
        final originalError = FlutterError.onError;
        FlutterError.onError = (e) {
          h.issues.add(e.exceptionAsString());
          stdout.writeln('FRAMEWORK ${e.exceptionAsString()}');
        };
        try {
          await h.login('paradise@vortice.dev');
          final repo = h.container.read(maintenanceRepositoryProvider),
              fleet = SupabaseFleetRepository(supabase);
          final workspace = await repo.workspace();
          await repo.setup(const Uuid().v4(), 'asset', asset, 0, {
            'name': name,
            'location': '$marker Dock',
            'asset_type_id': (workspace['asset_types'] as List).first['id'],
          });
          final context = await repo.assetContext(asset);
          final mechanic =
              (context['assignees'] as List).firstWhere(
                    (p) => p['role'] == 'client_mechanic',
                  )
                  as Map;
          await h.step('manager creates assigned maintenance job', () async {
            await h.go('/maintenance/new?assetId=$asset');
            await h.fill(h.field('Work to do'), '$marker Repair pump');
            await h.fill(
              h.field('Instructions'),
              '$marker Isolate, inspect and test pump',
            );
            await h.select('Assigned to', mechanic['name'] as String);
            await h.tap(find.widgetWithText(FilledButton, 'Create job'));
            final jobs = await repo.jobs(assetId: asset);
            expect(jobs.length, 1);
            job = jobs.single.id;
            manifest['maintenance_job'] = job;
            save();
            expect(jobs.single.status, 'assigned');
          });
          await h.step(
            'mechanic labour, blocking, resuming and parts persist',
            () async {
              if (job == null) throw StateError('No created job');
              await h.login('client_mechanic@vortice.dev');
              await h.go('/maintenance/jobs/$job');
              await h.tap(find.text('Start labour'));
              await h.tap(find.widgetWithText(TextButton, 'Pause'));
              await h.tap(find.text('Block'));
              await h.fill(
                h.field('Reason / note'),
                '$marker Waiting for seal',
              );
              await h.tap(find.widgetWithText(FilledButton, 'Confirm'));
              expect((await repo.jobs(jobId: job)).single.status, 'on_hold');
              await h.tap(find.text('Start labour'));
              await h.tap(find.widgetWithText(TextButton, 'Pause'));
              await h.tap(find.text('Add part'));
              await h.fill(h.field('Description'), '$marker Pump seal');
              await h.fill(h.field('Quantity'), '2');
              await h.fill(h.field('Unit cost (USD)'), '12.50');
              await h.tap(find.widgetWithText(FilledButton, 'Confirm'));
              final saved = (await repo.jobs(jobId: job)).single;
              expect(saved.parts.length, 1);
              expect(saved.parts.single['quantity'], 2);
              expect(saved.labour.length, 2);
            },
          );
          Future<void> report(String suffix, String action) async {
            await h.go('/maintenance/jobs/$job');
            await h.tap(find.text('Report & submit'));
            await h.fill(h.field('Diagnosis'), '$marker Worn seal $suffix');
            await h.fill(
              h.field('Repair and test results'),
              '$marker Replaced seal, pressure test passed $suffix',
            );
            await h.tap(
              action == 'Save draft'
                  ? find.widgetWithText(OutlinedButton, action)
                  : find.widgetWithText(FilledButton, action),
            );
          }

          await h.step(
            'maintenance report draft and reopen retain entered data',
            () async {
              if (job == null) throw StateError('No created job');
              await report('draft', 'Save draft');
              await h.go('/maintenance/jobs/$job');
              await h.tap(find.text('Report & submit'));
              expect(
                tester.widget<TextField>(h.field('Diagnosis')).controller!.text,
                '$marker Worn seal draft',
              );
              await h.tap(
                find.widgetWithText(FilledButton, 'Submit for review'),
              );
              expect(
                (await repo.jobs(jobId: job)).single.status,
                'pending_review',
              );
            },
          );
          Future<void> review(String label, String note) async {
            await h.go('/maintenance/jobs/$job');
            await h.tap(find.text(label));
            await h.fill(h.field('Reason / note'), note);
            await h.tap(find.widgetWithText(FilledButton, 'Confirm'));
          }

          await h.step(
            'manager return, mechanic correction and final approval',
            () async {
              if (job == null) throw StateError('No created job');
              await h.login('paradise@vortice.dev');
              await review('Return', '$marker Add pressure reading');
              await h.login('client_mechanic@vortice.dev');
              await report('100 psi', 'Submit for review');
              await h.login('paradise@vortice.dev');
              await review(
                'Approve & complete',
                '$marker Verified 100 psi and labour',
              );
              expect((await repo.jobs(jobId: job)).single.status, 'closed');
            },
          );
          await h.step(
            'operator reports a fault and manager assigns repair',
            () async {
              await h.login('operator@vortice.dev');
              await h.go('/fleet/report?assetId=$asset');
              await h.fill(
                h.field('Describe the fault'),
                '$marker Steering vibration',
              );
              final buttons = find.byType(FilledButton);
              await h.tap(buttons.last);
              final faults = await fleet.faults(assetId: asset);
              expect(faults.length, 1);
              fault = faults.single.id;
              manifest['fault'] = fault;
              save();
              await h.login('paradise@vortice.dev');
              await h.go('/fleet/faults/$fault');
              await h.tap(find.text('Acknowledge'));
              await h.fill(
                h.field('Note / reason'),
                '$marker Scheduled diagnostic',
              );
              await h.tap(find.byType(FilledButton).last);
              await h.tap(find.text('Assign repair'));
              await h.select('Assigned to', mechanic['name'] as String);
              await h.fill(
                h.field('Note / reason'),
                '$marker Assigned mechanic',
              );
              await h.tap(find.byType(FilledButton).last);
              expect(
                (await fleet.faults(faultId: fault)).single.assignedTo,
                mechanic['id'],
              );
            },
          );
          Future<void> faultAction(String label, String note) async {
            await h.go('/fleet/faults/$fault');
            await h.tap(find.text(label));
            await h.fill(h.field('Note / reason'), note);
            await h.tap(find.byType(FilledButton).last);
          }

          await h.step(
            'fault repair, review, resolution and reopening',
            () async {
              if (fault == null) throw StateError('No created fault');
              await h.login('client_mechanic@vortice.dev');
              await faultAction('Start repair', '$marker Inspection started');
              await faultAction(
                'Add progress note',
                '$marker Fasteners checked',
              );
              await faultAction(
                'Submit for review',
                '$marker Vibration corrected',
              );
              await h.login('paradise@vortice.dev');
              await faultAction(
                'Verify & resolve',
                '$marker Operational test passed',
              );
              expect(
                (await fleet.faults(faultId: fault)).single.status.name,
                'resolved',
              );
              await faultAction('Reopen fault', '$marker Recheck at load');
              await faultAction(
                'Dismiss with reason',
                '$marker Duplicate of planned test',
              );
              expect(
                (await fleet.faults(faultId: fault)).single.status.name,
                'dismissed',
              );
              expect(
                (await fleet.faultEvents(fault!)).length,
                greaterThanOrEqualTo(8),
              );
            },
          );
          await h.step(
            'manager availability update requires reason and persists',
            () async {
              await h.login('paradise@vortice.dev');
              await h.go('/fleet/assets/$asset');
              await h.tap(
                find.widgetWithText(FilledButton, 'Update availability'),
              );
              await h.select('State', 'Available');
              await h.tap(find.widgetWithText(FilledButton, 'Save state'));
              expect(find.text('Explain this change'), findsOneWidget);
              await h.fill(
                h.field('Reason / verification'),
                '$marker Checked after repair',
              );
              await h.tap(find.widgetWithText(FilledButton, 'Save state'));
              expect(
                (await fleet.fleet())
                    .singleWhere((a) => a.id == asset)
                    .state
                    .name,
                'available',
              );
              expect((await fleet.availabilityEvents(asset)).length, 1);
            },
          );
          await h.step(
            'shift handover persists and another team member acknowledges',
            () async {
              await h.login('paradise@vortice.dev');
              await h.go('/discussion/job/$job');
              await h.tap(find.text('Write a note or handover'));
              await h.select('Note type', 'Shift handover');
              await h.fill(
                h.field('What happened / current situation'),
                '$marker Pump repaired and tested',
              );
              await h.fill(
                h.field('Next shift / outstanding work'),
                '$marker Recheck pressure under load',
              );
              await h.tap(find.widgetWithText(FilledButton, 'Post note'));
              final coordination = SupabaseCoordinationRepository(supabase);
              final query = (
                subject: (kind: 'job', id: job!),
                before: null,
                beforeId: null,
                focus: null,
              );
              final posted = coordinationRows(
                (await coordination.thread(query))['posts'],
              );
              expect(posted.length, 1);
              expect(posted.single['kind'], 'handover');
              await h.login('client_mechanic@vortice.dev');
              await h.go('/discussion/job/$job');
              await h.tap(find.text('Acknowledge handover'));
              final acknowledged = coordinationRows(
                (await coordination.thread(query))['posts'],
              ).single;
              expect((acknowledged['acknowledgements'] as List).length, 1);
            },
          );
          await h.step(
            'asset history shows the saved maintenance and fault events',
            () async {
              await h.login('paradise@vortice.dev');
              await h.go('/history/assets/$asset');
              expect(find.textContaining(marker), findsWidgets);
              await h.screenshot('operations-history');
            },
          );
        } finally {
          FlutterError.onError = originalError;
          save();
          await h.close();
        }
        File('outputs/NOW-010-operations.json').writeAsStringSync(
          const JsonEncoder.withIndent(
            '  ',
          ).convert({'steps': h.steps, 'issues': h.issues}),
        );
        expect(h.issues, isEmpty);
      });
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}
