import 'dart:async';
import 'package:flutter/material.dart';
import 'package:vortice_app/core/app_dropdown_field.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/sync/field_work_provider.dart';
import 'package:vortice_app/sync/field_work_queue.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vortice_app/features/maintenance/planning/maintenance_planning_screen.dart';
import 'package:vortice_app/features/maintenance/planning/planning_models.dart';
import 'package:vortice_app/features/maintenance/planning/planning_repository.dart';
import 'package:vortice_app/features/maintenance/planning/planning_service_repository.dart';
import 'package:vortice_app/features/work_orders/work_order_provider.dart';
import 'package:vortice_app/models/profile.dart';
import 'package:vortice_app/models/work_order.dart';
import 'package:vortice_app/models/work_order_assignment.dart';
import '../fleet/fleet_test_support.dart'
    show captureFleet, loadFleetScreenshotFonts;
import 'maintenance_screen_test.dart' show pumpMaintenance, FixtureMaintenance;
import 'planning_test.dart' show chooseView, applyFilters;
import 'planning_test.dart'
    show
        booking,
        FixturePlanning,
        FixturePlanningServices,
        showPlanning,
        reveal;

Future<void> chooseFilter(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('Search & filters'));
  await tester.pumpAndSettle();
  final picker = find.byWidgetPredicate(
    (w) =>
        w is AppDropdownField<String> && w.key.toString().contains('filter-'),
  );
  await tester.scrollUntilVisible(
    picker,
    250,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.tap(picker);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
  await applyFilters(tester);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(loadFleetScreenshotFonts);
  testWidgets(
    'photo retry updates keep Work readable without another server read',
    (tester) async {
      final updates = StreamController<List<FieldOperation>>();
      addTearDown(updates.close);
      final fixture = FixturePlanning(
        PlanningData(jobs: [booking('offline')], plans: []),
      );
      await pumpMaintenance(
        tester,
        const MaintenancePlanningScreen(
          initialFilter: 'open',
          initialView: 'list',
        ),
        FixtureMaintenance(),
        overrides: [
          planningRepositoryProvider.overrideWithValue(fixture),
          fieldOperationsProvider.overrideWith((_) async* {
            yield [];
            yield* updates.stream;
          }),
        ],
      );
      expect(find.text('Service offline'), findsOneWidget);
      final initialReads = fixture.reads;
      for (var attempt = 1; attempt <= 3; attempt++) {
        updates.add([
          FieldOperation(
            id: 'photo',
            kind: 'upload',
            subject: 'offline',
            payload: const {},
            attempts: attempt,
            error: 'Offline',
          ),
        ]);
        await tester.pumpAndSettle();
        expect(find.text('Service offline'), findsOneWidget);
        expect(
          fixture.reads,
          initialReads,
          reason: 'An upload retry must not restart hosted Work reads',
        );
      }
      updates.add([
        const FieldOperation(
          id: 'start',
          kind: 'apply_maintenance_field_action',
          subject: 'offline',
          payload: {
            'p_revision': 2,
            'p_action': 'start',
            'p_data': {'_actor': 'mechanic'},
            'p_recorded_at': '2026-09-12T12:00:00Z',
          },
        ),
      ]);
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MaintenancePlanningScreen)),
      );
      expect(
        (await container.read(
          displayedMaintenancePlanningProvider(null).future,
        )).jobs.single.status,
        'in_progress',
      );
      expect(fixture.reads, initialReads);
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();
      expect(fixture.reads, initialReads + 1);
    },
  );
  test('saved filters agree on active, review, completed and blocked work', () {
    final now = DateTime(2026, 9, 12);
    final completed = booking('done', status: 'closed', due: '2026-09-01');
    final review = booking('review', status: 'pending_review');
    final parts = PlanningJob({
      ...booking('parts', status: 'on_hold').data,
      'blocked_category': 'parts',
    });
    final people = PlanningJob({
      ...booking('people', status: 'on_hold').data,
      'blocked_category': 'people',
    });
    final other = PlanningJob({
      ...booking('external', status: 'on_hold').data,
      'blocked_category': 'external',
    });
    expect(completed.matchesFilter('completed', 'mechanic', now), isTrue);
    expect(completed.overdue(now), isFalse);
    for (final filter in [
      'open',
      'mine',
      'overdue',
      'unassigned',
      'unscheduled',
    ]) {
      expect(
        completed.matchesFilter(filter, 'mechanic', now),
        isFalse,
        reason: filter,
      );
    }
    expect(review.matchesFilter('review', 'mechanic', now), isTrue);
    expect(review.matchesFilter('unscheduled', 'mechanic', now), isFalse);
    expect(parts.matchesFilter('parts', 'mechanic', now), isTrue);
    expect(people.matchesFilter('people', 'mechanic', now), isTrue);
    expect(other.matchesFilter('blocked', 'mechanic', now), isTrue);
    expect(parts.matchesFilter('blocked', 'mechanic', now), isFalse);
    expect(
      booking(
        'someone',
        assignee: 'other',
      ).matchesFilter('mine', 'mechanic', now),
      isFalse,
    );
    expect(
      booking(
        'none',
        assignee: null,
      ).matchesFilter('unassigned', 'mechanic', now),
      isTrue,
    );
    expect(
      PlanningJob({
        ...booking('secondary', assignee: 'primary').data,
        'assigned_to_me': true,
      }).matchesFilter('mine', 'mechanic', now),
      isTrue,
    );
  });

  test(
    'search includes component, worker, status and translated work type',
    () {
      final job = PlanningJob({
        ...booking('inspect', status: 'pending_review').data,
        'component_name': 'Port hydraulic pump',
        'job_type': 'inspection',
      });
      for (final query in [
        'hydraulic',
        'alex',
        'awaiting review',
        'inspection',
        'harbour',
      ]) {
        expect(job.matchesSearch(query, false), isTrue, reason: query);
      }
      expect(job.matchesSearch('inspección', true), isTrue);
      expect(job.matchesSearch('unknown', false), isFalse);
    },
  );

  testWidgets('List exposes completed work without schedule actions', (
    tester,
  ) async {
    await showPlanning(
      tester,
      const MaintenancePlanningScreen(
        initialFilter: 'open',
        initialView: 'list',
      ),
      FixturePlanning(
        PlanningData(
          jobs: [
            booking('open'),
            booking('finished', status: 'closed'),
          ],
          plans: [],
        ),
      ),
    );
    await chooseFilter(tester, 'Completed');
    await reveal(tester, find.text('Service finished'));
    expect(find.text('Service open'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Schedule'), findsNothing);
    await reveal(tester, find.widgetWithText(FilledButton, 'Open work'));
    expect(find.widgetWithText(FilledButton, 'Open work'), findsOneWidget);
  });

  testWidgets(
    'month selects a day without leaving the calendar and retains unscheduled access',
    (tester) async {
      final now = DateTime.now();
      final later = DateTime(now.year, now.month, now.day == 28 ? 27 : 28, 10);
      await showPlanning(
        tester,
        const MaintenancePlanningScreen(),
        FixturePlanning(
          PlanningData(
            jobs: [
              booking('later in month', start: later),
              booking('not yet booked'),
            ],
            plans: [],
          ),
        ),
      );
      expect(find.byType(PlanningMonth), findsOneWidget);
      await tester.pumpAndSettle();
      final date = DateTime(later.year, later.month, later.day);
      final day = find.byKey(
        ValueKey('calendar-day-${date.toIso8601String()}'),
      );
      await reveal(tester, day);
      await tester.tap(day);
      await tester.pumpAndSettle();
      expect(find.byType(PlanningMonth), findsOneWidget);
      await reveal(tester, find.text('Service later in month'));
      expect(find.text('Service later in month'), findsOneWidget);
      expect(find.text('Service not yet booked'), findsNothing);
      await captureFleet(tester, 'work-hub-month-agenda');
      await tester.drag(find.byType(ListView).first, const Offset(0, 1600));
      await tester.pumpAndSettle();
      await reveal(tester, find.widgetWithText(ActionChip, 'Unscheduled · 1'));
      await tester.tap(find.widgetWithText(ActionChip, 'Unscheduled · 1'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Service not yet booked'));
      expect(find.text('Service later in month'), findsNothing);
    },
  );

  testWidgets('detail return retains selected day and Mine filter', (
    tester,
  ) async {
    final now = DateTime.now();
    await showPlanning(
      tester,
      const MaintenancePlanningScreen(
        initialFilter: 'mine',
        initialView: 'list',
      ),
      FixturePlanning(
        PlanningData(
          jobs: [
            booking(
              'my work',
              start: DateTime(now.year, now.month, now.day + 1, 8),
            ),
            booking(
              'someone else',
              start: DateTime(now.year, now.month, now.day + 1, 8),
              assignee: 'other',
            ),
          ],
          plans: [],
        ),
      ),
    );
    await chooseView(tester, 'Day');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Next'));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Service my work'));
    await tester.tap(find.text('Service my work'));
    await tester.pumpAndSettle();
    expect(find.text('Job saved'), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator).last).pop();
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Service my work'));
    expect(find.text('Service someone else'), findsNothing);
    expect(find.text('Service my work'), findsOneWidget);
  });

  testWidgets('status, type and component filters preserve matching work', (
    tester,
  ) async {
    final pump = PlanningJob({
      ...booking('pump', status: 'pending_review').data,
      'component_name': 'Port pump',
      'job_type': 'inspection',
    });
    await showPlanning(
      tester,
      const MaintenancePlanningScreen(
        initialFilter: 'open',
        initialView: 'list',
      ),
      FixturePlanning(PlanningData(jobs: [pump, booking('repair')], plans: [])),
    );
    await tester.tap(find.byTooltip('Search & filters'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'port pump');
    await tester.pumpAndSettle();
    await applyFilters(tester);
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Service pump'));
    expect(find.text('Service repair'), findsNothing);
  });

  testWidgets('completed provider orders keep their authorized billing route', (
    tester,
  ) async {
    await pumpMaintenance(
      tester,
      const MaintenancePlanningScreen(
        initialFilter: 'completed',
        initialView: 'list',
      ),
      FixtureMaintenance(),
      role: UserRole.owner,
      overrides: [
        planningServiceRepositoryProvider.overrideWithValue(
          const FixturePlanningServices(
            PlanningServiceData(assetNames: {'asset': 'Harbour generator'}),
          ),
        ),

        planningRepositoryProvider.overrideWithValue(
          FixturePlanning(PlanningData(jobs: [], plans: [])),
        ),
        workOrdersProvider.overrideWith(
          (_) async => [
            const WorkOrder(
              id: 'service',
              assetId: 'asset',
              clientId: 'company',
              createdBy: 'owner',
              title: 'Completed service visit',
              jobType: WorkOrderJobType.inspection,
              status: WorkOrderStatus.invoiced,
            ),
          ],
        ),
        assetNameProvider(
          'asset',
        ).overrideWith((_) async => 'Harbour generator'),
        currentUserAssignedToWorkOrderProvider(
          'service',
        ).overrideWith((_) async => false),
        workOrderAssignmentsProvider('service').overrideWith((_) async => []),
      ],
    );
    await reveal(tester, find.text('Completed service visit'));
    expect(find.textContaining('Invoiced'), findsOneWidget);
    await reveal(tester, find.text('Open work order'));
    await tester.tap(find.text('Open work order'));
    await tester.pumpAndSettle();
    expect(find.text('Work order service'), findsOneWidget);
  });

  testWidgets(
    'Mine includes a secondary provider assignee without rereading the order',
    (tester) async {
      var assignmentChecks = 0;
      var detailReads = 0;
      await pumpMaintenance(
        tester,
        const MaintenancePlanningScreen(
          initialFilter: 'mine',
          initialView: 'list',
        ),
        FixtureMaintenance(),
        role: UserRole.employee,
        overrides: [
          planningServiceRepositoryProvider.overrideWithValue(
            const FixturePlanningServices(
              PlanningServiceData(
                assetNames: {'asset': 'Harbour generator'},
                componentNames: {'engine': 'Port hydraulic pump'},
                componentAssets: {'engine': 'asset'},
                workerNames: {
                  'lead': 'Lead mechanic',
                  'mechanic': 'Alex Morgan',
                },
                workersByOrder: {
                  'secondary': {'mechanic'},
                },
              ),
            ),
          ),

          planningRepositoryProvider.overrideWithValue(
            FixturePlanning(PlanningData(jobs: [], plans: [])),
          ),
          workOrdersProvider.overrideWith(
            (_) async => [
              const WorkOrder(
                id: 'secondary',
                assetId: 'asset',
                engineId: 'engine',
                clientId: 'company',
                createdBy: 'owner',
                title: 'Assist the lead mechanic',
                assignedTo: 'lead',
                jobType: WorkOrderJobType.repair,
                status: WorkOrderStatus.assigned,
              ),
            ],
          ),
          assetNameProvider(
            'asset',
          ).overrideWith((_) async => 'Harbour generator'),
          profileNameProvider(
            'lead',
          ).overrideWith((_) async => 'Lead mechanic'),
          profileNameProvider(
            'mechanic',
          ).overrideWith((_) async => 'Alex Morgan'),
          workOrderAssignmentsProvider('secondary').overrideWith(
            (_) async => [
              const WorkOrderAssignment(
                id: 'assignment',
                workOrderId: 'secondary',
                profileId: 'mechanic',
              ),
            ],
          ),
          assetEnginesProvider('asset').overrideWith(
            (_) async => [
              {'id': 'engine', 'label': 'Port hydraulic pump'},
            ],
          ),
          currentUserAssignedToWorkOrderProvider('secondary').overrideWith((
            _,
          ) async {
            assignmentChecks++;
            return false;
          }),
          workOrderByIdProvider('secondary').overrideWith((_) async {
            detailReads++;
            return null;
          }),
        ],
      );
      await reveal(tester, find.text('Assist the lead mechanic'));
      expect(find.text('Assist the lead mechanic'), findsOneWidget);
      expect(find.textContaining('Port hydraulic pump'), findsOneWidget);
      expect(assignmentChecks, 0);
      expect(detailReads, 0);
    },
  );

  testWidgets('Mine retains legacy primary assignment without detail reads', (
    tester,
  ) async {
    var assignmentChecks = 0;
    var detailReads = 0;
    await pumpMaintenance(
      tester,
      const MaintenancePlanningScreen(
        initialFilter: 'mine',
        initialView: 'list',
      ),
      FixtureMaintenance(),
      role: UserRole.employee,
      overrides: [
        planningServiceRepositoryProvider.overrideWithValue(
          const FixturePlanningServices(
            PlanningServiceData(
              assetNames: {'asset': 'Harbour generator'},
              workerNames: {'mechanic': 'Alex Morgan'},
            ),
          ),
        ),

        planningRepositoryProvider.overrideWithValue(
          FixturePlanning(PlanningData(jobs: [], plans: [])),
        ),
        workOrdersProvider.overrideWith(
          (_) async => [
            const WorkOrder(
              id: 'legacy',
              assetId: 'asset',
              clientId: 'company',
              createdBy: 'owner',
              title: 'Legacy primary assignment',
              assignedTo: 'mechanic',
              jobType: WorkOrderJobType.repair,
              status: WorkOrderStatus.assigned,
            ),
            const WorkOrder(
              id: 'unassigned',
              assetId: 'asset',
              clientId: 'company',
              createdBy: 'owner',
              title: 'Unassigned provider work',
              jobType: WorkOrderJobType.repair,
              status: WorkOrderStatus.draft,
            ),
          ],
        ),
        assetNameProvider(
          'asset',
        ).overrideWith((_) async => 'Harbour generator'),
        profileNameProvider(
          'mechanic',
        ).overrideWith((_) async => 'Alex Morgan'),
        for (final id in ['legacy', 'unassigned']) ...[
          workOrderAssignmentsProvider(id).overrideWith((_) async => []),
          currentUserAssignedToWorkOrderProvider(id).overrideWith((_) async {
            assignmentChecks++;
            return false;
          }),
          workOrderByIdProvider(id).overrideWith((_) async {
            detailReads++;
            return null;
          }),
        ],
      ],
    );
    await reveal(tester, find.text('Legacy primary assignment'));
    expect(find.text('Legacy primary assignment'), findsOneWidget);
    expect(find.text('Unassigned provider work'), findsNothing);
    expect(assignmentChecks, 0);
    expect(detailReads, 0);
  });

  testWidgets(
    'Spanish large text filters and month agenda render without overflow',
    (tester) async {
      final now = DateTime.now();
      await showPlanning(
        tester,
        const MaintenancePlanningScreen(
          initialFilter: 'review',
          initialView: 'list',
        ),
        FixturePlanning(
          PlanningData(
            jobs: [
              booking(
                'revisión del generador de emergencia',
                status: 'pending_review',
                start: now,
              ),
            ],
            plans: [],
          ),
        ),
        es: true,
        light: true,
        width: 360,
        scale: 2,
      );
      await captureFleet(tester, 'work-hub-review-es-large');
      await reveal(
        tester,
        find.text('Service revisión del generador de emergencia'),
      );
      await captureFleet(tester, 'work-hub-review-es-large-work');
      expect(tester.takeException(), isNull);
    },
  );
}
