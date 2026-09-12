import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Session;
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/membership/organization_provider_work_panel.dart';
import 'package:vortice_app/features/membership/organization_work_execution.dart';
import 'package:vortice_app/features/membership/organization_work_provider.dart';
import 'package:vortice_app/features/parts/parts_readiness_models.dart';
import 'package:vortice_app/features/parts/parts_readiness_repository.dart';
import 'package:vortice_app/features/service_reports/service_report_form_sections.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/sync/online_action_gate.dart';
import '../agent_access/agent_mfa_test.dart' show session;
import '../fleet/fleet_test_support.dart'
    show captureFleet, loadFleetScreenshotFonts;

class ExecutionFixture extends OrganizationWorkRepository {
  Map<String, dynamic> data = {
    'work_order': {
      'id': 'work',
      'asset_id': 'asset',
      'provider_organization_id': 'provider',
      'status': 'in_progress',
      'title': 'Verify truck pressure repair',
      'description': 'Pressure falls under load',
      'engine_id': 'meter',
      'meter_unit': 'km',
      'hours_at_start': 62000,
      'hours_at_end': 62010,
      'started_at': '2026-09-12T10:00:00Z',
    },
    'revision': 3,
    'asset_name': 'Truck 28',
    'provider_name': 'Workshop',
    'customer_name': 'Harbour Fleet',
    'is_provider': true,
    'can_work': true,
    'can_manage': true,
    'can_bill': false,
    'people': [],
    'parts': [],
    'report': {
      'id': 'report',
      'diagnosis': 'Pressure seal failed',
      'repair': 'Replaced seal and verified pressure',
      'notes': '',
    },
    'labour_hours': 1.25,
    'labour': [
      {
        'id': 'timer',
        'actor_id': 'actor',
        'actor_name': 'Morgan Mechanic',
        'started_at': DateTime.now()
            .subtract(const Duration(minutes: 5))
            .toUtc()
            .toIso8601String(),
        'stopped_at': null,
      },
    ],
    'checklist_name': 'Pressure verification',
    'procedure_notes':
        'Isolate before repair. Verify pressure after restarting.',
    'checklist_snapshot': [
      {
        'id': 'step',
        'template_id': 'template',
        'description_en': 'Verify repaired pressure',
        'description_es': 'Verificar la presión después de la reparación',
        'requires_photo': true,
        'definition': {
          'input_type': 'number',
          'min': 2,
          'max': 4,
          'unit': 'bar',
          'equipment_state': 'verification',
        },
      },
    ],
    'answers': {
      'step': {
        'result': 'fail',
        'note': '1',
        'photo_path': 'work/actor/pressure.jpg',
      },
    },
    'evidence_paths': ['work/actor/pressure.jpg'],
    'sources': [],
  };
  final calls = <Map<String, dynamic>>[];
  bool failNext = false;
  @override
  Future<Map<String, dynamic>> context(String id) async =>
      Map<String, dynamic>.from(jsonDecode(jsonEncode(data)) as Map);
  @override
  Future<void> changeOperation(
    String id,
    int revision,
    String operation,
    String action,
    Map<String, dynamic> values,
  ) async {
    calls.add({
      'id': operation,
      'action': action,
      'data': jsonDecode(jsonEncode(values)),
    });
    if (failNext) {
      failNext = false;
      throw TimeoutException('Uncertain response');
    }
    data['revision'] = (data['revision'] as int) + 1;
    final order = data['work_order'] as Map;
    if (action == 'pause') {
      for (final row in data['labour'] as List) {
        row['stopped_at'] = DateTime.now().toUtc().toIso8601String();
      }
    }
    if (action == 'submit' || action == 'save_report') {
      data['report'] = {
        'id': 'report',
        'diagnosis': values['diagnosis'],
        'repair': values['repair'],
        'notes': values['notes'],
      };
      data['answers'] = values['answers'];
      data['evidence_paths'] = values['evidence_paths'];
      if (action == 'submit') {
        order['status'] = 'pending_review';
        data['returned_at'] = null;
        data['review_note'] = null;
      }
    }
    if (action == 'approve') {
      order['status'] = 'closed';
      data['report'] = {
        ...data['report'] as Map,
        'checklist_snapshot': data['checklist_snapshot'],
        'answers': data['answers'],
        'evidence_paths': data['evidence_paths'],
      };
    }
    if (action == 'return') {
      order['status'] = 'in_progress';
      data['review_note'] = values['note'];
    }
  }

