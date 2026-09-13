import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/clients/client_capability_gate.dart';
import 'package:vortice_app/features/maintenance/maintenance_asset_screen.dart';
import 'package:vortice_app/features/maintenance/maintenance_list_screen.dart';
import 'package:vortice_app/features/maintenance/maintenance_models.dart';
import 'package:vortice_app/features/maintenance/maintenance_report_screen.dart';
import 'package:vortice_app/features/maintenance/work_list_provider.dart';
import 'package:vortice_app/features/maintenance/planning/planning_models.dart';
import 'package:vortice_app/features/maintenance/planning/planning_repository.dart';
import 'package:vortice_app/features/service_reports/service_report_provider.dart';
import 'package:vortice_app/features/work_orders/work_order_detail_actions_section.dart';
import 'package:vortice_app/features/work_orders/work_order_provider.dart';
import 'package:vortice_app/models/profile.dart';
import 'package:vortice_app/models/service_report.dart';
import 'package:vortice_app/models/work_order.dart';
import '../fleet/fleet_test_support.dart';
import 'maintenance_screen_test.dart'
    show FixtureMaintenance, pumpMaintenance, jobData;

const serviceOrder = WorkOrder(
  id: 'service',
  assetId: 'asset',
  clientId: 'company',
  createdBy: 'owner',
  jobType: WorkOrderJobType.repair,
  status: WorkOrderStatus.inProgress,
  title: 'Pump seal service',
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(loadFleetScreenshotFonts);

  testWidgets(
    'running labour directs report back to timer without submitting',
    (tester) async {
      final data = jobData()
        ..['labour'] = [
          {
            'id': 'timer',
            'actor_id': 'mechanic',
            'started_at': '2026-09-06T12:00:00Z',
          },
        ];
      final repository = FixtureMaintenance(job: data);
      await pumpMaintenance(
        tester,
        MaintenanceReportScreen(job: MaintenanceJob(data)),
        repository,
      );
      final submit = find.widgetWithText(FilledButton, 'Submit for review');
      await tester.scrollUntilVisible(
        submit,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);
      expect(find.text('Open labour timer'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Save draft'),
            )
            .onPressed,
        isNotNull,
      );
      expect(repository.writes, isEmpty);
      await captureFleet(tester, 'simplify-report-timer-en');
    },
  );

  for (final role in [UserRole.owner, UserRole.clientAdmin]) {
    test(
      'work discovery preserves role, asset and assignment scope ($role)',
      () async {
        var providerReads = 0;
        final container = ProviderContainer(
          overrides: [
            profileProvider.overrideWith(
              (_) async => Profile(
                id: 'mechanic',
                email: 'fixture@example.invalid',
                fullName: 'Alex',
                role: role,
              ),
            ),
            maintenancePlanningProvider.overrideWith((_, assetId) async {
              providerReads++;
              expect(assetId, 'asset');
              return PlanningData(
                jobs: [
                  PlanningJob({
                    'id': 'job',
                    'asset_id': 'asset',
                    'title': 'Internal repair',
                    'asset_name': 'Generator 02',
                    'status': 'assigned',
                  }),
                  if (role == UserRole.owner)
                    PlanningJob({
                      'id': 'service',
                      'asset_id': 'asset',
                      'title': 'Provider repair',
                      'asset_name': 'Generator 02',
                      'status': 'assigned',
                      'provider_service': true,
                      'assigned_to_me': true,
                      'route': '/owner/work-orders/service',
                    }),
                ],
                plans: [],
              );
            }),
          ],
        );
        addTearDown(container.dispose);
        final entries = await container.read(workListProvider('asset').future);
        expect(entries.where((e) => !e.service).length, 1);
        expect(entries.where((e) => e.id == 'job').length, 1);
        if (role == UserRole.owner) {
          final service = entries.singleWhere((e) => e.service);
          expect(service.route, '/owner/work-orders/service');
          expect(service.matches('mine', 'generator'), isTrue);
          expect(service.matches('closed', ''), isFalse);
        } else {
          expect(entries.every((e) => !e.service), isTrue);
        }
        expect(providerReads, 1);
      },
    );
  }

  for (final es in [false, true]) {
    testWidgets('asset actions keep work first and edit in menu ($es)', (
      tester,
    ) async {
      await pumpMaintenance(
        tester,
        const MaintenanceAssetScreen(assetId: 'asset'),
        FixtureMaintenance(),
        es: es,
        width: es ? 320 : 390,
        scale: es ? 1.5 : 1,
      );
      final work = es ? 'Ver órdenes' : 'Work orders';
      final edit = es ? 'Editar equipo' : 'Edit asset';
      expect(find.widgetWithText(FilledButton, work), findsOneWidget);
      expect(find.text(edit), findsNothing);
      expect(
        find.text(es ? 'Custodia e inspecciones' : 'Custody & inspections'),
        findsOneWidget,
      );
      await captureFleet(tester, 'simplify-asset-${es ? 'es-large' : 'en'}');
      await tester.tap(find.byTooltip(es ? 'Más acciones' : 'More actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(edit));
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsWidgets);
    });
  }

  testWidgets('combined Work opens each original detail workflow', (
    tester,
  ) async {
    await pumpMaintenance(
      tester,
      const MaintenanceListScreen(),
      FixtureMaintenance(),
      role: UserRole.owner,
      overrides: [
        workListProvider.overrideWith(
          (_, id) async => const [
            WorkListEntry(
              id: 'job',
              title: 'Generator repair',
              assetName: 'Generator 02',
              status: 'assigned',
              route: '/maintenance/jobs/job',
              assignedToMe: true,
              service: false,
            ),
            WorkListEntry(
              id: 'service',
              title: 'Pump seal service',
              assetName: 'Generator 02',
              status: 'in_progress',
              route: '/owner/work-orders/service',
              assignedToMe: false,
              service: true,
            ),
          ],
        ),
      ],
    );
    await captureFleet(tester, 'simplify-work-en');
    await tester.tap(find.text('Assigned to me'));
    await tester.pumpAndSettle();
    expect(find.text('Pump seal service'), findsNothing);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pump seal service'));
    await tester.pumpAndSettle();
    expect(find.text('Work order service'), findsOneWidget);
  });

  for (final state in ['missing', 'submitted', 'loading', 'error']) {
    testWidgets('service report next action reflects $state', (tester) async {
      await pumpMaintenance(
        tester,
        const Scaffold(
          body: WorkOrderDetailActionsSection(
            workOrder: serviceOrder,
            profile: null,
            isOwnerOrEmployee: true,
            isOwner: true,
            routePrefix: '/owner',
            checklistDone: false,
          ),
        ),
        FixtureMaintenance(),
        role: UserRole.owner,
        overrides: [
          currentUserAssignedToWorkOrderProvider.overrideWith(
            (_, id) async => true,
          ),
          clientCapabilityGateProvider.overrideWith((_, scope) async => true),
          serviceReportsByWorkOrderProvider.overrideWith((_, id) {
            if (state == 'loading') {
              return Completer<List<ServiceReport>>().future;
            }
            if (state == 'error') {
              return Future.error(StateError('Could not load'));
            }
            return Future.value(
              state == 'submitted'
                  ? [
                      ServiceReport(
                        id: 'report',
                        workOrderId: 'service',
                        signedAt: DateTime(2026, 9, 6),
                      ),
                    ]
                  : <ServiceReport>[],
            );
          }),
        ],
      );
      final next = find.widgetWithText(
        ElevatedButton,
        state == 'submitted' ? 'Mark Completed' : 'Continue service report',
      );
      expect(next, findsOneWidget);
      expect(
        tester.widget<ElevatedButton>(next).onPressed,
        state == 'loading' || state == 'error' ? isNull : isNotNull,
      );
      if (state == 'missing') {
        await captureFleet(tester, 'simplify-service-next-en');
        await tester.tap(next);
        await tester.pumpAndSettle();
        expect(find.text('Service report service'), findsOneWidget);
      }
      if (state == 'error') {
        expect(find.text('Retry loading reports'), findsOneWidget);
      }
    });
  }
}
