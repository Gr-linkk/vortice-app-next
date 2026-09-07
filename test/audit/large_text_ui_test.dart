import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/org_codes/org_code_provider.dart';
import 'package:vortice_app/features/org_codes/org_code_screen.dart';
import 'package:vortice_app/features/clients/client_capability_gate.dart';
import 'package:vortice_app/features/telemetry/telemetry_history_screen.dart';
import 'package:vortice_app/features/telemetry/telemetry_provider.dart';
import 'package:vortice_app/features/assets/asset_provider.dart';
import 'package:vortice_app/features/checklists/checklist_provider.dart';
import 'package:vortice_app/features/parts/pm_parts_provider.dart';
import 'package:vortice_app/features/work_orders/create_work_order_form.dart';
import 'package:vortice_app/features/work_orders/work_order_provider.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/models/asset.dart';
import 'package:vortice_app/models/checklist_template.dart';
import 'package:vortice_app/models/pm_parts_requirement.dart';
import 'package:vortice_app/models/work_order.dart';
import '../features/fleet/fleet_test_support.dart';

Future<void> pumpAuditScreen(
  WidgetTester tester,
  Widget screen, {
  required String language,
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = const Size(320, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        locale: Locale(language),
        theme: AppTheme.lightTheme,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: RepaintBoundary(
            key: const Key('fleet-capture'),
            child: child!,
          ),
        ),
        home: screen,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await loadFleetScreenshotFonts();
    final monoPath = Platform.environment['VORTICE_MONOSPACE_FONT'];
    final mono = FontLoader('monospace')
      ..addFont(
        monoPath == null
            ? rootBundle.load('assets/fonts/Roboto-Regular.ttf')
            : File(monoPath).readAsBytes().then(ByteData.sublistView),
      );
    await mono.load();
  });
  for (final language in ['en', 'es']) {
    testWidgets(
      'org code remains readable at 320px and 200% text in $language',
      (tester) async {
        await pumpAuditScreen(
          tester,
          const OrgCodeScreen(),
          language: language,
          overrides: [
            orgCodesProvider.overrideWith(
              (ref) async => [
                OrgCode(
                  id: 'fixture',
                  code: 'ABCD2345',
                  intendedRole: 'employee',
                  maxUses: 12,
                  useCount: 2,
                  expiresAt: DateTime(2030, 9, 30),
                  notes: language == 'es'
                      ? 'Acceso para el equipo de mantenimiento'
                      : 'Access for the maintenance team',
                ),
              ],
            ),
          ],
        );
        expect(tester.takeException(), isNull);
        expect(find.text('ABCD2345'), findsOneWidget);
        final addIcon = tester.element(find.byIcon(Icons.add));
        final foreground = IconTheme.of(addIcon).color!.computeLuminance();
        final background = tester
            .widget<FloatingActionButton>(find.byType(FloatingActionButton))
            .backgroundColor!
            .computeLuminance();
        final contrast = foreground > background
            ? (foreground + .05) / (background + .05)
            : (background + .05) / (foreground + .05);
        expect(
          contrast,
          greaterThanOrEqualTo(3),
          reason: 'The add action must remain visible against its background.',
        );
        await captureFleet(tester, 'org-code-$language-200');
      },
    );
    testWidgets(
      'telemetry date range remains usable at 320px and 200% text in $language',
      (tester) async {
        await pumpAuditScreen(
          tester,
          const TelemetryHistoryScreen(assetId: 'fixture'),
          language: language,
          overrides: [
            clientCapabilityGateProvider.overrideWith(
              (ref, request) async => true,
            ),
            telemetryHistoryForAssetProvider.overrideWith(
              (ref, request) async => [],
            ),
            allAlertsForAssetProvider.overrideWith((ref, asset) async => []),
          ],
        );
        expect(tester.takeException(), isNull);
        await captureFleet(tester, 'telemetry-$language-200');
        await tester.tap(find.text(language == 'es' ? 'Cambiar' : 'Change'));
        await tester.pumpAndSettle();
        expect(find.byType(DateRangePickerDialog), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      'work order form localizes every section and retains actions at 200% in $language',
      (tester) async {
        final es = language == 'es';
        final controllers = List.generate(4, (_) => TextEditingController());
        for (final controller in controllers) {
          addTearDown(controller.dispose);
        }
        var assignments = 0;
        var submissions = 0;
        var selectedTechIds = <String>[];
        String? engineId;
        final formKey = GlobalKey<FormState>();
        final form = StatefulBuilder(
          builder: (context, update) => CreateWorkOrderForm(
            formKey: formKey,
            titleCtrl: controllers[0],
            descCtrl: controllers[1],
            hoursCtrl: controllers[2],
            partsCtrl: controllers[3],
            jobType: WorkOrderJobType.preventative,
            selectedAssetId: 'asset',
            selectedEngineId: engineId,
            selectedTechIds: selectedTechIds,
            selectedChecklistTemplateId: 'template',
            scheduledDate: null,
            isLoading: false,
            onJobTypeChanged: (_) {},
            onAssetChanged: (_) {},
            onEngineChanged: (value) => update(() => engineId = value),
            onChecklistTemplateChanged: (_) {},
            onPickScheduledDate: () {},
            onClearScheduledDate: () {},
            onPickTechnicians: (_) async {
              assignments++;
              update(() => selectedTechIds = ['tech']);
            },
            onSubmit: () {
              submissions++;
            },
          ),
        );
        var failTemplates = false;
        List<Override> formOverrides() => [
          visibleAssetsProvider.overrideWith(
            (ref) async => [
              const Asset(
                id: 'asset',
                clientId: 'client',
                assetTypeId: 'type',
                name: 'Generator 4',
              ),
            ],
          ),
          assetEnginesProvider.overrideWith(
            (ref, asset) async => [
              {'id': 'engine', 'kind': 'port'},
            ],
          ),
          assignableWorkOrderProfilesProvider.overrideWith(
            (ref, client) async => [
              {'id': 'tech', 'full_name': ''},
            ],
          ),
          checklistTemplatesProvider.overrideWith((ref) async {
            if (failTemplates) throw StateError('fixture unavailable');
            return [const ChecklistTemplate(id: 'template', name: 'PM 500')];
          }),
          pmPartsRequirementsProvider.overrideWith(
            (ref, template) async => [
              PmPartsRequirement(
                id: 'part',
                templateId: 'template',
                description: es ? 'Filtro de aceite' : 'Oil filter',
              ),
            ],
          ),
        ];
        await pumpAuditScreen(
          tester,
          Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: form,
            ),
          ),
          language: language,
          overrides: formOverrides(),
        );
        expect(
          find.text(es ? 'DETALLES DEL TRABAJO' : 'JOB DETAILS'),
          findsOneWidget,
        );
        expect(
          find.text(es ? 'Motor / Posición' : 'Engine / Position'),
          findsOneWidget,
        );
        expect(
          find.text(
            es ? 'Plantilla de lista de verificación' : 'Checklist Template',
          ),
          findsOneWidget,
        );
        expect(find.text(es ? 'ASIGNACIÓN' : 'ASSIGNMENT'), findsOneWidget);
        expect(find.text(es ? 'PROGRAMACIÓN' : 'SCHEDULING'), findsOneWidget);
        expect(find.text(es ? 'NOTAS' : 'NOTES'), findsOneWidget);
        expect(
          find.text(es ? 'Horas actuales del motor' : 'Current Engine Hours'),
          findsOneWidget,
        );
        expect(
          find.text(
            es ? 'Piezas / Materiales previstos' : 'Parts / Materials Expected',
          ),
          findsOneWidget,
        );
        expect(
          find.text(es ? 'Piezas necesarias' : 'Parts required'),
          findsOneWidget,
        );
        expect(
          find.text(
            es
                ? 'Aún no hay técnicos asignados'
                : 'No technicians assigned yet',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        final engineChoice = find.text(es ? 'Ninguno' : 'None').hitTestable();
        await tester.ensureVisible(engineChoice);
        await tester.tap(engineChoice);
        await tester.pumpAndSettle();
        final engineLabel = find
            .text(es ? 'Motor de babor' : 'Port Engine')
            .last;
        await tester.tap(engineLabel);
        await tester.pumpAndSettle();
        expect(engineId, 'engine');
        await captureFleet(tester, 'work-order-$language-200-top');
        final assign = find.text(
          es ? 'Asignar técnicos' : 'Assign technicians',
        );
        await tester.ensureVisible(assign);
        await tester.tap(assign);
        await tester.pumpAndSettle();
        expect(assignments, 1);
        expect(
          find.text(es ? 'Asignados (1)' : 'Assigned (1)'),
          findsOneWidget,
        );
        expect(
          find.text(es ? 'Técnico sin nombre' : 'Unnamed tech'),
          findsOneWidget,
        );
        await captureFleet(tester, 'work-order-$language-200-assignment');
        final submit = find.widgetWithText(
          ElevatedButton,
          es ? 'Crear orden' : 'Create Work Order',
        );
        await tester.ensureVisible(submit);
        await tester.pumpAndSettle();
        await captureFleet(tester, 'work-order-$language-200-bottom');
        await tester.tap(submit);
        expect(submissions, 1);
        expect(tester.takeException(), isNull);
        final container = ProviderScope.containerOf(
          tester.element(find.byType(CreateWorkOrderForm)),
        );
        failTemplates = true;
        container.invalidate(checklistTemplatesProvider);
        await tester.pumpAndSettle();
        expect(
          find.text(
            es
                ? 'No se pudieron cargar las plantillas'
                : 'Could not load templates',
          ),
          findsOneWidget,
        );
      },
    );
  }
}
