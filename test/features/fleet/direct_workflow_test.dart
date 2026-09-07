import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vortice_app/features/fleet/fault_detail_screen.dart';
import 'package:vortice_app/features/fleet/fleet_models.dart';

import 'package:vortice_app/features/maintenance/maintenance_create_screen.dart';
import 'package:vortice_app/features/maintenance/maintenance_job_screen.dart';
import 'package:vortice_app/features/maintenance/maintenance_report_screen.dart';
import 'package:vortice_app/models/profile.dart';
import 'package:vortice_app/models/service_request.dart';
import 'package:vortice_app/features/service_requests/service_request_provider.dart';
import 'package:vortice_app/features/service_requests/service_request_list_screen.dart';
import '../maintenance/maintenance_screen_test.dart'
    show FixtureMaintenance, pumpMaintenance, jobData;
import 'fleet_test_support.dart';

FixtureFleetRepository faults({
  bool linked = false,
  bool canOpen = true,
  FaultStatus status = FaultStatus.open,
  String jobStatus = 'assigned',
}) => FixtureFleetRepository()
  ..items = [
    FleetFault(
      id: 'fault',
      assetId: 'asset',
      assetName: 'North Harbour — Generator 02',
      description: 'Hydraulic oil leaking from the main pump seal',
      urgent: true,
      status: status,
      canPlanRepair: true,
      revision: 4,
      workOrderId: linked ? 'job' : null,
      workOrderManaged: linked,
      canOpenWorkOrder: canOpen,
      workOrderStatus: linked ? jobStatus : null,
      reporterName: 'Sam Rivera',
    ),
  ];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(loadFleetScreenshotFonts);

  testWidgets('new and assigned work orders each expose the next action', (
    tester,
  ) async {
    final repository = FixtureMaintenance(job: jobData(status: 'draft'));
    await pumpMaintenance(
      tester,
      const MaintenanceJobScreen(jobId: 'job'),
      repository,
    );
    expect(
      find.widgetWithText(FilledButton, 'Assign work order'),
      findsOneWidget,
    );
    expect(find.text('Continue repair report'), findsNothing);
    await tester.tap(find.text('Assign work order'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await pumpMaintenance(
      tester,
      const MaintenanceJobScreen(jobId: 'job'),
      FixtureMaintenance(job: jobData(status: 'assigned')),
    );
    expect(find.widgetWithText(FilledButton, 'Start work'), findsOneWidget);
    expect(find.text('Start labour'), findsNothing);
  });

  for (final es in [false, true]) {
    testWidgets(
      'service request opens its work-order draft with a clear label ($es)',
      (tester) async {
        await pumpMaintenance(
          tester,
          const StaffServiceRequestListScreen(),
          FixtureMaintenance(),
          role: UserRole.owner,
          es: es,
          width: es ? 320 : 390,
          scale: es ? 1.5 : 1,
          overrides: [
            staffServiceRequestsProvider.overrideWith(
              (_) async => [
                const ServiceRequest(
                  id: 'request',
                  clientId: 'client',
                  assetId: 'asset',
                  title: 'Breakdown',
                  description: 'Pump will not hold pressure',
                  urgency: ServiceRequestUrgency.urgent,
                  status: ServiceRequestStatus.newRequest,
                  assetName: 'Pump 04',
                ),
              ],
            ),
          ],
        );
        final label = es ? 'Crear orden de trabajo' : 'Create work order';
        await tester.scrollUntilVisible(
          find.text(label),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Accept + WO'), findsNothing);
        await captureFleet(
          tester,
          es ? 'direct-11-request-es-large' : 'direct-10-request-en',
        );
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(find.text('Request draft: request / asset'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'reported fault leads directly into a prefilled repair workflow',
    (tester) async {
      final repository = FixtureMaintenance();
      await pumpMaintenance(
        tester,
        const FaultDetailScreen(faultId: 'fault'),
        repository,
        fleet: faults(),
      );
      expect(find.text('Start repair'), findsNothing);
      expect(find.text('Assign repair'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Plan repair'), findsOneWidget);
      await captureFleet(tester, 'direct-01-fault-en');
      await tester.tap(find.text('Plan repair'));
      await tester.pumpAndSettle();
      expect(find.byType(MaintenanceCreateScreen), findsOneWidget);
      expect(
        find.text('Hydraulic oil leaking from the main pump seal'),
        findsWidgets,
      );
      expect(find.text('Urgent'), findsOneWidget);
      await captureFleet(tester, 'direct-02-create-en');
      await tester.scrollUntilVisible(
        find.text('Create & open work order'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Create & open work order'));
      await tester.pumpAndSettle();
      expect(repository.writes.single.action, 'plan_fault');
      expect(repository.writes.single.data['asset_id'], 'asset');
      expect(repository.writes.single.data['priority'], 'urgent');
      expect(repository.writes.single.data['fault_id'], 'fault');
      expect(find.text('Job saved'), findsOneWidget);
    },
  );

  testWidgets(
    'link an existing work order without duplicating it, retrying the same input',
    (tester) async {
      final repository = FixtureMaintenance()..failNext = true;
      await pumpMaintenance(
        tester,
        const MaintenanceCreateScreen(faultId: 'fault'),
        repository,
        fleet: faults(),
      );
      await tester.tap(find.byType(DropdownButtonFormField<bool>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Link existing work order').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Link & open work order'));
      await tester.pumpAndSettle();
      expect(find.text('Choose a work order'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('250-hour generator service').last);
      await tester.pumpAndSettle();
      await captureFleet(tester, 'direct-03-link-en');
      await tester.tap(find.text('Link & open work order'));
      await tester.pumpAndSettle();
      expect(find.text('Retry link'), findsOneWidget);
      expect(
        tester
            .widget<DropdownButtonFormField<bool>>(
              find.byType(DropdownButtonFormField<bool>),
            )
            .onChanged,
        isNull,
      );
      await tester.tap(find.text('Retry link'));
      await tester.pumpAndSettle();
      expect(repository.writes.length, 2);
      expect(repository.writes[0].id, repository.writes[1].id);
      expect(repository.writes[0].data, repository.writes[1].data);
      expect(repository.writes[0].data['job_id'], 'job');
      expect(repository.writes[0].data.containsKey('title'), isFalse);
      expect(find.text('Job saved'), findsOneWidget);
    },
  );

  testWidgets(
    'linked managed repair opens company job and hides parallel repair controls',
    (tester) async {
      await pumpMaintenance(
        tester,
        const FaultDetailScreen(faultId: 'fault'),
        FixtureMaintenance(),
        fleet: faults(linked: true),
      );
      expect(find.text('Open work order'), findsOneWidget);
      await tester.tap(find.text('More actions'));
      await tester.pumpAndSettle();
      expect(find.text('Assign repair'), findsNothing);
      expect(find.text('Start repair'), findsNothing);
      expect(find.text('Dismiss with reason'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open work order'));
      await tester.pumpAndSettle();
      expect(find.text('Job saved'), findsOneWidget);
    },
  );

  testWidgets(
    'operator sees linked progress without private work-order entry',
    (tester) async {
      await pumpMaintenance(
        tester,
        const FaultDetailScreen(faultId: 'fault'),
        FixtureMaintenance(),
        role: UserRole.operator,
        fleet: faults(linked: true, canOpen: false),
      );
      expect(find.text('Open work order'), findsNothing);
      expect(find.text('Plan repair'), findsNothing);
      expect(find.text('More actions'), findsNothing);
      expect(
        find.textContaining('Linked work order: Assigned'),
        findsOneWidget,
      );
    },
  );

  testWidgets('job approval is followed by explicit fault verification', (
    tester,
  ) async {
    await pumpMaintenance(
      tester,
      const FaultDetailScreen(faultId: 'fault'),
      FixtureMaintenance(),
      fleet: faults(
        linked: true,
        status: FaultStatus.pendingReview,
        jobStatus: 'closed',
      ),
    );
    expect(
      find.widgetWithText(FilledButton, 'Verify & resolve'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(OutlinedButton, 'Open work order'),
      findsOneWidget,
    );
    expect(find.text('Review asset availability'), findsNothing);
    await captureFleet(tester, 'direct-04-verify-en');
  });

  testWidgets(
    'job report is direct and secondary actions remain available in a menu',
    (tester) async {
      final repository = FixtureMaintenance();
      await pumpMaintenance(
        tester,
        const MaintenanceJobScreen(jobId: 'job'),
        repository,
      );
      await captureFleet(tester, 'direct-05-job-en');
      await tester.ensureVisible(find.text('Continue repair report'));
      await tester.tap(find.text('Continue repair report'));
      await tester.pumpAndSettle();
      expect(find.byType(MaintenanceReportScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('More actions'));
      await tester.tap(find.text('More actions'));
      await tester.pumpAndSettle();
      expect(find.text('Assign job'), findsOneWidget);
      expect(find.text('Block work'), findsOneWidget);
      await tester.tap(find.text('Assign job'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('narrow Spanish workflow actions remain readable at large text', (
    tester,
  ) async {
    await pumpMaintenance(
      tester,
      const FaultDetailScreen(faultId: 'fault'),
      FixtureMaintenance(),
      es: true,
      width: 320,
      scale: 1.5,
      fleet: faults(),
    );
    await tester.scrollUntilVisible(
      find.text('Planificar reparación'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await captureFleet(tester, 'direct-06-fault-es-large');
    await tester.tap(find.text('Planificar reparación'));
    await tester.pumpAndSettle();
    await captureFleet(tester, 'direct-07-create-es-large');
    await tester.scrollUntilVisible(
      find.text('Crear y abrir orden'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await captureFleet(tester, 'direct-08-create-es-large-bottom');
    expect(tester.takeException(), isNull);
  });

  testWidgets('review decisions follow the saved repair report', (
    tester,
  ) async {
    final repository = FixtureMaintenance(
      job: jobData(status: 'pending_review'),
    );
    await pumpMaintenance(
      tester,
      const MaintenanceJobScreen(jobId: 'job'),
      repository,
    );
    await tester.scrollUntilVisible(
      find.text('Review repair report'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Continue repair report'), findsNothing);
    await captureFleet(tester, 'direct-09-review-en');
    await tester.scrollUntilVisible(
      find.text('Return for changes'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Return for changes'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