  @override
  Future<Uint8List> evidence(String path) async => base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aHd8AAAAASUVORK5CYII=',
  );
}

Widget app(
  ExecutionFixture fixture, {
  bool spanish = false,
  bool dark = false,
  double scale = 1,
  Widget? home,
  String actor = 'actor',
}) => ProviderScope(
  overrides: [
    sessionProvider.overrideWithValue(
      Session.fromJson(jsonDecode(jsonEncode(session(actor)))),
    ),
    organizationWorkRepositoryProvider.overrideWithValue(fixture),
    organizationWorkOrderContextProvider(
      'work',
    ).overrideWith((ref) => fixture.context('work')),
    partsWorkspaceProvider('work').overrideWith(
      (ref) async => PartsWorkspace({
        'can_manage': true,
        'can_change': true,
        'can_issue': true,
        'stock': [],
        'requirements': [],
        'events': [],
        'purchases': [],
      }),
    ),
    onlineActionGateProvider.overrideWith(
      (ref) => OnlineActionGate(
        account: actor,
        currentAccount: () => actor,
        probe: () async {},
      ),
    ),
  ],
  child: RepaintBoundary(
    key: const Key('fleet-capture'),
    child: MaterialApp(
      theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
      debugShowCheckedModeBanner: false,
      locale: Locale(spanish ? 'es' : 'en'),
      supportedLocales: const [Locale('en'), Locale('es')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: home ?? const OrganizationProviderWorkPanel(workOrderId: 'work'),
    ),
  ),
);

Future<void> reveal(
  WidgetTester tester,
  Finder finder, {
  double delta = 250,
}) async {
  await tester.scrollUntilVisible(
    finder,
    delta,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await loadFleetScreenshotFonts();
    final font = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await font.load();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'return reason remains mounted through the closing sheet animation',
    (tester) async {
      final fixture = ExecutionFixture();
      (fixture.data['work_order'] as Map)['status'] = 'pending_review';
      await tester.pumpWidget(app(fixture));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Return for changes'));
      await tester.tap(find.text('Return for changes'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'Add pressure verification.',
      );
      tester.testTextInput.hide();
      await tester.pump();
      await tester.tap(find.text('Return report'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(fixture.calls.single['action'], 'return');
      expect(fixture.calls.single['data'], {
        'note': 'Add pressure verification.',
      });
    },
  );
  testWidgets(
    'timer, required checklist, exact retry, review and approved customer view share one order',
    (tester) async {
      final fixture = ExecutionFixture();
      await tester.pumpWidget(app(fixture));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Pause my labour'));
      await tester.tap(find.text('Pause my labour'));
      await tester.pumpAndSettle();
      expect(fixture.calls.single['action'], 'pause');
      await reveal(tester, find.text('Continue service report'));
      await tester.tap(find.text('Continue service report'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Submit for review'));
      await tester.tap(find.text('Submit for review'));
      await tester.pumpAndSettle();
      expect(
        fixture.calls.length,
        1,
        reason: 'failed checklist must stay incomplete',
      );
      final reading = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Reading',
      );
      await reveal(tester, reading, delta: -250);
      await tester.enterText(reading, '3');
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Submit for review'));
      fixture.failNext = true;
      await tester.tap(find.text('Submit for review'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Retry request'));
      await tester.tap(find.text('Retry request'));
      await tester.pumpAndSettle();
      expect(fixture.calls[1]['id'], fixture.calls[2]['id']);
      final sent = fixture.calls[2]['data'] as Map;
      expect((sent['answers'] as Map)['step']['note'], '3');
      expect(sent['evidence_paths'], ['work/actor/pressure.jpg']);
      expect(sent['meter_unit'], 'km');
      expect((fixture.data['work_order'] as Map)['status'], 'pending_review');
      await reveal(tester, find.text('Approve and share report'));
      await tester.tap(find.text('Approve and share report'));
      await tester.pumpAndSettle();
      expect((fixture.data['work_order'] as Map)['status'], 'closed');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      fixture.data['is_provider'] = false;
      fixture.data['can_manage'] = false;
      fixture.data['can_work'] = false;
      fixture.data.remove('labour');
      fixture.data.remove('labour_hours');
      fixture.data['parts'] = null;
      await tester.pumpWidget(app(fixture, actor: 'customer'));
      await tester.pumpAndSettle();
      expect(find.byType(OrganizationWorkExecution), findsNothing);
      expect(find.textContaining('Recorded labour'), findsNothing);
      await reveal(tester, find.text('Verify repaired pressure'));
      expect(find.text('pass · 3'), findsOneWidget);
      await reveal(tester, find.text('Photo 1'), delta: -250);
      await tester.tap(find.text('Photo 1'));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  testWidgets('local report survives leaving and reopening the editor', (
    tester,
  ) async {
    final fixture = ExecutionFixture();
    await tester.pumpWidget(app(fixture));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Continue service report'));
    await tester.tap(find.text('Continue service report'));
    await tester.pumpAndSettle();
    final diagnosis = find.descendant(
      of: find.byType(ServiceReportTextField).first,
      matching: find.byType(TextFormField),
    );
    await tester.enterText(diagnosis, 'Local draft diagnosis');
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Continue service report'));
    await tester.tap(find.text('Continue service report'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ServiceReportTextField>(
            find.byType(ServiceReportTextField).first,
          )
          .controller
          .text,
      'Local draft diagnosis',
    );
    expect(fixture.calls, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
  testWidgets(
    'retired pinned procedure remains selected while kit blocks replacement',
    (tester) async {
      final fixture = ExecutionFixture();
      (fixture.data['work_order'] as Map).addAll(<String, Object>{
        'checklist_template_id': 'retired',
        'checklist_template_version': 1,
        'parts_kit_captured': true,
      });
      fixture.data['templates'] = [];
      fixture.data['checklist_name'] = 'Retired pressure procedure';
      Map<String, dynamic>? saved;
      await tester.pumpWidget(
        app(
          fixture,
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () async {
                  saved = await showModalBottomSheet<Map<String, dynamic>>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) =>
                        OrganizationWorkSetupSheet(data: fixture.data),
                  );
                },
                child: const Text('Prepare'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Prepare'));
      await tester.pumpAndSettle();
      expect(find.text('Retired pressure procedure · v1'), findsOneWidget);
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byType(DropdownButtonFormField<String>),
            )
            .onChanged,
        isNull,
      );
      expect(
        find.textContaining('already captured its parts kit'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Save preparation'));
      await tester.tap(find.text('Save preparation'));
      await tester.pumpAndSettle();
      expect(saved?['checklist_template_id'], 'retired');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  for (final dark in [false, true]) {
    testWidgets(
      '320px Spanish 200 percent ${dark ? 'dark' : 'light'} panel and editor remain usable',
      (tester) async {
        tester.view.physicalSize = const Size(320, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final fixture = ExecutionFixture();
        await tester.pumpWidget(
          app(fixture, spanish: true, dark: dark, scale: 2),
        );
        await tester.pumpAndSettle();
        await captureFleet(
          tester,
          'provider-execution-${dark ? 'dark' : 'light'}-es-200',
        );
        await reveal(tester, find.text('Pausar mi tiempo'));
        await captureFleet(
          tester,
          'provider-timer-${dark ? 'dark' : 'light'}-es-200',
        );
        await reveal(tester, find.text('Continuar informe de servicio'));
        await tester.tap(find.text('Continuar informe de servicio'));
        await tester.pumpAndSettle();
        await captureFleet(
          tester,
          'provider-report-${dark ? 'dark' : 'light'}-es-200',
        );
        await reveal(tester, find.text('Foto requerida'));
        await captureFleet(
          tester,
          'provider-checklist-${dark ? 'dark' : 'light'}-es-200',
        );
        await reveal(tester, find.text('Enviar a revisión'));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
}
