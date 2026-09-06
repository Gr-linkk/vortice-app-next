import 'package:vortice_app/features/dashboard/dashboard_layout.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/app_navigation.dart';
import 'package:vortice_app/core/app_shell.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/more_screen.dart';
import 'package:vortice_app/core/router.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/features/assets/asset_list_screen.dart';
import 'package:vortice_app/features/assets/asset_provider.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/clients/client_capability_gate.dart';
import 'package:vortice_app/features/fleet/fault_report_screen.dart';
import 'package:vortice_app/features/fleet/fleet_providers.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/models/asset.dart';
import 'package:vortice_app/models/profile.dart';
import 'package:vortice_app/core/theme.dart';
import '../features/fleet/fleet_test_support.dart';

Future<GoRouter> pumpUx(
  WidgetTester tester,
  UserRole role, {
  String initial = '/more',
  String language = 'en',
  double scale = 1,
  double width = 390,
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
  final key = GlobalKey<NavigatorState>();
  final prefix = roleRoutePrefix(role);
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      ShellRoute(
        navigatorKey: key,
        builder: (_, state, child) =>
            AppShell(location: state.uri.path, navigatorKey: key, child: child),
        routes: [
          GoRoute(path: '/more', builder: (_, __) => const MoreScreen()),
          GoRoute(
            path: '$prefix/dashboard',
            builder: (_, __) => const Scaffold(body: Text('Home destination')),
          ),
          GoRoute(
            path: '$prefix/assets',
            builder: (_, __) => const AssetListScreen(),
          ),
          GoRoute(
            path: '$prefix/assets/:id',
            builder: (_, state) =>
                Scaffold(body: Text('Asset ${state.pathParameters['id']}')),
          ),
          GoRoute(
            path: '/fleet',
            builder: (_, __) => Builder(
              builder: (ctx) => Scaffold(
                body: TextButton(
                  onPressed: () => ctx.push('/fleet/report'),
                  child: const Text('Report a fault'),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/fleet/report',
            builder: (_, __) => const FaultReportScreen(),
          ),
          for (final destination in toolDestinations(role))
            GoRoute(
              path: destination.route,
              builder: (_, __) =>
                  Scaffold(body: Text('${destination.en} destination')),
            ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authStatusProvider.overrideWithValue(
          AppAuthStatus(
            isLoading: false,
            isAuthenticated: true,
            profile: profile,
          ),
        ),
        profileProvider.overrideWith((_) async => profile),
        clientCapabilityGateProvider.overrideWith((_, __) async => false),
        fleetRepositoryProvider.overrideWithValue(FixtureFleetRepository()),
        visibleAssetsProvider.overrideWith(
          (_) async => [
            const Asset(
              id: 'pump',
              clientId: 'client',
              assetTypeId: 'pump',
              name: 'Hydraulic Pump 04',
              location:
                  'A very long workshop location that needs to wrap on a small phone screen',
            ),
          ],
        ),
        assetAssignedProfilesProvider.overrideWith((_) async => {}),
      ],
      child: RepaintBoundary(
        key: const Key('fleet-capture'),
        child: MaterialApp.router(
          theme: AppTheme.darkNavyTheme.copyWith(
            textTheme: AppTheme.darkNavyTheme.textTheme.apply(
              fontFamily: 'Roboto',
            ),
            primaryTextTheme: AppTheme.darkNavyTheme.primaryTextTheme.apply(
              fontFamily: 'Roboto',
            ),
            appBarTheme: AppTheme.darkNavyTheme.appBarTheme.copyWith(
              titleTextStyle: AppTheme.darkNavyTheme.appBarTheme.titleTextStyle
                  ?.copyWith(fontFamily: 'Roboto'),
            ),
            textButtonTheme: TextButtonThemeData(
              style: AppTheme.darkNavyTheme.textButtonTheme.style?.copyWith(
                textStyle: const WidgetStatePropertyAll(
                  TextStyle(fontFamily: 'Roboto', fontSize: 14),
                ),
              ),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: AppTheme.darkNavyTheme.elevatedButtonTheme.style?.copyWith(
                textStyle: const WidgetStatePropertyAll(
                  TextStyle(fontFamily: 'Roboto', fontSize: 16),
                ),
              ),
            ),
          ),
          debugShowCheckedModeBanner: false,
          routerConfig: router,
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
  await tester.pumpAndSettle();
  return router;
}

void main() {
  setUpAll(loadFleetScreenshotFonts);
  testWidgets(
    'account exposes build information and sign-out can be cancelled',
    (tester) async {
      await pumpUx(tester, UserRole.operator);
      await tester.scrollUntilVisible(
        find.text('Sign out'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Vórtice Next · ${AppConstants.appVersion}'),
        findsOneWidget,
      );
      await captureFleet(tester, 'ux-account-build');
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Sign out?'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'error recovery stays readable without exposing the server exception',
    (tester) async {
      var retries = 0;
      await pumpFleet(
        tester,
        Scaffold(
          body: AppErrorState(
            error: Exception('private-database-table'),
            onRetry: () => retries++,
          ),
        ),
        FixtureFleetRepository(),
        language: 'es',
        textScale: 1.5,
        size: const Size(320, 640),
      );
      expect(find.textContaining('private-database-table'), findsNothing);
      await tester.tap(find.text('Intentar de nuevo'));
      expect(retries, 1);
      expect(tester.takeException(), isNull);
      await captureFleet(tester, 'ux-retry-es-large');
    },
  );
  test('all role destinations exist in the actual application router', () {
    final container = ProviderContainer(
      overrides: [
        authStatusProvider.overrideWithValue(AppAuthStatus.unauthenticated),
      ],
    );
    addTearDown(container.dispose);
    final router = container.read(routerProvider);
    for (final role in UserRole.values) {
      for (final item in [
        ...primaryDestinations(role, operationalChecklistsEnabled: true),
        ...toolDestinations(role),
        ...dashboardActions(role, operationalChecklistsEnabled: true),
        ...dashboardActions(role),
      ]) {
        expect(
          router.configuration.findMatch(Uri.parse(item.route)).isError,
          isFalse,
          reason: '${role.name}: ${item.route}',
        );
      }
    }
  });
  testWidgets('a directly opened fault form has a working back button', (
    tester,
  ) async {
    final router = await pumpUx(
      tester,
      UserRole.operator,
      initial: '/fleet/report',
    );
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/fleet');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'direct form discard returns to faults without a previous route',
    (tester) async {
      final router = await pumpUx(
        tester,
        UserRole.operator,
        initial: '/fleet/report',
      );
      await tester.enterText(find.byType(TextFormField), 'A leak');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/fleet');
    },
  );
  test('displayed build agrees with the package version', () {
    final version = RegExp(
      r'^version: (.+)$',
      multiLine: true,
    ).firstMatch(File('pubspec.yaml').readAsStringSync())!.group(1);
    expect(AppConstants.appVersion, version);
  });
  test(
    'every role keeps assets, faults, and tools reachable; field roles omit billing',
    () {
      for (final role in UserRole.values) {
        final items = primaryDestinations(role);
        expect(
          items.map((e) => e.en),
          containsAll(['Home', 'Assets', 'Faults', 'More']),
        );
        expect(items.length, lessThanOrEqualTo(5));
        expect(
          selectedDestination(items, '/fleet/faults/123'),
          items.indexWhere((e) => e.en == 'Faults'),
        );
        expect(
          selectedDestination(
            items,
            '${roleRoutePrefix(role)}/service-reports/123',
          ),
          items.length - 1,
        );
      }
      for (final role in [
        UserRole.operator,
        UserRole.clientOperator,
        UserRole.clientMechanic,
        UserRole.employee,
      ]) {
        expect(
          toolDestinations(role).map((e) => e.en),
          isNot(contains('Invoices')),
        );
        expect(
          toolDestinations(role).map((e) => e.en),
          isNot(contains('Team')),
        );
      }
      expect(
        primaryDestinations(UserRole.operator).map((e) => e.en),
        isNot(contains('Checks')),
      );
      expect(
        primaryDestinations(
          UserRole.operator,
          operationalChecklistsEnabled: true,
        ).map((e) => e.en),
        contains('Checks'),
      );
    },
  );
  for (final role in UserRole.values) {
    testWidgets('${role.name} asset tap stays in the correct role routes', (
      tester,
    ) async {
      await pumpUx(
        tester,
        role,
        initial: '${roleRoutePrefix(role)}/assets',
        width: 320,
        scale: 1.4,
      );
      expect(
        find.byType(FloatingActionButton),
        role == UserRole.owner ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Hydraulic Pump 04'));
      await tester.pumpAndSettle();
      expect(find.text('Asset pump'), findsOneWidget);
    });
  }
  testWidgets('More searches tools and opens the actual destination', (
    tester,
  ) async {
    await pumpUx(tester, UserRole.owner);
    await captureFleet(tester, 'ux-owner-more');
    await tester.enterText(find.byType(TextField), 'invoice');
    await tester.pumpAndSettle();
    expect(find.text('Clients'), findsNothing);
    await tester.tap(find.text('Invoices'));
    await tester.pumpAndSettle();
    expect(find.text('Invoices destination'), findsOneWidget);
  });
  testWidgets(
    'Spanish More remains usable with enlarged text and narrow width',
    (tester) async {
      await pumpUx(
        tester,
        UserRole.clientAdmin,
        language: 'es',
        scale: 1.5,
        width: 320,
      );
      await captureFleet(tester, 'ux-client-more-es-large');
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextField), 'impossible');
      await tester.pumpAndSettle();
      expect(
        find.text('No hay resultados. Prueba otra palabra.'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Borrar búsqueda'));
      await tester.pumpAndSettle();
      expect(find.text('Solicitudes de servicio'), findsOneWidget);
    },
  );
  testWidgets(
    'Android shell back protects fault text; keep editing retains it; discard leaves',
    (tester) async {
      final router = await pumpUx(
        tester,
        UserRole.clientMechanic,
        initial: '/fleet',
      );
      await tester.tap(find.text('Report a fault'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomNavigationBar), findsNothing);
      await tester.enterText(
        find.byType(TextFormField),
        'Hydraulic leak at the pump seal',
      );
      await tester.pumpAndSettle();
      final listener = tester.widget<BackButtonListener>(
        find.byType(BackButtonListener).first,
      );
      await listener.onBackButtonPressed();
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
      await captureFleet(tester, 'ux-unsaved-fault');
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.text('Hydraulic leak at the pump seal'), findsOneWidget);
      await listener.onBackButtonPressed();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/fleet');
      expect(tester.takeException(), isNull);
    },
  );
}
