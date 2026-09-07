import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/agent_access/agent_workspace_screen.dart';
import 'package:vortice_app/features/agent_access/agent_pending_plans_screen.dart';
import '../fleet/fleet_test_support.dart';

Map<String, dynamic> workspaceData({bool single = false}) => {
  'fleets': [
    {'id': 'fleet-a', 'name': 'Harbour Marine'},
    if (!single) {'id': 'fleet-b', 'name': 'Quarry Operations'},
  ],
  'connections': [],
  'activity': [],
};
List<Map<String, dynamic>> proposals(String fleet) => [
  {
    'id': 'proposal-$fleet',
    'assets': {
      'name': fleet == 'fleet-a' ? 'Harbour generator' : 'Mobile crane',
    },
    'draft': {
      'interval_label': fleet == 'fleet-a'
          ? 'Cooling system service'
          : 'Hoist inspection',
      'interval_hours': 250,
    },
  },
];

Widget app({
  bool dark = false,
  bool spanish = false,
  double scale = 1,
  bool single = false,
  List<String>? requests,
  bool Function()? fail,
}) => ProviderScope(
  overrides: [
    agentWorkspaceProvider.overrideWith(
      (ref) async => workspaceData(single: single),
    ),
    pendingAgentPlansProvider.overrideWith((ref, key) async {
      requests?.add(key.$1);
      if (fail?.call() == true) throw StateError('offline');
      return proposals(key.$1);
    }),
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
      home: const AgentWorkspacePanel(),
    ),
  ),
);

void main() {
  setUpAll(() async {
    await loadFleetScreenshotFonts();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  testWidgets(
    'workspace requires explicit fleet and replaces prior fleet proposals',
    (tester) async {
      final requests = <String>[];
      await tester.pumpWidget(app(requests: requests));
      await tester.pumpAndSettle();
      expect(requests, isEmpty);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Harbour Marine').last);
      await tester.pumpAndSettle();
      expect(find.text('Cooling system service'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Quarry Operations').last);
      await tester.pumpAndSettle();
      expect(find.text('Cooling system service'), findsNothing);
      expect(find.text('Hoist inspection'), findsOneWidget);
      expect(requests, ['fleet-a', 'fleet-b']);
    },
  );
  testWidgets('plan error retries without losing selected fleet', (
    tester,
  ) async {
    var fail = true;
    await tester.pumpWidget(app(single: true, fail: () => fail));
    await tester.pumpAndSettle();
    fail = false;
    await tester.tap(find.text('Could not load plans. Retry.'));
    await tester.pumpAndSettle();
    expect(find.text('Cooling system service'), findsOneWidget);
  });
  for (final dark in [false, true]) {
    for (final large in [false, true]) {
      testWidgets('workspace render dark=$dark large=$large', (tester) async {
        tester.view.physicalSize = const Size(390, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          app(dark: dark, spanish: dark, scale: large ? 2 : 1, single: true),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await captureFleet(tester, 'workspace-$dark-$large');
        await tester.drag(find.byType(ListView), const Offset(0, -650));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await captureFleet(tester, 'workspace-scrolled-$dark-$large');
      });
    }
  }
}
