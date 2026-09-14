import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vortice_app/core/app_dropdown_field.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/maintenance/create_work_entry.dart';
import 'package:vortice_app/features/membership/organization_work_provider.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import '../assets/fleet_import_screen_test.dart' show visibleTap;
import '../fleet/fleet_test_support.dart'
    show captureFleet, loadFleetScreenshotFonts;

const equipment = [
  {
    'relationship_id': 'customer',
    'asset_id': 'machine',
    'customer_name': 'North Harbour',
    'asset_name': 'Generator 02',
    'templates': [
      {
        'id': 'checklist',
        'name': 'Generator inspection and pressure verification',
        'version': 3,
      },
    ],
  },
  {
    'relationship_id': 'customer',
    'asset_id': 'other',
    'customer_name': 'North Harbour',
    'asset_name': 'Pump 04',
    'templates': [],
  },
];

class CreationFixture extends OrganizationWorkRepository {
  Object? failure;
  final saves = <Map<String, dynamic>>[];
  @override
  Future<String> createCustomerWork(
    String operation,
    String relationship,
    String asset,
    String title,
    String note, {
    DateTime? serviceDate,
    String? checklistTemplateId,
  }) async {
    saves.add({
      'operation': operation,
      'asset': asset,
      'date': serviceDate,
      'checklist': checklistTemplateId,
      'title': title,
      'note': note,
    });
    if (failure != null) throw failure!;
    return 'saved-work';
  }
}

Future<void> pumpCreation(
  WidgetTester tester,
  CreationFixture fixture, {
  bool es = false,
  double width = 390,
  double scale = 1,
  bool empty = false,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => CustomerWorkCreateScreen(
                  selectedDay: DateTime(2026, 9, 20),
                ),
              ),
            ),
            child: const Text('New'),
          ),
        ),
      ),
      GoRoute(
        path: '/maintenance/planning',
        builder: (_, state) => Scaffold(
          body: Text('Calendar ${state.uri.queryParameters['day']}'),
        ),
      ),
      GoRoute(
        path: '/work-orders/:id',
        builder: (_, state) =>
            Scaffold(body: Text('Work ${state.pathParameters['id']}')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        customerWorkCreationProvider.overrideWith(
          (_) async => {'equipment': empty ? [] : equipment},
        ),
        organizationWorkRepositoryProvider.overrideWithValue(fixture),
      ],
      child: RepaintBoundary(
        key: const Key('fleet-capture'),
        child: MaterialApp.router(
          routerConfig: router,
          theme: AppTheme.darkNavyTheme,
          debugShowCheckedModeBanner: false,
          locale: Locale(es ? 'es' : 'en'),
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
  await tester.tap(find.text('New'));
  await tester.pumpAndSettle();
}

Future<void> chooseEquipment(WidgetTester tester, {bool other = false}) async {
  await visibleTap(tester, find.byType(AppDropdownField<String>).first);
  await tester.tap(
    find
        .text(
          other ? 'North Harbour · Pump 04' : 'North Harbour · Generator 02',
        )
        .last,
  );
  await tester.pumpAndSettle();
}

Future<void> chooseChecklist(WidgetTester tester) async {
  await visibleTap(tester, find.byType(AppDropdownField<String>).last);
  await tester.tap(
    find.text('Generator inspection and pressure verification · v3').last,
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadFleetScreenshotFonts);
  testWidgets(
    'creation changes calendar day and attaches selected checklist in one save',
    (tester) async {
      final fixture = CreationFixture();
      await pumpCreation(tester, fixture);
      await chooseEquipment(tester);
      await chooseChecklist(tester);
      expect(find.text('Sep 20, 2026'), findsOneWidget);
      await visibleTap(tester, find.byKey(const Key('creation-date')));
      await tester.tap(find.text('23').last);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await captureFleet(tester, 'creation-checklist-date-390');
      await tester.enterText(find.byType(TextField).first, 'Generator service');
      await tester.enterText(
        find.byType(TextField).last,
        'Check pressure under load.',
      );
      await visibleTap(tester, find.text('Create work order'));
      expect(fixture.saves.single['date'], DateTime(2026, 9, 23));
      expect(fixture.saves.single['checklist'], 'checklist');
      expect(find.text('Calendar 2026-09-23'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'changing equipment clears checklist and clearing date saves unscheduled',
    (tester) async {
      final fixture = CreationFixture();
      await pumpCreation(tester, fixture);
      await chooseEquipment(tester);
      await chooseChecklist(tester);
      await chooseEquipment(tester, other: true);
      expect(
        find.text('No published checklists match this equipment.'),
        findsOneWidget,
      );
      await visibleTap(tester, find.byKey(const Key('creation-clear-date')));
      await tester.enterText(find.byType(TextField).first, 'Pump inspection');
      await visibleTap(tester, find.text('Create work order'));
      expect(fixture.saves.single['date'], isNull);
      expect(fixture.saves.single['checklist'], isNull);
      expect(find.text('Work saved-work'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('uncertain save freezes inputs and retries identical payload', (
    tester,
  ) async {
    final fixture = CreationFixture()
      ..failure = TimeoutException('Lost response');
    await pumpCreation(tester, fixture);
    await chooseEquipment(tester);
    await chooseChecklist(tester);
    await tester.enterText(find.byType(TextField).first, 'Generator service');
    await visibleTap(tester, find.text('Create work order'));
    expect(
      tester.widget<TextField>(find.byType(TextField).first).enabled,
      isFalse,
    );
    expect(
      tester.widget<ListTile>(find.byKey(const Key('creation-date'))).onTap,
      isNull,
    );
    fixture.failure = null;
    await visibleTap(tester, find.text('Retry same save'));
    expect(fixture.saves, hasLength(2));
    expect(fixture.saves.first, fixture.saves.last);
    expect(find.text('Calendar 2026-09-20'), findsOneWidget);
  });
  for (final es in [false, true]) {
    testWidgets(
      'checklist/date readable and rejection editable at 320px 200% $es',
      (tester) async {
        final fixture = CreationFixture()
          ..failure = const PostgrestException(
            message: 'Choose a published provider checklist for this equipment',
            code: 'P0001',
          );
        await pumpCreation(tester, fixture, es: es, width: 320, scale: 2);
        await chooseEquipment(tester);
        await chooseChecklist(tester);
        await captureFleet(tester, 'creation-checklist-320-2x-$es');
        await visibleTap(tester, find.byKey(const Key('creation-date')));
        await captureFleet(tester, 'creation-datepicker-320-2x-$es');
        await tester.tap(find.text(es ? 'Cancelar' : 'Cancel'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextField).first,
          'Generator service',
        );
        await visibleTap(
          tester,
          find.text(es ? 'Crear orden de trabajo' : 'Create work order'),
        );
        expect(
          tester.widget<TextField>(find.byType(TextField).first).enabled,
          isTrue,
        );
        await captureFleet(tester, 'creation-rejection-320-2x-$es');
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('no shared equipment explains next step and cannot create', (
    tester,
  ) async {
    await pumpCreation(tester, CreationFixture(), empty: true);
    expect(
      find.textContaining('Your customer needs to connect'),
      findsOneWidget,
    );
    expect(find.byType(FilledButton), findsNothing);
  });
}
