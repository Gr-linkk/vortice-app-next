import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vortice_app/features/maintenance/internal_work_order_edit_screen.dart';
import 'package:vortice_app/features/maintenance/maintenance_asset_screen.dart';
import 'package:vortice_app/features/maintenance/maintenance_create_screen.dart';
import 'package:vortice_app/features/maintenance/maintenance_job_screen.dart';
import 'package:vortice_app/features/maintenance/maintenance_models.dart';
import 'package:vortice_app/features/maintenance/maintenance_report_screen.dart';
import 'package:vortice_app/features/service_intervals/maintenance_work_order_draft.dart';
import 'package:vortice_app/models/profile.dart';
import 'package:vortice_app/models/work_order.dart';
import '../fleet/fleet_test_support.dart';
import 'maintenance_screen_test.dart'
    show FixtureMaintenance, jobData, pumpMaintenance;

Map<String, dynamic> orderData() => {
  ...jobData(status: 'assigned'),
  'service_interval_id': null,
  'job_type': 'general',
  'title': 'Prepare generator for seasonal operation',
  'expected_materials': 'Oil, filters and absorbent pads',
  'labour': <Map<String, dynamic>>[],
  'checklist_snapshot': <Map<String, dynamic>>[],
};

Finder field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Future<void> reveal(WidgetTester tester, Finder target) async {
  final scroll = find
      .descendant(
        of: find.byType(ListView).last,
        matching: find.byType(Scrollable),
      )
      .first;
  if (target.evaluate().isEmpty) {
    final state = tester.state<ScrollableState>(scroll);
    state.position.jumpTo(state.position.minScrollExtent);
    await tester.pump();
    await tester.scrollUntilVisible(target, 220, scrollable: scroll);
  }
  await Scrollable.ensureVisible(tester.element(target.last), alignment: .5);
  await tester.pumpAndSettle();
}

Future<void> fill(WidgetTester tester, String label, String value) async {
  await reveal(tester, field(label));
  await tester.enterText(field(label), value);
  await tester.pump();
}

Future<void> pick(WidgetTester tester, String label, String value) async {
  final input = find.byWidgetPredicate(
    (widget) =>
        widget is InputDecorator && widget.decoration.labelText == label,
  );
  await reveal(tester, input);
  await tester.tap(input);
  await tester.pumpAndSettle();
  await tester.tap(find.text(value).last);
  await tester.pumpAndSettle();
}

Future<void> openEdit(WidgetTester tester, FixtureMaintenance fixture) async {
  await pumpMaintenance(
    tester,
    Builder(
      builder: (context) => Scaffold(
        body: FilledButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) =>
                  InternalWorkOrderEditScreen(job: MaintenanceJob(fixture.job)),
            ),
          ),
          child: const Text('Open editor'),
        ),
      ),
    ),
    fixture,
  );
  await tester.tap(find.text('Open editor'));
  await tester.pumpAndSettle();
}

