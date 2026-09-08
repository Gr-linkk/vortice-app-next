import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/app_navigation.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/equipment_reporting/equipment_report.dart';
import 'package:vortice_app/features/equipment_reporting/equipment_report_screen.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/models/profile.dart';
import '../fleet/fleet_test_support.dart'
    show captureFleet, loadFleetScreenshotFonts;

EquipmentReport fixture({String name = 'Harbour Generator 02'}) =>
    EquipmentReport({
      'from': '2026-01-01T00:00:00Z',
      'to': '2026-02-01T00:00:00Z',
      'generated_at': '2026-02-02T12:00:00Z',
      'assets': [
        {
          'id': 'generator',
          'name': name,
          'location': 'North workshop',
          'labour': 100,
          'parts': 40,
          'outside': 116,
          'total': 256,
          'unavailable_hours': 8,
          'unknown_hours': 0,
          'cost_gaps': 1,
          'fault_count': 2,
          'repeats': [
            {
              'description': 'Cooling leak',
              'count': 2,
              'ids': ['fault-1', 'fault-2'],
            },
          ],
          'records': [
            {
              'id': 'job-1',
              'kind': 'internal',
              'title': 'Replace cooling seal',
              'occurred_at': '2026-01-10T12:00:00Z',
              'labour': 100,
              'parts': 40,
              'outside': 0,
              'hours': 0,
              'gaps': 0,
            },
            {
              'id': 'invoice-1',
              'kind': 'invoice',
              'title': 'INV-42',
              'occurred_at': '2026-01-12T12:00:00Z',
              'labour': 0,
              'parts': 0,
              'outside': 116,
              'hours': 0,
              'gaps': 0,
            },
            {
              'id': 'fault-1',
              'kind': 'fault',
              'title': 'Cooling leak',
              'occurred_at': '2026-01-05T12:00:00Z',
              'labour': 0,
              'parts': 0,
              'outside': 0,
              'hours': 0,
              'gaps': 0,
            },
          ],
        },
        {
          'id': 'loader',
          'name': 'Wheel Loader 12',
          'location': 'Yard',
          'labour': 0,
          'parts': 0,
          'outside': 0,
          'total': 0,
          'unavailable_hours': 20,
          'unknown_hours': 48,
          'cost_gaps': 0,
          'fault_count': 0,
          'repeats': [],
          'records': [],
        },
      ],
    });

