import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/agent_access/agent_plan_review_screen.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/maintenance/maintenance_repository.dart';
import 'agent_mfa_test.dart' show session;
import '../fleet/fleet_test_support.dart';

class FixturePlan extends AgentPlanRepository {
  FixturePlan(SupabaseClient client) : super(client, 'actor');
  Map<String, dynamic>? applied;
  @override
  Future<Map<String, dynamic>> load(String id) async => {
    'proposal': {
      'id': id,
      'asset_id': 'asset',
      'document_id': 'doc',
      'applied_plan_id': applied == null ? null : 'saved-plan',
      'draft': {
        'interval_label': 'Cooling service',
        'interval_hours': 250,
        'engine_id': 'engine',
        'source_page': 1,
        'source_quote': 'Service the cooling system every 250 hours.',
      },
    },
    'catalog': {
      'asset': {'name': 'Harbour generator'},
      'components': [
        {'id': 'engine', 'label': 'Main engine', 'current_hours': 250},
      ],
      'plans': [],
      'templates': [],
    },
  };
  @override
  Future<void> apply(
    String id,
    String operation,
    Map<String, dynamic> data,
  ) async {
    applied = data;
  }
}

Widget app(
  FixturePlan repository, {
  bool spanish = false,
  bool dark = false,
  double scale = 1,
}) => ProviderScope(
  overrides: [
    sessionProvider.overrideWithValue(Session.fromJson(jsonDecode(jsonEncode(session('actor'))))),
    agentPlanRepositoryProvider.overrideWithValue(repository),
    maintenanceWorkspaceProvider.overrideWith((ref) async => {}),
  ],
  child: RepaintBoundary(
    key: const Key('fleet-capture'),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
      locale: Locale(spanish ? 'es' : 'en'),
      supportedLocales: const [Locale('en'), Locale('es')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: const AgentPlanReviewScreen(id: 'proposal'),
    ),
  ),
);

void main() {
  late SupabaseClient client;
  setUpAll(() async {
    client = SupabaseClient('https://hkjpojobdbbtjkhaudki.supabase.co', 'fixture');
    await loadFleetScreenshotFonts();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  tearDownAll(() => client.dispose());
  testWidgets(
    'user edits interval and supplies missing history before a reviewed save',
    (tester) async {
      final repository = FixturePlan(client);
      await tester.pumpWidget(app(repository));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Last service for this task: Needs confirmation'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Edit and save reviewed plan'));
      await tester.tap(find.text('Edit and save reviewed plan'));
      await tester.pumpAndSettle();
      // Inspect the controller to prove that unknown history was not set to zero.
      final baseline = find.byWidgetPredicate(
        (w) =>
            w is TextField && w.decoration?.labelText == 'Last service meter',
      );
      expect(tester.widget<TextField>(baseline).controller!.text, '');
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(repository.applied, isNull);
      await tester.enterText(baseline, '100');
      final interval = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.labelText == 'Service every (hours)',
      );
      await tester.enterText(interval, '300');
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(repository.applied?['interval_hours'], '300');
      expect(repository.applied?['last_service_hours'], '100');
      expect(repository.applied?['source_reviewed'], true);
      expect(repository.applied?['review_current_hours'], 250);
      expect(find.text('View saved plan'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  for (final spanish in [false, true]) {
    for (final dark in [false, true]) {
      testWidgets('plan review at 320px and 200% $spanish $dark', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          app(FixturePlan(client), spanish: spanish, dark: dark, scale: 2),
        );
        await tester.pumpAndSettle();
        await captureFleet(
          tester,
          'plan-review-${spanish ? 'es' : 'en'}-${dark ? 'dark' : 'light'}',
        );
        await tester.drag(find.byType(ListView), const Offset(0, -650));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
