import 'dart:convert';
import 'dart:io';
import 'audit_output.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:vortice_app/features/maintenance/maintenance_repository.dart';
import 'package:vortice_app/features/maintenance/planning/planning_repository.dart';
import 'package:vortice_app/features/maintenance/planning/planning_models.dart';
import 'connected_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'connected service plan, booking, rescheduling and execution',
    (tester) async {
      await tester.runAsync(() async {
        final h = ConnectedHarness(tester, report: 'planning013');
        await h.start();
        final marker = 'E2E-013-${const Uuid().v4().substring(0, 8)}';
        final asset = const Uuid().v4(),
            component = const Uuid().v4(),
            plan = const Uuid().v4();
        final name = '$marker Planning vessel';
        final manifest = <String, dynamic>{
          'marker': marker,
          'asset': asset,
          'asset_name': name,
        };
        void save() => File(
          auditOutputPath('NOW-013-fixture-$marker.json'),
        ).writeAsStringSync(jsonEncode(manifest));
        save();
        String? job, second;
        final originalError = FlutterError.onError;
        FlutterError.onError = (e) {
          h.issues.add(e.exceptionAsString());
          stdout.writeln('FRAMEWORK ${e.exceptionAsString()}');
        };
        try {
          await h.login('paradise@vortice.dev');
          MaintenanceRepository repository() =>
              h.container.read(maintenanceRepositoryProvider);
          Future<PlanningData> planning() =>
              h.container.read(planningRepositoryProvider).load(asset);
          final workspace = await repository().workspace();
          await repository().setup(const Uuid().v4(), 'asset', asset, 0, {
            'name': name,
            'location': '$marker Dock',
            'asset_type_id': (workspace['asset_types'] as List).first['id'],
          });
          await repository().setup(
            const Uuid().v4(),
            'component',
            component,
            0,
            {
              'asset_id': asset,
              'label': 'Auxiliary generator',
              'current_hours': 240,
            },
          );
          await repository().setup(const Uuid().v4(), 'plan', plan, 0, {
            'asset_id': asset,
            'engine_id': component,
            'interval_label': '$marker 250-hour service',
            'interval_hours': 250,
            'last_service_hours': 0,
          });
          final catalog = await repository().assetContext(asset);
          final mechanic =
              (catalog['assignees'] as List).firstWhere(
                    (p) => p['role'] == 'client_mechanic',
                  )
                  as Map;
          Future<void> pickStart() async {
            await h.tap(find.text('Booked start'));
            await h.tap(find.widgetWithText(TextButton, 'OK'));
            await h.tap(find.widgetWithText(TextButton, 'OK'));
          }

          await h.step(
            'existing service interval becomes planned work and opens booking',
            () async {
              await h.go('/maintenance/planning?assetId=$asset');
              await h.tap(find.byKey(const ValueKey('planning-collection')));
              await h.tap(find.text('Service plans'));
              await h.tap(find.widgetWithText(FilledButton, 'Plan service'));
              await h.fill(
                h.field('Work order title'),
                '$marker Generator service',
              );
              await h.fill(
                h.field('Instructions'),
                '$marker Replace filter and test under load',
              );
              await h.tap(
                find.widgetWithText(FilledButton, 'Create work order'),
              );
              final jobs = await repository().jobs(assetId: asset);
              expect(jobs, hasLength(1));
              job = jobs.single.id;
              manifest['maintenance_job'] = job;
              save();
              expect(jobs.single.data['service_interval_id'], plan);
              expect(find.text('Schedule work'), findsOneWidget);
              await h.screenshot('planning013-booking');
            },
          );
          await h.step(
            'manager books time duration assignee and deadline through native controls',
            () async {
              if (job == null) throw StateError('No created job');
              await h.select('Assignee', mechanic['name'] as String);
              await pickStart();
              await h.fill(h.field('Estimated duration (minutes)'), '120');
              await h.tap(find.text('Deadline'));
              await h.tap(find.widgetWithText(TextButton, 'OK'));
              await h.fill(
                h.field('Scheduling reason'),
                '$marker Planned shutdown',
              );
              await h.tap(find.widgetWithText(FilledButton, 'Save schedule'));
              final saved = (await planning()).jobs.single;
              expect(saved.start, isNotNull);
              expect(saved.minutes, 120);
              expect(saved.assignee, mechanic['id']);
              expect(saved.dueDate, isNotNull);
              expect(saved.status, 'assigned');
              await h.go('/maintenance/planning?assetId=$asset');
              await h.tap(find.byKey(const ValueKey('planning-collection')));
              await h.tap(find.text('Schedule'));
              await h.tap(find.widgetWithText(ChoiceChip, 'Month'));
              await h.reveal(find.text('$marker Generator service'));
              await h.screenshot('planning013-month');
            },
          );
          await h.step(
            'server refuses overlap then accepts an explicit documented decision',
            () async {
              second = const Uuid().v4();
              manifest['second_job'] = second;
              save();
              await repository().create(second!, {
                'asset_id': asset,
                'title': '$marker Pump inspection',
              });
              await h.go('/maintenance/planning?assetId=$asset&jobId=$second');
              await h.select('Assignee', mechanic['name'] as String);
              await pickStart();
              await h.fill(
                h.field('Scheduling reason'),
                '$marker Parallel visual check during generator cool-down',
              );
              await h.tap(find.widgetWithText(FilledButton, 'Save schedule'));
              expect(
                (await planning()).jobs.firstWhere((j) => j.id == second).start,
                isNull,
              );
              expect(
                find.text(
                  'This booking overlaps another job for the assignee or asset. Change the time or explicitly allow the overlap.',
                ),
                findsOneWidget,
              );
              await h.tap(find.byType(CheckboxListTile));
              await h.tap(find.widgetWithText(FilledButton, 'Save schedule'));
              expect((await planning()).jobs.every((j) => j.conflict), isTrue);
            },
          );
          await h.step(
            'rescheduling and returning work to the queue preserve jobs and remove conflicts',
            () async {
              await h.go('/maintenance/planning?assetId=$asset');
              await h.go('/maintenance/planning?assetId=$asset&jobId=$second');
              await h.tap(find.text('Return to unscheduled'));
              await h.select('Assignee', 'Unassigned');
              await h.fill(
                h.field('Scheduling reason'),
                '$marker Wait for an independent inspection slot',
              );
              await h.tap(find.widgetWithText(FilledButton, 'Save schedule'));
              expect(
                (await planning()).jobs
                    .firstWhere((j) => j.id == second)
                    .unscheduled,
                isTrue,
              );
              expect((await planning()).jobs.any((j) => j.conflict), isFalse);
              await h.go('/maintenance/planning?assetId=$asset&jobId=$job');
              await h.fill(h.field('Estimated duration (minutes)'), '90');
              await h.fill(
                h.field('Scheduling reason'),
                '$marker Revised estimate after preparation',
              );
              await h.tap(find.widgetWithText(FilledButton, 'Save schedule'));
              expect(
                (await planning()).jobs.firstWhere((j) => j.id == job).minutes,
                90,
              );
            },
          );
          await h.step(
            'assigned mechanic discovers today and completes the existing report workflow',
            () async {
              await h.login('client_mechanic@vortice.dev');
              await h.go('/maintenance/planning?assetId=$asset');
              expect(find.text('Plan work'), findsNothing);
              await h.tap(find.text('Continue work'));
              await h.tap(find.widgetWithText(FilledButton, 'Start work'));
              await h.tap(find.widgetWithText(TextButton, 'Pause'));
              await h.tap(find.text('Continue work report'));
              await h.fill(
                h.field('Findings'),
                '$marker Planned generator service',
              );
              await h.fill(
                h.field('Work performed and results'),
                '$marker Filter replaced and load test passed',
              );
              await h.fill(h.field('Component meter at completion'), '250');
              await h.tap(
                find.widgetWithText(FilledButton, 'Submit for review'),
              );
              expect(
                (await repository().jobs(jobId: job)).single.status,
                'pending_review',
              );
            },
          );
          await h.step(
            'approval advances the original interval and removes completed work from planning',
            () async {
              await h.login('paradise@vortice.dev');
              await h.go('/maintenance/jobs/$job');
              await h.tap(
                find.widgetWithText(FilledButton, 'Approve & complete'),
              );
              await h.tap(find.widgetWithText(FilledButton, 'Confirm'));
              final data = await planning();
              expect(data.jobs.any((j) => j.id == job), isFalse);
              expect(data.plans.single.data['next_due_hours'], 500);
              expect(data.plans.single.hasJob, isFalse);
              await h.go('/maintenance/planning?assetId=$asset');
              await h.tap(find.byKey(const ValueKey('planning-collection')));
              await h.tap(find.text('Service plans'));
              await h.reveal(find.text('Plan service'));
              await h.screenshot('planning013-next-service');
            },
          );
          await h.step(
            'other company cannot discover or schedule the fixture',
            () async {
              await h.login('client@vortice.dev');
              final data = await planning();
              expect(data.jobs, isEmpty);
              expect(data.plans, isEmpty);
              await expectLater(
                h.container.read(planningRepositoryProvider).schedule(
                  second!,
                  2,
                  const Uuid().v4(),
                  {'note': 'Cross-company attempt'},
                ),
                throwsA(isA<Exception>()),
              );
              await h.go('/maintenance/planning?assetId=$asset');
              expect(find.text('$marker Generator service'), findsNothing);
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
