import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vortice_app/core/app_navigation.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/maintenance/planning/planning_models.dart';
import 'package:vortice_app/features/maintenance/planning/planning_repository.dart';
import 'package:vortice_app/features/maintenance/planning/planning_service_repository.dart';
import 'package:vortice_app/features/maintenance/planning/maintenance_planning_screen.dart';
import 'package:vortice_app/features/maintenance/planning/schedule_job_screen.dart';
import 'package:vortice_app/models/profile.dart';
import 'package:vortice_app/models/work_order.dart';
import 'package:vortice_app/features/work_orders/work_order_provider.dart';
import 'package:vortice_app/sync/online_action_gate.dart';
import '../fleet/fleet_test_support.dart';
import 'maintenance_screen_test.dart' show pumpMaintenance, FixtureMaintenance;

PlanningJob booking(
  String id, {
  DateTime? start,
  int minutes = 60,
  String? assignee = 'mechanic',
  String asset = 'asset',
  String status = 'assigned',
  bool manager = true,
  String? due,
}) => PlanningJob({
  'id': id,
  'asset_id': asset,
  'asset_name': 'Harbour generator',
  'title': 'Service $id',
  'assigned_to': assignee,
  'assignee_name': assignee == null ? '' : 'Alex Morgan',
  'planned_start': start?.toUtc().toIso8601String(),
  'estimated_minutes': start == null ? null : minutes,
  'revision': 2,
  'priority': 'high',
  'status': status,
  'can_manage': manager,
  'due_date': due,
});

class FixturePlanningServices implements PlanningServiceRepository {
  const FixturePlanningServices(this.data);
  final PlanningServiceData data;
  @override
  Future<PlanningServiceData> load(
    List<WorkOrder> orders, {
    required String accountId,
  }) async => data;
}

class FixturePlanning implements PlanningRepository {
  FixturePlanning(this.data);
  PlanningData data;
  Object? readError, writeError;
  int reads = 0;
  final writes = <(String, int, String, Map<String, dynamic>)>[];
  @override
  Future<PlanningData> load(String? assetId) async {
    reads++;
    if (readError != null) throw readError!;
    return data;
  }

  @override
  Future<void> schedule(
    String jobId,
    int revision,
    String operationId,
    Map<String, dynamic> data,
  ) async {
    writes.add((jobId, revision, operationId, data));
    final failure = writeError;
    writeError = null;
    if (failure != null) throw failure;
  }
}

