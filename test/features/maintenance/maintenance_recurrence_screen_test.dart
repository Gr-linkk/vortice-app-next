import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/maintenance/maintenance_setup_screen.dart';
import 'maintenance_screen_test.dart'
    show FixtureMaintenance, catalog, pumpMaintenance;
import '../fleet/fleet_test_support.dart'
    show captureFleet, loadFleetScreenshotFonts;

final initial = <String, dynamic>{
  'id': 'plan',
  'engine_id': 'engine',
  'interval_label': 'Dredge routine service',
  'interval_hours': 250,
  'last_service_hours': 6700,
  'revision': 0,
  'recurrence_mode': 'fixed',
  'anchor_hours': 7000,
  'next_due_hours': 7000,
  'is_active': true,
};

void main() {
  setUpAll(() async {
    await loadFleetScreenshotFonts();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  testWidgets(
    'manager previews transition, adjusts target and retries unchanged save',
    (tester) async {
      final repo = FixtureMaintenance()..failNext = true;
      await pumpMaintenance(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => MaintenanceSetupScreen(
                    kind: 'plan',
                    assetId: 'asset',
                    initial: initial,
                    catalog: catalog,
                  ),
                ),
              ),
              child: const Text('Open plan'),
            ),
          ),
        ),
        repo,
      );
      await tester.tap(find.text('Open plan'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('anchor_hours')));
      await tester.enterText(
        find.byKey(const ValueKey('anchor_hours')),
        '7100',
      );
      await tester.enterText(
        find.byKey(const ValueKey('change_reason')),
        'Align after haul-out',
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Upcoming targets'));
      expect(find.text('1. 7100.0 h'), findsOneWidget);
      expect(find.text('2. 7350.0 h'), findsOneWidget);
      await captureFleet(tester, 'recurrence-preview-en');
      await tester.scrollUntilVisible(
        find.text('Save').hitTestable(),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(repo.writes, hasLength(1));
      expect(repo.writes.single.data['anchor_hours'], '7100');
      expect(repo.writes.single.data['last_service_hours'], '6700');
      expect(repo.writes.single.data['recurrence_mode'], 'fixed');
      await tester.scrollUntilVisible(
        find.text('Retry save').hitTestable(),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retry save'));
      await tester.pumpAndSettle();
      expect(repo.writes, hasLength(2));
      expect(repo.writes[0].id, repo.writes[1].id);
      expect(repo.writes[0].data, repo.writes[1].data);
      expect(find.text('Open plan'), findsOneWidget);
    },
  );
  testWidgets('calendar recurrence renders at 320px Spanish large text', (
    tester,
  ) async {
    await pumpMaintenance(
      tester,
      MaintenanceSetupScreen(
        kind: 'plan',
        assetId: 'asset',
        catalog: catalog,
        initial: {
          ...initial,
          'interval_hours': 0,
          'interval_months': 6,
          'anchor_date': '2026-10-01',
          'next_due_date': '2026-10-01',
        },
      ),
      FixtureMaintenance(),
      es: true,
      width: 320,
      scale: 2,
    );
    await captureFleet(tester, 'recurrence-calendar-es-large-top');
    for (var i = 0; i < 6; i++) {
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await tester.pumpAndSettle();
    }
    await captureFleet(tester, 'recurrence-calendar-es-large');
    expect(tester.takeException(), isNull);
  });
}