Future<void> pumpReport(
  WidgetTester tester,
  ReportLoader loader, {
  String language = 'en',
  double scale = 1,
  bool dark = false,
  UserRole role = UserRole.clientAdmin,
  Future<void> Function(String, Rect?)? share,
  Future<Profile?> Function()? profileSource,
  bool settle = true,
}) async {
  tester.view.resetPhysicalSize();
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    initialLocation: '/fleet/reporting',
    routes: [
      GoRoute(
        path: '/fleet/reporting',
        builder: (_, _) => const EquipmentReportScreen(),
      ),
      GoRoute(
        path: '/maintenance/jobs/:id',
        builder: (_, state) =>
            Scaffold(body: Text('Opened ${state.pathParameters['id']}')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        profileProvider.overrideWith(
          (ref) async => profileSource != null
              ? await profileSource()
              : Profile(
                  id: 'manager',
                  email: 'manager@example.invalid',
                  fullName: 'Manager',
                  role: role,
                ),
        ),
        equipmentReportLoaderProvider.overrideWithValue(loader),
        shareEquipmentReportProvider.overrideWithValue(
          share ?? (_, _) async {},
        ),
      ],
      child: RepaintBoundary(
        key: const Key('fleet-capture'),
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          routerConfig: router,
          theme: dark ? AppTheme.darkNavyTheme : AppTheme.lightTheme,
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
  if (settle) {
    await tester.pumpAndSettle();
  }
}

Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await loadFleetScreenshotFonts();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  test(
    'CSV includes full records, matching groups, bounds and formula-safe names',
    () {
      final csv = equipmentReportCsv(fixture(name: '=HYPERLINK("bad")'));
      expect(csv, contains("'=HYPERLINK"));
      expect(csv, contains('Replace cooling seal'));
      expect(csv, contains('INV-42'));
      expect(csv, contains('fault-1 fault-2'));
      expect(csv, contains('Until (exclusive, UTC)'));
      expect(csv, contains('256.00'));
      expect(
        equipmentReportCsv(fixture(), spanish: true),
        contains('Informe de equipos'),
      );
      expect(possibleRepeatCount(fixture().assets.first), 1);
      expect(possibleRepeatCount(fixture().assets.last), 0);
    },
  );
  test(
    'navigation only exposes report to management and source links preserve role',
    () {
      for (final role in UserRole.values) {
        expect(
          toolDestinations(role).any((d) => d.route == '/fleet/reporting'),
          canReadEquipmentReport(role),
        );
      }
      expect(
        reportRecordDestination(
          {'kind': 'invoice', 'id': 'i'},
          'a',
          UserRole.clientAdmin,
        ),
        '/client/invoices/i',
      );
      expect(
        reportRecordDestination(
          {'kind': 'uncosted', 'id': 'w'},
          'a',
          UserRole.client,
        ),
        '/client/service-reports?workOrderId=w',
      );
      expect(
        reportRecordDestination(
          {'kind': 'downtime', 'id': 'e'},
          'a',
          UserRole.owner,
        ),
        '/fleet/assets/a',
      );
    },
  );
  testWidgets(
    'periods, sort, expansion, source navigation and full refreshed export',
    (tester) async {
      final periods = <ReportPeriod>[];
      String? exported;
      await pumpReport(
        tester,
        (period) async {
          periods.add(period);
          return fixture();
        },
        share: (csv, _) async {
          exported = csv;
        },
      );
      expect(find.text('USD 256.00'), findsOneWidget);
      await tester.tap(find.text('Last month'));
      await tester.pumpAndSettle();
      expect(periods.last.to.day, 1);
      expect(periods.last.from.day, 1);
      await reveal(tester, find.text('Downtime'));
      await tester.tap(find.text('Downtime'));
      await tester.pumpAndSettle();
      final tiles = tester
          .widgetList<ExpansionTile>(find.byType(ExpansionTile))
          .toList();
      expect((tiles.first.title as Text).data, 'Wheel Loader 12');
      await reveal(tester, find.text('Export report'));
      await tester.tap(find.text('Export report'));
      await tester.pumpAndSettle();
      expect(periods.length, 3);
      expect(exported, contains('INV-42'));
      await reveal(tester, find.text('Harbour Generator 02'));
      await tester.tap(find.text('Harbour Generator 02'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Possible repeat: Cooling leak (2)'),
        findsOneWidget,
      );
      await reveal(tester, find.text('Replace cooling seal'));
      await tester.tap(find.text('Replace cooling seal'));
      await tester.pumpAndSettle();
      expect(find.text('Opened job-1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('failed fresh export never shares cached report', (tester) async {
    var calls = 0;
    var shares = 0;
    await pumpReport(
      tester,
      (_) async {
        if (++calls > 1) throw StateError('Access denied');
        return fixture();
      },
      share: (_, _) async {
        shares++;
      },
    );
    await reveal(tester, find.text('Export report'));
    await tester.tap(find.text('Export report'));
    await tester.pumpAndSettle();
    expect(shares, 0);
    expect(find.byType(AppErrorState), findsOneWidget);
  });
  testWidgets('non-manager direct entry performs no report request', (
    tester,
  ) async {
    var calls = 0;
    await pumpReport(tester, (_) async {
      calls++;
      return fixture();
    }, role: UserRole.clientMechanic);
    expect(calls, 0);
    expect(find.text('Available to fleet managers.'), findsOneWidget);
  });
  testWidgets(
    'changing company while export is pending prevents sharing old data',
    (tester) async {
      var profile = const Profile(
        id: 'manager',
        email: 'manager@example.invalid',
        fullName: 'Manager',
        role: UserRole.clientAdmin,
        orgId: 'company-a',
      );
      final pending = Completer<EquipmentReport>();
      var calls = 0;
      var shares = 0;
      await pumpReport(
        tester,
        (_) async {
          calls++;
          if (calls == 1) return fixture();
          if (calls == 2) return pending.future;
          return EquipmentReport({'assets': []});
        },
        profileSource: () async => profile,
        share: (_, _) async {
          shares++;
        },
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(EquipmentReportScreen)),
      );
      await reveal(tester, find.text('Export report'));
      await tester.tap(find.text('Export report'));
      await tester.pump();
      profile = profile.copyWith(orgId: 'company-b');
      container.invalidate(profileProvider);
      await tester.pumpAndSettle();
      pending.complete(fixture());
      await tester.pumpAndSettle();
      expect(shares, 0);
      expect(find.text('Harbour Generator 02'), findsNothing);
    },
  );
  testWidgets('loading is explicit until the report arrives', (tester) async {
    final pending = Completer<EquipmentReport>();
    await pumpReport(tester, (_) => pending.future, settle: false);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.complete(fixture());
    await tester.pumpAndSettle();
    expect(find.text('USD 256.00'), findsOneWidget);
  });
  testWidgets('empty and error states can be retried', (tester) async {
    var fail = true;
    await pumpReport(tester, (_) async {
      if (fail) throw StateError('Offline');
      return EquipmentReport({'assets': []});
    });
    expect(find.byType(AppErrorState), findsOneWidget);
    fail = false;
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(
      find.text('No equipment is available in your fleet.'),
      findsOneWidget,
    );
  });
  for (final language in ['en', 'es']) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('render $language ${scale}x', (tester) async {
        await pumpReport(
          tester,
          (_) async => fixture(),
          language: language,
          scale: scale,
          dark: language == 'es',
        );
        expect(tester.takeException(), isNull);
        await captureFleet(tester, 'report-$language-$scale');
        await reveal(tester, find.text('Harbour Generator 02'));
        await tester.tap(find.text('Harbour Generator 02'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await reveal(tester, find.text('Replace cooling seal'));
        await captureFleet(tester, 'report-detail-$language-$scale');
        expect(tester.takeException(), isNull);
      });
    }
  }
}