// Load the real theme's colors and resolve only test font families for captures.
ThemeData planningCaptureTheme(ThemeData theme) => theme.copyWith(
  textTheme: theme.textTheme.apply(fontFamily: 'Roboto'),
  primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: 'Roboto'),
  appBarTheme: theme.appBarTheme.copyWith(
    titleTextStyle: theme.appBarTheme.titleTextStyle?.copyWith(
      fontFamily: 'Roboto',
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: theme.filledButtonTheme.style?.copyWith(
      textStyle: WidgetStateProperty.resolveWith(
        (states) => theme.filledButtonTheme.style?.textStyle
            ?.resolve(states)
            ?.copyWith(fontFamily: 'Roboto'),
      ),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: theme.textButtonTheme.style?.copyWith(
      textStyle: WidgetStateProperty.resolveWith(
        (states) => theme.textButtonTheme.style?.textStyle
            ?.resolve(states)
            ?.copyWith(fontFamily: 'Roboto'),
      ),
    ),
  ),
);

Future<void> showPlanning(
  WidgetTester tester,
  Widget screen,
  FixturePlanning fixture, {
  bool es = false,
  bool light = false,
  double width = 390,
  double scale = 1,
  UserRole role = UserRole.clientAdmin,
}) async {
  final home = screen is ScheduleJobScreen
      ? Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => screen),
              ),
              child: const Text('Test schedule'),
            ),
          ),
        )
      : screen;
  await pumpMaintenance(
    tester,
    Theme(
      data: planningCaptureTheme(
        light ? AppTheme.lightTheme : AppTheme.darkTheme,
      ),
      child: home,
    ),
    FixtureMaintenance(),
    es: es,
    width: width,
    scale: scale,
    role: role,
    overrides: [
      planningRepositoryProvider.overrideWithValue(fixture),
      onlineActionGateProvider.overrideWith(
        (ref) => OnlineActionGate(
          account: 'fixture',
          currentAccount: () => 'fixture',
          probe: () async {},
        ),
      ),
    ],
  );
  if (screen is ScheduleJobScreen) {
    await tester.tap(find.text('Test schedule'));
    await tester.pumpAndSettle();
  }
}

Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Future<void> chooseView(WidgetTester tester, String label) async {
  await reveal(tester, find.byKey(const ValueKey('planning-collection')));
  await tester.tap(find.byKey(const ValueKey('planning-collection')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> showUnscheduled(WidgetTester tester, {bool es = false}) async {
  final chip = find.byWidgetPredicate(
    (w) =>
        w is ActionChip &&
        w.label is Text &&
        ((w.label as Text).data ?? '').startsWith(
          es ? 'Sin programar' : 'Unscheduled',
        ),
  );
  await reveal(tester, chip);
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

Future<void> applyFilters(WidgetTester tester, {bool es = false}) async {
  final button = find.text(
    es ? 'Mostrar órdenes de trabajo' : 'Show work orders',
  );
  await tester.scrollUntilVisible(
    button,
    250,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(loadFleetScreenshotFonts);

  test('a deadline never creates a booking', () {
    final job = booking('one', due: '2026-09-10');
    expect(job.start, isNull);
    expect(job.overdue(DateTime(2026, 9, 10)), isFalse);
    expect(job.overdue(DateTime(2026, 9, 11)), isTrue);
  });
  test(
    'half-open bookings allow back-to-back jobs and flag shared resources',
    () {
      final a = booking('a', start: DateTime(2026, 9, 7, 8));
      List<PlanningJob> conflicts(
        DateTime start, {
        String asset = 'different',
        String? assignee = 'mechanic',
      }) => bookingConflicts(
        [a],
        jobId: 'b',
        assetId: asset,
        assignee: assignee,
        start: start,
        minutes: 60,
      );
      expect(conflicts(DateTime(2026, 9, 7, 9)), isEmpty);
      expect(conflicts(DateTime(2026, 9, 7, 8, 30)), hasLength(1));
      expect(
        conflicts(DateTime(2026, 9, 7, 8, 30), asset: 'asset', assignee: null),
        hasLength(1),
      );
      expect(
        conflicts(DateTime(2026, 9, 7, 8, 30), assignee: 'other'),
        isEmpty,
      );
    },
  );
  test('unassigned jobs on different assets do not collide', () {
    expect(
      bookingConflicts(
        [booking('a', start: DateTime(2026, 9, 7, 8), assignee: null)],
        jobId: 'b',
        assetId: 'other',
        assignee: null,
        start: DateTime(2026, 9, 7, 8),
        minutes: 60,
      ),
      isEmpty,
    );
  });
  test('closed and review work do not block bookings', () {
    expect(
      bookingConflicts(
        [
          for (final status in ['closed', 'pending_review'])
            booking(status, start: DateTime(2026, 9, 7, 8), status: status),
        ],
        jobId: 'b',
        assetId: 'asset',
        assignee: 'mechanic',
        start: DateTime(2026, 9, 7, 8),
        minutes: 60,
      ),
      isEmpty,
    );
  });
  test('weekly hours clip overnight and week boundary bookings', () {
    final job = booking(
      'overnight',
      start: DateTime(2026, 9, 6, 23),
      minutes: 180,
    );
    expect(job.hoursBetween(DateTime(2026, 9, 7), DateTime(2026, 9, 14)), 2);
    expect(planningWeek(DateTime(2026, 9, 6)), DateTime(2026, 8, 31));
  });
  test('plan thresholds use the linked component and never invent dates', () {
    final plan = PlanningPlan({
      'id': 'p',
      'asset_id': 'a',
      'engine_id': 'engine',
      'current_hours': 1250,
      'next_due_hours': 1250,
    });
    expect(plan.due, isTrue);
    expect(plan.needsSetup, isFalse);
    expect(
      PlanningPlan({'id': 'p', 'asset_id': 'a', 'engine_id': null}).needsSetup,
      isTrue,
    );
  });
  test(
    'provider date-only work is visible without pretending to have booked hours',
    () {
      final job = PlanningJob({
        'id': 'service',
        'asset_id': 'a',
        'status': 'assigned',
        'provider_service': true,
        'service_date': '2026-09-07',
      });
      expect(job.inPeriod(DateTime(2026, 9, 7), DateTime(2026, 9, 8)), isTrue);
      expect(job.unscheduled, isFalse);
      expect(job.hoursBetween(DateTime(2026, 9, 7), DateTime(2026, 9, 8)), 0);
      expect(job.schedulable, isFalse);
    },
  );
  test('planning stays separate from general work navigation', () {
    final items = primaryDestinations(UserRole.clientAdmin);
    expect(items[2].en, 'Work orders');
    expect(selectedDestination(items, '/maintenance/planning'), 2);
    expect(
      selectedDestination(items, '/maintenance/jobs/job'),
      items.indexWhere((item) => item.en == 'Work orders'),
    );
    expect(primaryDestinations(UserRole.clientMechanic)[2].en, 'Work orders');
  });

  testWidgets('manager sees forward week and opens unscheduled booking', (
    tester,
  ) async {
    final fixture = FixturePlanning(
      PlanningData(jobs: [booking('unplanned')], plans: []),
    );
    await showPlanning(tester, const MaintenancePlanningScreen(), fixture);
    expect(find.text('Work orders').first, findsOneWidget);
    await showUnscheduled(tester);
    await reveal(tester, find.text('Schedule'));
    await tester.tap(find.text('Schedule'));
    await tester.pumpAndSettle();
    expect(find.text('Schedule work'), findsOneWidget);
    expect(find.text('Booked start'), findsOneWidget);
  });
  testWidgets(
    'booked work opens first and collection changes retain calendar view',
    (tester) async {
      final fixture = FixturePlanning(
        PlanningData(
          jobs: [booking('booked', start: DateTime.now())],
          plans: [],
        ),
      );
      await showPlanning(tester, const MaintenancePlanningScreen(), fixture);
      await reveal(tester, find.text('Service booked'));
      expect(find.byTooltip('Reschedule'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Reschedule'), findsNothing);
      await tester.drag(find.byType(ListView).first, const Offset(0, 800));
      await tester.pumpAndSettle();
      await chooseView(tester, 'Day');
      await tester.pumpAndSettle();
      await showUnscheduled(tester);
      expect(find.text('Day'), findsOneWidget);
      await reveal(tester, find.text('Back to day'));
      await tester.tap(find.text('Back to day'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Service booked'));
      expect(find.text('Service booked'), findsOneWidget);
    },
  );

  testWidgets(
    'large text collections and reopened search preserve readable filters',
    (tester) async {
      final fixture = FixturePlanning(
        PlanningData(jobs: [booking('pump')], plans: []),
      );
      await showPlanning(
        tester,
        const MaintenancePlanningScreen(),
        fixture,
        es: true,
        width: 360,
        scale: 2,
      );
      await tester.tap(find.byTooltip('Buscar y filtrar'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'pump');
      await applyFilters(tester, es: true);
      await tester.tap(find.byTooltip('Buscar y filtrar'));
      await tester.pumpAndSettle();
      expect(find.text('pump'), findsOneWidget);
      await applyFilters(tester, es: true);
      await showUnscheduled(tester, es: true);
      await reveal(tester, find.text('Programar'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'changing the requested booking reuses the planner with fresh work',
    (tester) async {
      final selected = ValueNotifier<String?>(null);
      addTearDown(selected.dispose);
      final fixture = FixturePlanning(
        PlanningData(jobs: [booking('first')], plans: []),
      );
      await showPlanning(
        tester,
        ValueListenableBuilder<String?>(
          valueListenable: selected,
          builder: (_, id, child) => MaintenancePlanningScreen(jobId: id),
        ),
        fixture,
      );
      selected.value = 'first';
      await tester.pumpAndSettle();
      expect(find.text('Schedule work'), findsOneWidget);
      expect(find.text('Service first'), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      fixture.data = PlanningData(
        jobs: [booking('first'), booking('second')],
        plans: [],
      );
      selected.value = 'second';
      await tester.pumpAndSettle();
      expect(find.text('Schedule work'), findsOneWidget);
      expect(find.text('Service second'), findsOneWidget);
    },
  );
  testWidgets('mechanic opens today without planning controls', (tester) async {
    final now = DateTime.now();
    final fixture = FixturePlanning(
      PlanningData(
        jobs: [
          booking(
            'today',
            start: DateTime(now.year, now.month, now.day, 8),
            manager: false,
          ),
        ],
        plans: [],
      ),
    );
    await showPlanning(
      tester,
      const MaintenancePlanningScreen(),
      fixture,
      role: UserRole.clientMechanic,
    );
    expect(find.text('Work orders').first, findsOneWidget);
    expect(find.text('Plan work'), findsNothing);
    expect(find.text('Service plans'), findsNothing);
    await reveal(tester, find.text('Service today'));
    await tester.tap(find.text('Service today'));
    await tester.pumpAndSettle();
    expect(find.text('Job saved'), findsOneWidget);
  });
  testWidgets('read failure stays visible and retry reloads', (tester) async {
    final fixture = FixturePlanning(PlanningData(jobs: [], plans: []))
      ..readError = TimeoutException('offline');
    await showPlanning(tester, const MaintenancePlanningScreen(), fixture);
    expect(
      find.text('Could not load the current plan. Connect and try again.'),
      findsOneWidget,
    );
    final before = fixture.reads;
    fixture.readError = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(fixture.reads, greaterThan(before));
    expect(find.text('Work orders').first, findsOneWidget);
  });
  testWidgets('uncertain scheduling retry preserves exact identity and input', (
    tester,
  ) async {
    final job = booking('retry');
    final fixture = FixturePlanning(PlanningData(jobs: [job], plans: []))
      ..writeError = TimeoutException('lost response');
    await showPlanning(
      tester,
      ScheduleJobScreen(job: job, jobs: [job]),
      fixture,
    );
    await reveal(
      tester,
      find.widgetWithText(TextFormField, 'Scheduling reason'),
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Scheduling reason'),
      'Waiting for shutdown window',
    );
    await reveal(tester, find.text('Save schedule'));
    await tester.tap(find.text('Save schedule'));
    await tester.pumpAndSettle();
    expect(fixture.writes, hasLength(1));
    expect(
      tester
          .widget<TextFormField>(
            find.widgetWithText(TextFormField, 'Scheduling reason'),
          )
          .enabled,
      isFalse,
    );
    await reveal(tester, find.text('Retry same save'));
    await tester.tap(find.text('Retry same save'));
    await tester.pumpAndSettle();
    expect(fixture.writes, hasLength(2));
    expect(fixture.writes[0].$3, fixture.writes[1].$3);
    expect(fixture.writes[0].$4, fixture.writes[1].$4);
    expect(fixture.writes[0].$4['planned_start'], isNull);
    expect(fixture.writes[0].$4['estimated_minutes'], isNull);
  });
  testWidgets('known server rejection unlocks the form for correction', (
    tester,
  ) async {
    final job = booking('rejected');
    final fixture = FixturePlanning(PlanningData(jobs: [job], plans: []))
      ..writeError = const PostgrestException(
        message: 'This job changed',
        code: '40001',
      );
    await showPlanning(
      tester,
      ScheduleJobScreen(job: job, jobs: [job]),
      fixture,
    );
    await reveal(
      tester,
      find.widgetWithText(TextFormField, 'Scheduling reason'),
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Scheduling reason'),
      'Plan shutdown',
    );
    await reveal(tester, find.text('Save schedule'));
    await tester.tap(find.text('Save schedule'));
    await tester.pumpAndSettle();
    expect(
      find.text('This record changed. Refresh before editing.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextFormField>(
            find.widgetWithText(TextFormField, 'Scheduling reason'),
          )
          .enabled,
      isTrue,
    );
    fixture.data = PlanningData(
      jobs: [
        PlanningJob({...job.data, 'revision': 3}),
      ],
      plans: [],
    );
    await reveal(tester, find.text('Replace fields with the latest schedule'));
    await tester.tap(find.text('Replace fields with the latest schedule'));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Save schedule'));
    await tester.tap(find.text('Save schedule'));
    await tester.pumpAndSettle();
    expect(fixture.writes.last.$2, 3);
  });
  testWidgets('provider scheduled dates reuse authorized service routes', (
    tester,
  ) async {
    final now = DateTime.now();
    final fixture = FixturePlanning(PlanningData(jobs: [], plans: []));
    await pumpMaintenance(
      tester,
      const MaintenancePlanningScreen(),
      FixtureMaintenance(),
      role: UserRole.owner,
      overrides: [
        planningRepositoryProvider.overrideWithValue(fixture),
        planningServiceRepositoryProvider.overrideWithValue(
          const FixturePlanningServices(
            PlanningServiceData(assetNames: {'asset': 'Harbour generator'}),
          ),
        ),
        workOrdersProvider.overrideWith(
          (_) async => [
            WorkOrder(
              id: 'service',
              assetId: 'asset',
              clientId: 'company',
              createdBy: 'owner',
              title: 'Legacy service visit',
              jobType: WorkOrderJobType.repair,
              status: WorkOrderStatus.assigned,
              scheduledDate: now,
            ),
          ],
        ),
        assetNameProvider(
          'asset',
        ).overrideWith((_) async => 'Harbour generator'),
        workOrderAssignmentsProvider('service').overrideWith((_) async => []),
        currentUserAssignedToWorkOrderProvider(
          'service',
        ).overrideWith((_) async => false),
      ],
    );
    await reveal(tester, find.text('Legacy service visit'));
    await tester.tap(find.text('Legacy service visit'));
    await tester.pumpAndSettle();
    expect(find.text('Work order service'), findsOneWidget);
  });
  testWidgets('missing scheduling reason prevents a write', (tester) async {
    final job = booking('empty');
    final fixture = FixturePlanning(PlanningData(jobs: [job], plans: []));
    await showPlanning(
      tester,
      ScheduleJobScreen(job: job, jobs: [job]),
      fixture,
    );
    await reveal(tester, find.text('Save schedule'));
    await tester.tap(find.text('Save schedule'));
    await tester.pumpAndSettle();
    expect(fixture.writes, isEmpty);
    expect(find.text('Explain the change'), findsOneWidget);
  });
  for (final light in [false, true]) {
    for (final spanish in [false, true]) {
      testWidgets(
        'native planning renders ${light ? 'light' : 'dark'} ${spanish ? 'Spanish large text' : 'English'}',
        (tester) async {
          final now = DateTime.now();
          final fixture = FixturePlanning(
            PlanningData(
              jobs: [
                booking(
                  'generator preventive maintenance',
                  start: DateTime(now.year, now.month, now.day, 8),
                  minutes: 180,
                ),
                booking(
                  'pump inspection',
                  start: DateTime(now.year, now.month, now.day + 1, 10),
                  minutes: 90,
                ),
              ],
              plans: [
                PlanningPlan({
                  'id': 'plan',
                  'asset_id': 'asset',
                  'asset_name': 'Harbour generator',
                  'interval_label': '250-hour generator service',
                  'engine_id': 'engine',
                  'component_name': 'Auxiliary generator',
                  'current_hours': 1240,
                  'next_due_hours': 1250,
                  'can_manage': true,
                }),
              ],
            ),
          );
          await showPlanning(
            tester,
            const MaintenancePlanningScreen(),
            fixture,
            es: spanish,
            light: light,
            width: spanish ? 360 : 412,
            scale: spanish ? 1.35 : 1,
          );
          await captureFleet(
            tester,
            'planning-${light ? 'light' : 'dark'}-${spanish ? 'es' : 'en'}',
          );
          expect(find.byType(PlanningMonth), findsOneWidget);
          await reveal(tester, find.byType(PlanningMonth));
          await captureFleet(
            tester,
            'planning-month-${light ? 'light' : 'dark'}-${spanish ? 'es' : 'en'}',
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
