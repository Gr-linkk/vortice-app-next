import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/fleet/availability_screen.dart';
import 'package:vortice_app/features/fleet/fault_detail_screen.dart';
import 'package:vortice_app/features/fleet/fault_report_screen.dart';
import 'package:vortice_app/features/fleet/fleet_models.dart';
import 'package:vortice_app/features/fleet/fleet_policy.dart';
import 'package:vortice_app/features/fleet/fleet_screen.dart';
import 'package:vortice_app/models/profile.dart';
import 'fleet_test_support.dart';

void main() {
  setUpAll(loadFleetScreenshotFonts);
  testWidgets('fleet board shows actionable faults and filters assigned work', (
    tester,
  ) async {
    final repository = FixtureFleetRepository();
    await pumpFleet(
      tester,
      const FleetScreen(),
      repository,
      role: UserRole.clientMechanic,
      userId: 'mechanic',
    );
    expect(find.text('Hydraulic Pump 04'), findsOneWidget);
    expect(find.text('Wheel Loader 12'), findsOneWidget);
    await captureFleet(tester, '01-fault-board-en');
    await tester.tap(find.text('Assigned to me'));
    await tester.pumpAndSettle();
    expect(find.text('Wheel Loader 12'), findsNothing);
    await tester.tap(find.text('Closed'));
    await tester.pumpAndSettle();
    expect(find.text('No faults in this view'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('availability and unassessed states fit a narrow Spanish phone', (
    tester,
  ) async {
    await pumpFleet(
      tester,
      const FleetScreen(initialTab: 1),
      FixtureFleetRepository(),
      language: 'es',
      size: const Size(360, 800),
    );
    expect(find.text('Fuera de servicio'), findsWidgets);
    await captureFleet(tester, '02-availability-es');
    await tester.tap(find.byType(DropdownButtonFormField<OperatingState>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sin evaluar').last);
    await tester.pumpAndSettle();
    expect(find.text('Wheel Loader 12'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'report validates, preserves failed input and retries same identifier',
    (tester) async {
      final repository = FixtureFleetRepository()
        ..nextReportError = TimeoutException('network');
      await pumpFleet(
        tester,
        const FaultReportScreen(assetId: 'pump'),
        repository,
        role: UserRole.operator,
      );
      await tester.ensureVisible(find.text('Submit report'));
      await tester.tap(find.text('Submit report'));
      await tester.pumpAndSettle();
      expect(find.text('Add a description'), findsOneWidget);
      await tester.enterText(
        find.byType(TextFormField),
        'Hydraulic line is leaking',
      );
      await tester.ensureVisible(find.byType(SwitchListTile));
      await tester.tap(find.byType(SwitchListTile));
      await tester.ensureVisible(find.text('Submit report'));
      await tester.tap(find.text('Submit report'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Your input is kept here'), findsOneWidget);
      expect(find.text('Hydraulic line is leaking'), findsOneWidget);
      await captureFleet(tester, '03-report-retry-en');
      await tester.ensureVisible(find.text('Submit report'));
      await tester.tap(find.text('Submit report'));
      await tester.pumpAndSettle();
      expect(repository.reportIds.length, 2);
      expect(repository.reportIds.toSet().length, 1);
      expect(repository.reportUrgent, isTrue);
      expect(find.text('Fault tracking'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'manager review requires evidence note and submits the selected action',
    (tester) async {
      final repository = FixtureFleetRepository();
      await pumpFleet(
        tester,
        const FaultDetailScreen(faultId: 'fault-1'),
        repository,
      );
      await captureFleet(tester, '04-fault-review-en');
      await tester.ensureVisible(find.text('Verify & resolve'));
      await tester.tap(find.text('Verify & resolve'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Verify & resolve').last,
      );
      await tester.pumpAndSettle();
      expect(find.text('Explain this change'), findsOneWidget);
      await tester.enterText(
        find.byType(TextFormField),
        'Pressure test verified with no leakage',
      );
      await tester.tap(
        find.widgetWithText(FilledButton, 'Verify & resolve').last,
      );
      await tester.pumpAndSettle();
      expect(repository.mutations, [FaultAction.resolve]);
      expect(repository.lastNote, 'Pressure test verified with no leakage');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('operator cannot approve repairs or change asset availability', (
    tester,
  ) async {
    final repository = FixtureFleetRepository();
    await pumpFleet(
      tester,
      const FaultDetailScreen(faultId: 'fault-1'),
      repository,
      role: UserRole.operator,
    );
    expect(find.text('Verify & resolve'), findsNothing);
    expect(find.text('Assign repair'), findsNothing);
    await tester.tap(find.text('Hydraulic Pump 04'));
    await tester.pumpAndSettle();
    expect(find.text('Update availability'), findsNothing);
    expect(find.text('Recorded downtime'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'urgent fault blocks available but permits a reasoned maintenance state',
    (tester) async {
      final repository = FixtureFleetRepository();
      await pumpFleet(
        tester,
        const AvailabilityScreen(assetId: 'pump'),
        repository,
      );
      await captureFleet(tester, '05-asset-availability-en');
      await tester.ensureVisible(find.text('Update availability'));
      await tester.tap(find.text('Update availability'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<OperatingState>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Available').last);
      await tester.pumpAndSettle();
      expect(
        find.text('Resolve or dismiss urgent faults first.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save state'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byType(DropdownButtonFormField<OperatingState>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Under maintenance').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField),
        'Moved to workshop for seal replacement',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save state'));
      await tester.pumpAndSettle();
      expect(repository.lastState, OperatingState.underMaintenance);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('read failure is explicit and retry loads the fleet', (
    tester,
  ) async {
    final repository = FixtureFleetRepository()
      ..readError = TimeoutException('offline');
    await pumpFleet(tester, const FleetScreen(), repository);
    expect(find.text('Retry'), findsWidgets);
    repository.readError = null;
    await tester.tap(find.text('Retry').first);
    await tester.pumpAndSettle();
    expect(find.text('Hydraulic Pump 04'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('large text keeps long fault details readable', (tester) async {
    final repository = FixtureFleetRepository();
    await pumpFleet(
      tester,
      const FaultDetailScreen(faultId: 'fault-1'),
      repository,
      role: UserRole.operator,
      textScale: 1.6,
      size: const Size(360, 800),
      language: 'es',
    );
    await captureFleet(tester, '06-fault-large-text-es');
    expect(tester.takeException(), isNull);
  });
}
