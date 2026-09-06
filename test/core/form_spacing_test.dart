import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/app_shell.dart';
import 'package:vortice_app/core/app_dropdown_field.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/clients/client_capability_gate.dart';
import 'package:vortice_app/features/maintenance/maintenance_create_screen.dart';
import 'package:vortice_app/models/profile.dart';
import 'package:vortice_app/models/asset.dart';
import 'package:vortice_app/models/checklist_template.dart';
import 'package:vortice_app/features/operator/operator_checklist_selection_step.dart';
import 'package:vortice_app/features/service_requests/service_request_form_asset_field.dart';
import 'package:vortice_app/features/maintenance/maintenance_job_screen.dart';
import '../features/maintenance/maintenance_screen_test.dart';
import '../features/fleet/fleet_test_support.dart';

void main() {
  setUpAll(loadFleetScreenshotFonts);
  testWidgets('legacy asset and checklist menus fit narrow large-text forms', (
    tester,
  ) async {
    const asset = Asset(
      id: 'asset',
      clientId: 'company',
      assetTypeId: 'type',
      name: 'Generador auxiliar de estribor para servicios de emergencia',
    );
    const template = ChecklistTemplate(
      id: 'template',
      name: 'Inspección diaria del sistema de refrigeración y seguridad',
      checklistType: 'operator_daily',
    );
    String? requestedAsset;
    ChecklistTemplate? selectedTemplate;
    await pumpMaintenance(
      tester,
      Scaffold(
        body: SingleChildScrollView(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: ServiceRequestFormAssetField(
                  assets: const [asset],
                  value: asset.id,
                  onChanged: (value) => requestedAsset = value,
                ),
              ),
              OperatorChecklistSelectionStep(
                assetsAsync: AsyncData([
                  {'id': 'asset', 'name': asset.name},
                ]),
                templatesAsync: const AsyncData([template]),
                selectedAsset: const {'id': 'asset'},
                selectedTemplate: template,
                onAssetSelected: (_) {},
                onTemplateSelected: (value) => selectedTemplate = value,
              ),
            ],
          ),
        ),
      ),
      FixtureMaintenance(),
      es: true,
      width: 320,
      scale: 1.5,
    );
    expect(tester.takeException(), isNull);
    await captureFleet(tester, 'form-legacy-selectors-es-large');
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await captureFleet(tester, 'form-service-asset-menu-es-large');
    await tester.tap(find.text('Other').last);
    await tester.pumpAndSettle();
    expect(requestedAsset, isNotNull);
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    final menuText = find.descendant(
      of: find.byType(Scrollable).last,
      matching: find.text(template.name),
    );
    expect(
      tester.renderObject<RenderParagraph>(menuText).didExceedMaxLines,
      isFalse,
    );
    await captureFleet(tester, 'form-checklist-menu-es-large');
    await tester.tap(menuText);
    await tester.pumpAndSettle();
    expect(selectedTemplate, template);
    expect(tester.takeException(), isNull);
  });

  testWidgets('parts dialog separates fields and scrolls above the keyboard', (
    tester,
  ) async {
    await pumpMaintenance(
      tester,
      const MaintenanceJobScreen(jobId: 'job'),
      FixtureMaintenance(),
      es: true,
      width: 320,
      scale: 1.5,
    );
      await tester.scrollUntilVisible(
        find.text('Añadir repuesto'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('Añadir repuesto'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Añadir repuesto'));
    await tester.pumpAndSettle();
    final fields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    expect(fields, findsNWidgets(4));
    for (var i = 1; i < 4; i++) {
      expect(
        tester.getRect(fields.at(i)).top -
            tester.getRect(fields.at(i - 1)).bottom,
        greaterThanOrEqualTo(16),
      );
    }
    await captureFleet(tester, 'form-parts-dialog-es-large');
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.tap(fields.first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(fields.last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await captureFleet(tester, 'form-parts-dialog-keyboard-es-large');
  });

  testWidgets(
    'maintenance dropdowns have visible gaps with and without a plan',
    (tester) async {
      await pumpMaintenance(
        tester,
        const MaintenanceCreateScreen(assetId: 'asset'),
        FixtureMaintenance(),
      );
      final plan = find.byKey(const ValueKey('plan-asset'));
      final component = find.byKey(const ValueKey('component-asset'));
      final assignee = find.byKey(const ValueKey('assignee-asset'));
      await tester.scrollUntilVisible(
        plan,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(assignee);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(component).top - tester.getRect(plan).bottom,
        greaterThanOrEqualTo(16),
      );
      expect(
        tester.getRect(assignee).top - tester.getRect(component).bottom,
        greaterThanOrEqualTo(16),
      );
      await captureFleet(tester, 'form-maintenance-fields');
      await tester.tap(plan);
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('250-hour service · Auxiliary generator').last,
      );
      await tester.pumpAndSettle();
      expect(component, findsNothing);
      expect(
        tester.getRect(assignee).top - tester.getRect(plan).bottom,
        greaterThanOrEqualTo(16),
      );
    },
  );

  testWidgets(
    'dropdown menus wrap long labels and preserve selection at large text',
    (tester) async {
      const label =
          'Generador auxiliar de estribor — revisión completa del sistema de refrigeración';
      String? selected;
      await pumpMaintenance(
        tester,
        Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: StatefulBuilder(
              builder: (context, setState) => AppDropdownField<String>(
                initialValue: selected,
                decoration: const InputDecoration(
                  labelText: 'Plan de servicio',
                ),
                items: [
                  const DropdownMenuItem(value: 'long', child: Text(label)),
                  for (var i = 0; i < 12; i++)
                    DropdownMenuItem(
                      value: '$i',
                      child: Text('Plan de mantenimiento ${i + 1}'),
                    ),
                ],
                onChanged: (value) => setState(() => selected = value),
              ),
            ),
          ),
        ),
        FixtureMaintenance(),
        es: true,
        width: 320,
        scale: 1.5,
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final menuText = find.descendant(
        of: find.byType(Scrollable).last,
        matching: find.text(label),
      );
      final paragraph = tester.renderObject<RenderParagraph>(menuText);
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(tester.getSize(menuText).height, greaterThan(48));
      await captureFleet(tester, 'form-dropdown-menu-es-large');
      await tester.tap(menuText);
      await tester.pumpAndSettle();
      expect(selected, 'long');
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(DropdownButtonFormField<String>)).height,
        lessThan(100),
      );
      await captureFleet(tester, 'form-dropdown-selected-es-large');
    },
  );

  testWidgets('dropdown validation and disabled selection remain usable', (
    tester,
  ) async {
    final form = GlobalKey<FormState>();
    bool disabled = false;
    await pumpMaintenance(
      tester,
      Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: StatefulBuilder(
            builder: (context, setState) => Form(
              key: form,
              child: Column(
                spacing: 16,
                children: [
                  AppDropdownField<String>(
                    decoration: const InputDecoration(labelText: 'Responsable'),
                    items: const [
                      DropdownMenuItem(
                        value: 'a',
                        child: Text('Mecánico responsable'),
                      ),
                    ],
                    onChanged: disabled ? null : (_) {},
                    validator: (value) => value == null
                        ? 'Selecciona un responsable para continuar.'
                        : null,
                  ),
                  FilledButton(
                    onPressed: () => form.currentState!.validate(),
                    child: const Text('Guardar'),
                  ),
                  TextButton(
                    onPressed: () => setState(() => disabled = true),
                    child: const Text('Deshabilitar'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      FixtureMaintenance(),
      es: true,
      width: 320,
      scale: 1.5,
    );
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(
      find.text('Selecciona un responsable para continuar.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await captureFleet(tester, 'form-dropdown-validation-es-large');
    await tester.tap(find.text('Deshabilitar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    expect(find.byType(Scrollable), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'forms in the app shell keep bottom actions above Android navigation',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const profile = Profile(
        id: 'manager',
        email: 'fixture@example.invalid',
        fullName: 'Manager',
        role: UserRole.clientAdmin,
      );
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => MediaQuery(
              data: const MediaQueryData(
                size: Size(390, 844),
                padding: EdgeInsets.only(bottom: 24),
                viewPadding: EdgeInsets.only(bottom: 24),
              ),
              child: AppShell(
                location: '/maintenance/new',
                child: Scaffold(
                  body: Align(
                    alignment: Alignment.bottomCenter,
                    child: FilledButton(
                      key: const Key('save-action'),
                      onPressed: () {},
                      child: const Text('Save'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStatusProvider.overrideWithValue(
              const AppAuthStatus(
                isLoading: false,
                isAuthenticated: true,
                profile: profile,
              ),
            ),
            clientCapabilityGateProvider.overrideWith((_, __) async => false),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(const Key('save-action'))).bottom,
        lessThanOrEqualTo(820),
      );
    },
  );
}
