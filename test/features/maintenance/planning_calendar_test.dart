import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vortice_app/features/maintenance/planning/maintenance_planning_screen.dart';
import 'package:vortice_app/features/maintenance/planning/planning_models.dart';
import 'planning_test.dart' show booking, FixturePlanning, showPlanning, reveal;
import 'planning_hub_test.dart' show chooseFilter;
import '../fleet/fleet_test_support.dart'
    show captureFleet, loadFleetScreenshotFonts;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(loadFleetScreenshotFonts);

  testWidgets('calendar status filtering keeps the selected month and day', (
    tester,
  ) async {
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    await showPlanning(
      tester,
      const MaintenancePlanningScreen(),
      FixturePlanning(
        PlanningData(
          jobs: [
            booking('scheduled', start: day.add(const Duration(hours: 8))),
            booking(
              'completed',
              start: day.add(const Duration(hours: 10)),
              status: 'closed',
            ),
          ],
          plans: [],
        ),
      ),
    );
    expect(find.byType(PlanningMonth), findsOneWidget);
    await tester.pumpAndSettle();
    await chooseFilter(tester, 'Completed');
    expect(find.byType(PlanningMonth), findsOneWidget);
    await reveal(tester, find.text('Service completed'));
    expect(find.text('Service scheduled'), findsNothing);
    await tester.tap(find.text('Service completed'));
    await tester.pumpAndSettle();
    expect(find.text('Job saved'), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator).last).pop();
    await tester.pumpAndSettle();
    await reveal(
      tester,
      find.byKey(ValueKey('calendar-agenda-${day.toIso8601String()}')),
    );
    expect(find.text('Service completed'), findsOneWidget);
  });

  for (final es in [false, true]) {
    testWidgets(
      'calendar badges and full agenda titles fit at 320px 200% ${es ? 'es' : 'en'}',
      (tester) async {
        final now = DateTime.now();
        final day = DateTime(now.year, now.month, now.day);
        final jobs = [
          booking(
            'overnight hydraulic equipment inspection',
            start: day.subtract(const Duration(hours: 1)),
            minutes: 180,
          ),
          PlanningJob({
            'id': 'customer',
            'title': 'Customer generator inspection without booked time',
            'asset_id': 'asset',
            'asset_name': 'Long equipment name for a customer vessel',
            'provider_service': true,
            'own_equipment': false,
            'service_date': day.toIso8601String(),
            'status': 'draft',
          }),
        ];
        await showPlanning(
          tester,
          const MaintenancePlanningScreen(),
          FixturePlanning(PlanningData(jobs: jobs, plans: [])),
          es: es,
          width: 320,
          scale: 2,
          light: true,
        );
        expect(find.byType(PlanningMonth), findsOneWidget);
        await reveal(tester, find.byType(PlanningMonth));
        await captureFleet(tester, 'calendar-month-320-${es ? 'es' : 'en'}');
        await reveal(
          tester,
          find.text('Customer generator inspection without booked time'),
        );
        expect(
          find.text(es ? 'Sin hora reservada' : 'No time booked'),
          findsOneWidget,
        );
        await captureFleet(tester, 'calendar-agenda-320-${es ? 'es' : 'en'}');
        expect(tester.takeException(), isNull);
        final next = DateTime(day.year, day.month, day.day + 1);
        expect(jobs.first.inPeriod(day, next), isTrue);
      },
    );
  }
}
