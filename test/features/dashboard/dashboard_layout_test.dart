import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/app_navigation.dart';
import 'package:vortice_app/core/app_shell.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/auth/sign_out_button.dart';
import 'package:vortice_app/features/assets/asset_provider.dart';
import 'package:vortice_app/features/assets/client_team_asset_access.dart';
import 'package:vortice_app/features/checklists/checklist_provider.dart';
import 'package:vortice_app/features/checklists/checklist_assignment_provider.dart';
import 'package:vortice_app/features/clients/client_capability_gate.dart';
import 'package:vortice_app/features/clients/client_context_provider.dart';
import 'package:vortice_app/features/dashboard/dashboard_layout.dart';
import 'package:vortice_app/features/dashboard/client_dashboard_router.dart';
import 'package:vortice_app/features/dashboard/client_dashboard_telemetry.dart';
import 'package:vortice_app/features/dashboard/client_operator_dashboard.dart';
import 'package:vortice_app/features/dashboard/employee_dashboard.dart';
import 'package:vortice_app/features/dashboard/owner_dashboard.dart';
import 'package:vortice_app/features/fleet/fleet_providers.dart';
import 'package:vortice_app/features/invoices/invoice_provider.dart';
import 'package:vortice_app/features/notifications/notification_provider.dart';
import 'package:vortice_app/features/operator/operator_runs_provider.dart';
import 'package:vortice_app/features/reminders/reminder_provider.dart';
import 'package:vortice_app/features/service_reports/service_report_provider.dart';
import 'package:vortice_app/features/telemetry/telemetry_provider.dart';
import 'package:vortice_app/features/telemetry/telemetry_repository.dart';
import 'package:vortice_app/features/work_orders/work_order_provider.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/models/asset.dart';
import 'package:vortice_app/models/checklist_template.dart';
import 'package:vortice_app/models/profile.dart';
import 'package:vortice_app/models/work_order.dart';
import '../fleet/fleet_test_support.dart';

const asset = Asset(
  id: 'pump',
  clientId: 'company',
  assetTypeId: 'pump',
  name: 'Hydraulic Pump 04 — Workshop',
);
const order = WorkOrder(
  id: 'order',
  assetId: 'pump',
  clientId: 'company',
  createdBy: 'owner',
  assignedTo: 'fixture',
  jobType: WorkOrderJobType.repair,
  status: WorkOrderStatus.inProgress,
  title: 'Repair hydraulic pump seal',
);