class StaleOrder extends FixtureMaintenance {
  StaleOrder() : super(job: orderData());
  @override
  Future<void> change(
    String jobId,
    int revision,
    String operationId,
    String action,
    Map<String, dynamic> data,
  ) async {
    record(operationId, action, data);
    throw const PostgrestException(
      message: 'This work order changed; refresh before editing',
      code: '40001',
    );
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(loadFleetScreenshotFonts);
  for (final type in WorkOrderJobType.values) {
    test(
      '${type.dbValue} survives provider JSON and work-order draft routing',
      () {
        final order = WorkOrder.fromJson({
          'id': 'job',
          'asset_id': 'asset',
          'client_id': 'company',
          'created_by': 'manager',
          'status': 'draft',
          'title': 'Internal work',
          'job_type': type.dbValue,
        });
        expect(order.jobType, type);
        expect(order.toJson()['job_type'], type.dbValue);
        final draft = MaintenanceWorkOrderDraft(
          jobType: type,
          checklistTemplateId: 'template',
        );
        expect(
          MaintenanceWorkOrderDraft.fromQueryParameters(
            draft.toQueryParameters(),
          ).jobType,
          type,
        );
      },
    );
  }
  test(
    'scope editing closes once work has started, including historical labour',
    () {
      expect(MaintenanceJob(orderData()).canPrepare, isTrue);
      expect(
        MaintenanceJob({
          ...orderData(),
          'started_at': '2026-09-07T08:00:00Z',
        }).canPrepare,
        isFalse,
      );
      expect(
        MaintenanceJob({
          ...orderData(),
          'labour': jobData()['labour'],
        }).canPrepare,
        isFalse,
      );
      expect(
        MaintenanceJob({...orderData(), 'can_manage': false}).canPrepare,
        isFalse,
      );
      expect(
        MaintenanceJob({...orderData(), 'can_work': false}).canPrepare,
        isFalse,
      );
      expect(
        MaintenanceJob({...orderData(), 'status': 'pending_review'}).canPrepare,
        isFalse,
      );
    },
  );
  testWidgets(
    'company manager creates an inspection with checklist and expected materials',
    (tester) async {
      final fixture = FixtureMaintenance(job: orderData());
      await pumpMaintenance(
        tester,
        const MaintenanceCreateScreen(assetId: 'asset'),
        fixture,
        role: UserRole.client,
      );
      expect(find.text('New work order'), findsOneWidget);
      await fill(tester, 'Work order title', 'Inspect generator mountings');
      await pick(tester, 'Work type', 'Inspection');
      await pick(
        tester,
        'Checklist (optional)',
        'Generator maintenance checklist',
      );
      await fill(tester, 'Expected parts / materials', 'Torque wrench');
      final save = find.widgetWithText(FilledButton, 'Create work order');
      await reveal(tester, save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(
        fixture.writes.single.data,
        containsPair('job_type', 'inspection'),
      );
      expect(
        fixture.writes.single.data,
        containsPair('checklist_template_id', 'template'),
      );
      expect(
        fixture.writes.single.data,
        containsPair('expected_materials', 'Torque wrench'),
      );
      expect(fixture.writes.single.data['service_interval_id'], isNull);
      expect(find.text('Job saved'), findsOneWidget);
    },
  );
  testWidgets(
    'service-plan entry fixes the type and preserves interval linkage',
    (tester) async {
      final fixture = FixtureMaintenance();
      await pumpMaintenance(
        tester,
        const MaintenanceCreateScreen(assetId: 'asset', planId: 'plan'),
        fixture,
      );
      expect(find.text('Preventive maintenance'), findsOneWidget);
      final type = find.byWidgetPredicate(
        (widget) => widget is DropdownButtonFormField<WorkOrderJobType>,
      );
      expect(
        tester
            .widget<DropdownButtonFormField<WorkOrderJobType>>(type)
            .onChanged,
        isNull,
      );
      final save = find.widgetWithText(FilledButton, 'Create work order');
      await reveal(tester, save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(fixture.writes.single.data['job_type'], 'preventative');
      expect(fixture.writes.single.data['service_interval_id'], 'plan');
    },
  );
  testWidgets(
    'uncertain scope edit freezes and retries exactly one input identity',
    (tester) async {
      final fixture = FixtureMaintenance(job: orderData())..failNext = true;
      await openEdit(tester, fixture);
      await fill(tester, 'Work order title', 'Prepare the full generator bay');
      await fill(
        tester,
        'Reason for change',
        'Add access preparation before shutdown',
      );
      final save = find.widgetWithText(FilledButton, 'Save work order');
      await reveal(tester, save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      await reveal(tester, field('Work order title'));
      expect(
        tester.widget<TextField>(field('Work order title')).enabled,
        isFalse,
      );
      final retry = find.widgetWithText(FilledButton, 'Retry same save');
      await reveal(tester, retry);
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(fixture.writes, hasLength(2));
      expect(fixture.writes[0].id, fixture.writes[1].id);
      expect(fixture.writes[0].data, fixture.writes[1].data);
      expect(fixture.writes[0].action, 'edit_details');
    },
  );
  testWidgets(
    'stale editing offers explicit discard without overwriting fresh work',
    (tester) async {
      final fixture = StaleOrder();
      await openEdit(tester, fixture);
      await fill(tester, 'Reason for change', 'Revise preparation');
      final save = find.widgetWithText(FilledButton, 'Save work order');
      await reveal(tester, save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.text('Discard edits and reload'), findsOneWidget);
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      expect(fixture.writes, hasLength(1));
    },
  );
  testWidgets('inspection report and approval do not describe a repair', (
    tester,
  ) async {
    final job = MaintenanceJob({
      ...orderData(),
      'job_type': 'inspection',
      'status': 'in_progress',
    });
    await pumpMaintenance(
      tester,
      MaintenanceReportScreen(job: job),
      FixtureMaintenance(job: job.data),
    );
    expect(field('Findings'), findsOneWidget);
    expect(field('Work performed and results'), findsOneWidget);
    expect(find.text('Repair and test results'), findsNothing);
    expect(maintenanceApprovalDescription(job, false), contains('work order'));
    await fill(tester, 'Findings', 'Inspection complete; no damage found.');
    await fill(
      tester,
      'Work performed and results',
      'Inspected and tested operation.',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await captureFleet(tester, 'internal17-report-en');
  });
  for (final es in [false, true]) {
    testWidgets(
      'native internal work-order screens ${es ? 'Spanish large text' : 'English'}',
      (tester) async {
        final fixture = FixtureMaintenance(job: orderData());
        await pumpMaintenance(
          tester,
          const MaintenanceAssetScreen(assetId: 'asset'),
          fixture,
          es: es,
          width: es ? 360 : 390,
          scale: es ? 1.35 : 1,
        );
        await captureFleet(
          tester,
          es ? 'internal-asset-es' : 'internal-asset-en',
        );
        await pumpMaintenance(
          tester,
          const MaintenanceCreateScreen(assetId: 'asset'),
          fixture,
          es: es,
          width: es ? 360 : 390,
          scale: es ? 1.35 : 1,
        );
        expect(
          find.text(es ? 'Nueva orden' : 'New work order'),
          findsOneWidget,
        );
        await fill(
          tester,
          es ? 'Título de la orden' : 'Work order title',
          es
              ? 'Preparar el generador para la temporada'
              : 'Prepare generator for seasonal operation',
        );
        await captureFleet(
          tester,
          es ? 'internal17-create-es' : 'internal17-create-en',
        );
        await reveal(
          tester,
          field(
            es
                ? 'Repuestos y materiales previstos'
                : 'Expected parts / materials',
          ),
        );
        await captureFleet(
          tester,
          es ? 'internal17-create-bottom-es' : 'internal17-create-bottom-en',
        );
        await pumpMaintenance(
          tester,
          const MaintenanceJobScreen(jobId: 'job'),
          fixture,
          es: es,
          width: es ? 360 : 390,
          scale: es ? 1.35 : 1,
        );
        await captureFleet(
          tester,
          es ? 'internal-details-es' : 'internal-details-en',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
