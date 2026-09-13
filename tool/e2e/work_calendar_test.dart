import 'dart:convert';
import 'dart:io';
import 'package:uuid/uuid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/maintenance/planning/maintenance_planning_screen.dart';
import 'package:vortice_app/features/maintenance/planning/planning_repository.dart';
import 'package:vortice_app/features/maintenance/planning/planning_models.dart';
import 'package:vortice_app/features/maintenance/maintenance_repository.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'connected_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'demo calendar dates open the matching work order and retain the month',
    (tester) async {
      await tester.runAsync(() async {
        final h = ConnectedHarness(tester, report: 'next006-work-calendar');
        await h.start();
        try {
          final accounts =
              (jsonDecode(
                        File(
                          'config/next006-fixtures.local.json',
                        ).readAsStringSync(),
                      )['accounts']
                      as List)
                  .cast<Map>();
          final account = accounts.firstWhere(
            (row) => row['purpose'] == 'fleet',
          );
          h.passwords[account['email']] = account['password'];
          await h.login(account['email'] as String);
          final repo = h.container.read(maintenanceRepositoryProvider);
          final profile = await h.container.read(profileProvider.future);
          final workspace = await repo.workspace();
          final asset = const Uuid().v4();
          await repo.setup(const Uuid().v4(), 'asset', asset, 0, {
            'name': 'NEXT006 Calendar hydraulic excavator',
            'asset_type_id': (workspace['asset_types'] as List).first['id'],
          });
          for (final item in [
            (8, 'Hydraulic pump inspection'),
            (11, 'Replace return filter'),
          ]) {
            final id = await repo.create(const Uuid().v4(), {
              'asset_id': asset,
              'title': item.$2,
              'job_type': 'repair',
              'description': 'NEXT006 isolated calendar acceptance',
              'priority': 'normal',
              'assigned_to': profile!.id,
            });
            final created = (await repo.jobs(jobId: id)).single;
            final today = DateTime.now();
            await h.container
                .read(planningRepositoryProvider)
                .schedule(id, created.revision, const Uuid().v4(), {
                  'planned_start': DateTime(
                    today.year,
                    today.month,
                    today.day,
                    item.$1,
                  ).toUtc().toIso8601String(),
                  'estimated_minutes': 90,
                  'assigned_to': profile.id,
                  'priority': 'normal',
                  'note': 'Calendar acceptance fixture',
                  'allow_overlap': false,
                });
          }
          h.container.invalidate(maintenancePlanningProvider);
          await h.go('/maintenance/planning?filter=open');
          await h.tap(find.byKey(const ValueKey('work-focus-all')));
          final data = await h.container.read(
            displayedMaintenancePlanningProvider(null).future,
          );
          final dated = data.jobs
              .where(
                (job) =>
                    !job.completed &&
                    (job.start != null || job.serviceDate != null),
              )
              .toList();
          expect(
            dated,
            isNotEmpty,
            reason:
                'Demo must contain scheduled work for real calendar acceptance',
          );
          final job = dated.first;
          final date = planningDay(job.start ?? job.serviceDate!);
          await h.step(
            'month selects a dated work order and opens its detail',
            () async {
              await h.tap(find.widgetWithText(ChoiceChip, 'Month'));
              var shown = DateTime.now();
              final delta =
                  (date.year - shown.year) * 12 + date.month - shown.month;
              expect(delta.abs(), lessThan(24));
              for (var n = 0; n < delta.abs(); n++) {
                await h.tap(find.byTooltip(delta < 0 ? 'Previous' : 'Next'));
              }
              final cell = find.byKey(
                ValueKey('calendar-day-${date.toIso8601String()}'),
              );
              await h.tap(cell);
              await h.screenshot('calendar-month-demo');
              final card = find.byKey(
                ValueKey('calendar-work-${job.id}-${date.day}'),
              );
              await h.reveal(card);
              await h.screenshot('calendar-day-demo');
              await h.tap(
                find.descendant(of: card, matching: find.text(job.title)),
              );
              expect(find.text(job.title), findsWidgets);
              await h.screenshot('calendar-opened-work');
              await h.tap(find.byTooltip('Back'));
              expect(
                tester
                    .widget<ChoiceChip>(
                      find.widgetWithText(ChoiceChip, 'Month'),
                    )
                    .selected,
                isTrue,
              );
            },
          );
          await h.step(
            'week headings and narrow large-text month remain readable',
            () async {
              await h.tap(find.widgetWithText(ChoiceChip, 'Week'));
              await h.reveal(find.text(job.title));
              await h.screenshot('calendar-week-demo');
              tester.view.physicalSize = const Size(320, 844);
              tester.platformDispatcher.textScaleFactorTestValue = 2;
              await h.tap(find.widgetWithText(ChoiceChip, 'Month'));
              await h.reveal(find.byType(PlanningMonth));
              await h.screenshot('calendar-month-demo-large');
              await h.reveal(find.text(job.title));
              await h.screenshot('calendar-agenda-demo-large');
              expect(tester.takeException(), isNull);
            },
          );
          expect(h.issues, isEmpty);
        } finally {
          tester.platformDispatcher.clearTextScaleFactorTestValue();
          await h.close();
        }
      });
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