Future<GoRouter> pumpDashboard(
  WidgetTester tester,
  UserRole role, {
  double width = 390,
  double scale = 1,
  String language = 'en',
  bool telemetry = false,
  bool checks = true,
  Future<List<WorkOrder>> Function()? loadOrders,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final profile = Profile(
    id: 'fixture',
    email: 'fixture@example.invalid',
    fullName: 'Alex Morgan',
    role: role,
  );
  final prefix = roleRoutePrefix(role);
  final nav = GlobalKey<NavigatorState>();
  final router = GoRouter(
    initialLocation: '$prefix/dashboard',
    routes: [
      ShellRoute(
        navigatorKey: nav,
        builder: (_, state, child) =>
            AppShell(location: state.uri.path, navigatorKey: nav, child: child),
        routes: [
          GoRoute(
            path: '$prefix/dashboard',
            builder: (_, __) => telemetry
                ? const ClientDashboardTelemetry()
                : switch (role) {
                    UserRole.owner => const OwnerDashboard(),
                    UserRole.employee => const EmployeeDashboard(),
                    _ => const ClientDashboardRouter(),
                  },
          ),
          for (final route in {
            ...dashboardActions(
              role,
              operationalChecklistsEnabled: true,
            ).map((a) => a.route),
            '/fleet',
            '$prefix/assets',
            '$prefix/notifications',
            '/operator/checklist',
            '/client/assets/pump/checklists/new',
          })
            GoRoute(
              path: route,
              builder: (_, state) =>
                  Scaffold(appBar: AppBar(), body: Text('Opened ${state.uri}')),
            ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  final theme = AppTheme.darkNavyTheme;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        profileProvider.overrideWith((_) async => profile),
        authStatusProvider.overrideWithValue(
          AppAuthStatus(
            isLoading: false,
            isAuthenticated: true,
            profile: profile,
          ),
        ),
        fleetRepositoryProvider.overrideWithValue(FixtureFleetRepository()),
        notificationsProvider.overrideWith((_) async => []),
        assetsProvider.overrideWith((_) async => [asset]),
        visibleAssetsProvider.overrideWith((_) async => [asset]),
        currentClientFleetAssetsProvider.overrideWith((_) async => [asset]),
        checklistTemplatesProvider.overrideWith(
          (_) async => [
            const ChecklistTemplate(
              id: 'template',
              assetTypeId: 'pump',
              name: 'Pump maintenance inspection',
            ),
          ],
        ),
        clientSummaryProvider.overrideWith(
          (_) async => [
            {
              'id': 'company',
              'name': 'North Harbour Services',
              'vessel_count': 3,
              'open_wo_count': 2,
            },
          ],
        ),
        workOrdersProvider.overrideWith(
          (_) => loadOrders?.call() ?? Future.value([order]),
        ),
        invoicesProvider.overrideWith((_) async => []),
        clientServiceReportsProvider.overrideWith((_) async => []),
        clientFlaggedIssuesProvider.overrideWith((_) async => []),
        clientCapabilityGateProvider.overrideWith((_, __) async => checks),
        currentClientIdProvider.overrideWith((_) async => 'company'),
        activeAlertsProvider.overrideWith((_) async => []),
        alertsForAssetProvider.overrideWith((_, __) async => []),
        fleetHealthProvider.overrideWith(
          (_, __) async => const FleetHealth(
            vesselCount: 3,
            activeAlertCount: 0,
            upcomingServiceCount: 2,
          ),
        ),
        remindersProvider.overrideWith((_) async => []),
        clientOperatorAssignedAssetsProvider.overrideWith(
          (_) async => [
            {'id': 'pump', 'name': asset.name},
          ],
        ),
        clientOperatorRecentRunsProvider.overrideWith((_) async => []),
        myChecklistAssignmentsProvider.overrideWith((_) async => []),
      ],
      child: RepaintBoundary(
        key: const Key('fleet-capture'),
        child: MaterialApp.router(
          theme: theme.copyWith(
            textTheme: theme.textTheme.apply(fontFamily: 'Roboto'),
            primaryTextTheme: theme.primaryTextTheme.apply(
              fontFamily: 'Roboto',
            ),
            appBarTheme: theme.appBarTheme.copyWith(
              titleTextStyle: theme.appBarTheme.titleTextStyle?.copyWith(
                fontFamily: 'Roboto',
              ),
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                textStyle: const TextStyle(fontFamily: 'Roboto', fontSize: 14),
              ),
            ),
          ),
          routerConfig: router,
          debugShowCheckedModeBanner: false,
          locale: Locale(language),
          supportedLocales: const [Locale('en'), Locale('es')],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return router;
}

void main() {
  setUpAll(loadFleetScreenshotFonts);
  for (final role in UserRole.values) {
    testWidgets('${role.name} has consistent home landmarks and fault action', (
      tester,
    ) async {
      await pumpDashboard(tester, role);
      await tester.pumpAndSettle();
      expect(find.byType(DashboardAppBar), findsOneWidget);
      expect(find.text('Hi, Alex'), findsOneWidget);
      expect(find.text('Quick actions'), findsOneWidget);
      expect(find.byType(SignOutButton), findsOneWidget);
      expect(tester.getCenter(find.byType(SignOutButton)).dx, greaterThan(330));
      expect(tester.takeException(), isNull);
      if (role == UserRole.owner ||
          role == UserRole.clientMechanic ||
          role == UserRole.clientAdmin) {
        await captureFleet(tester, 'dashboard-${role.name}');
      }
      await tester.tap(find.text('Report a fault'));
      await tester.pumpAndSettle();
      expect(find.text('Opened /fleet/report'), findsOneWidget);
    });
  }
  for (final variant in [
    'owner',
    'employee',
    'operator',
    'mechanic',
    'client',
    'telemetry',
  ]) {
    testWidgets(
      '$variant dashboard handles narrow Spanish large text and scrolling',
      (tester) async {
        final role = switch (variant) {
          'owner' => UserRole.owner,
          'employee' => UserRole.employee,
          'operator' => UserRole.operator,
          'mechanic' => UserRole.clientMechanic,
          _ => UserRole.clientAdmin,
        };
        await pumpDashboard(
          tester,
          role,
          width: 320,
          scale: 1.5,
          language: 'es',
          telemetry: variant == 'telemetry',
        );
        await tester.pumpAndSettle();
        expect(find.text('Inicio'), findsWidgets);
        expect(tester.takeException(), isNull);
        if (variant == 'operator') {
          await captureFleet(tester, 'dashboard-operator-es-large');
        }
        for (var step = 0; step < 6; step++) {
          await tester.drag(find.byType(DashboardList), const Offset(0, -440));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      },
    );
  }
  testWidgets('operator checklist card opens the selected asset', (
    tester,
  ) async {
    await pumpDashboard(tester, UserRole.operator);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text(asset.name),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text(asset.name));
    await tester.pumpAndSettle();
    expect(
      find.text('Opened /operator/checklist?assetId=pump'),
      findsOneWidget,
    );
  });
  testWidgets('mechanic checklist keeps its asset and template context', (
    tester,
  ) async {
    await pumpDashboard(tester, UserRole.clientMechanic);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Pump maintenance inspection'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Pump maintenance inspection'));
    await tester.pumpAndSettle();
    final expected = Uri(
      path: '/client/assets/pump/checklists/new',
      queryParameters: {
        'clientId': 'company',
        'name': asset.name,
        'assetTypeId': 'pump',
        'templateId': 'template',
      },
    );
    expect(find.text('Opened $expected'), findsOneWidget);
  });
  testWidgets('disabled operator checklist never appears as a shortcut', (
    tester,
  ) async {
    await pumpDashboard(tester, UserRole.operator, checks: false);
    await tester.pumpAndSettle();
    expect(find.text('Start checklist'), findsNothing);
    expect(find.text('View assets'), findsOneWidget);
    expect(find.text('Report a fault'), findsOneWidget);
  });
  testWidgets(
    'employee home remains usable while work is loading or unavailable',
    (tester) async {
      final request = Completer<List<WorkOrder>>();
      await pumpDashboard(
        tester,
        UserRole.employee,
        loadOrders: () => request.future,
      );
      expect(find.text('Report a fault'), findsOneWidget);
      expect(find.byType(SignOutButton), findsOneWidget);
      request.completeError(StateError('internal database detail'));
      await tester.pumpAndSettle();
      expect(find.textContaining('internal database detail'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Try again'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Try again'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
