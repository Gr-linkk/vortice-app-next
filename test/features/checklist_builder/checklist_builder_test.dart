import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/checklist_builder/checklist_builder_repository.dart';
import 'package:vortice_app/features/checklist_builder/checklist_editor_screen.dart';
import 'package:vortice_app/features/checklist_builder/checklist_library_screen.dart';
import 'package:vortice_app/features/checklist_builder/checklist_preview_screen.dart';
import 'package:vortice_app/features/checklists/checklist_answer_fields.dart';
import 'package:vortice_app/features/checklists/asset_checklist_template_filter.dart';
import 'package:vortice_app/models/checklist_template.dart';
import '../maintenance/maintenance_screen_test.dart'
    show pumpMaintenance, FixtureMaintenance;
import '../fleet/fleet_test_support.dart';

const catalog = <String, dynamic>{
  'can_pm': true,
  'can_preop': true,
  'assets': [],
  'asset_types': [],
};
const step = <String, dynamic>{
  'description_en': 'Record oil pressure',
  'description_es': 'Registrar presión de aceite',
  'category': 'Engine',
  'requires_photo': true,
  'definition': {
    'input_type': 'number',
    'unit': 'bar',
    'min': 10,
    'max': 50,
    'allow_na': false,
    'critical': true,
  },
};
const draft = <String, dynamic>{
  'name': 'Generator service',
  'checklist_type': 'pm',
  'items': [step],
};

class BuilderFixture extends ChecklistBuilderRepository {
  final calls = <Map<String, dynamic>>[];
  bool fail = false;
  @override
  Future<String> save(
    String operation,
    String id,
    int revision,
    String action,
    Map<String, dynamic> data,
  ) async {
    calls.add({
      'operation': operation,
      'id': id,
      'revision': revision,
      'action': action,
      'data': data,
    });
    if (fail) throw TimeoutException('Connection lost');
    return id;
  }
}

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
    await tester.scrollUntilVisible(target, 180, scrollable: scroll);
  }
  await Scrollable.ensureVisible(tester.element(target.last), alignment: .5);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadFleetScreenshotFonts);
  test('numeric range and NA rules cannot be bypassed by a pass result', () {
    final rule = Map<String, dynamic>.from(step['definition'] as Map);
    expect(checklistValueResult(rule, '10,5'), 'pass');
    expect(checklistValueResult(rule, '80'), 'action');
    expect(checklistAnswerValid(rule, 'pass', '80'), isFalse);
    expect(checklistAnswerValid(rule, 'fail', '80'), isTrue);
    expect(checklistAnswerValid(rule, 'pass', 'NaN'), isFalse);
    expect(checklistAnswerValid(rule, 'n/a', ''), isFalse);
    expect(checklistAnswerValid({'input_type': 'text'}, 'pass', '  '), isFalse);
  });
  test(
    'copy retains instruction rules and removes company and equipment scope',
    () {
      final copied = copiedChecklistDraft({
        ...draft,
        'id': 'source',
        'version': 3,
        'client_id': 'other',
        'scope_asset_id': 'asset',
      });
      expect(copied['source_version'], 3);
      expect(copied.containsKey('client_id'), isFalse);
      expect(copied.containsKey('scope_asset_id'), isFalse);
      expect(
        (copied['items'] as List).single['definition'],
        step['definition'],
      );
    },
  );
  test(
    'published scope requires matching company, equipment, and component',
    () {
      const template = ChecklistTemplate(
        id: 't',
        name: 'Scoped',
        clientId: 'company',
        scopeAssetId: 'asset',
        scopeEngineId: 'engine',
      );
      expect(
        checklistTemplateMatches(
          template,
          kind: 'pm',
          clientId: 'company',
          assetId: 'asset',
          engineId: 'engine',
        ),
        isTrue,
      );
      expect(
        checklistTemplateMatches(
          template,
          kind: 'pm',
          clientId: 'other',
          assetId: 'asset',
          engineId: 'engine',
        ),
        isFalse,
      );
      expect(
        checklistTemplateMatches(
          template,
          kind: 'pm',
          clientId: 'company',
          assetId: 'asset',
        ),
        isFalse,
      );
    },
  );
  for (final es in [false, true]) {
    testWidgets(
      'preview renders real range validation at 320 and large text es=$es',
      (tester) async {
        await pumpMaintenance(
          tester,
          const ChecklistPreviewScreen(draft: draft),
          FixtureMaintenance(),
          es: es,
          width: 320,
          scale: 1.5,
        );
        expect(tester.takeException(), isNull);
        await tester.enterText(find.byType(TextFormField), '80');
        await tester.pumpAndSettle();
        expect(
          find.textContaining(es ? 'Foto requerida' : 'Photo required'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await captureFleet(tester, 'builder-preview-${es ? 'es' : 'en'}-320');
      },
    );
  }
  testWidgets(
    'Spanish library and editor remain usable at narrow width and large text',
    (tester) async {
      await pumpMaintenance(
        tester,
        const ChecklistLibraryScreen(),
        FixtureMaintenance(),
        es: true,
        width: 320,
        scale: 1.5,
        overrides: [
          checklistLibraryProvider.overrideWith(
            (ref) async => {
              ...catalog,
              'procedures': [
                {'id': 'draft', 'draft': draft, 'revision': 1},
              ],
            },
          ),
        ],
      );
      expect(tester.takeException(), isNull);
      await captureFleet(tester, 'builder-library-es-320');
      await reveal(tester, find.text('Crear lista'));
      await tester.tap(find.text('Crear lista'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await captureFleet(tester, 'builder-editor-es-320');
      await reveal(tester, find.text('Añadir paso'));
      await tester.tap(find.text('Añadir paso'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Guardar paso'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).last, const Offset(0, -160));
      await tester.pumpAndSettle();
      expect(find.text('Guardar paso').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Guardar paso'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await reveal(tester, find.text('Describe el paso'));
      expect(find.text('Describe el paso'), findsOneWidget);
      await tester.pumpAndSettle();
      await captureFleet(tester, 'builder-step-es-320');
    },
  );
  testWidgets(
    'draft saves before publication and retry keeps the same operation',
    (tester) async {
      final repository = BuilderFixture()..fail = true;
      await pumpMaintenance(
        tester,
        const ChecklistEditorScreen(catalog: catalog, initial: draft),
        FixtureMaintenance(),
        overrides: [
          checklistBuilderRepositoryProvider.overrideWithValue(repository),
        ],
      );
      await reveal(tester, find.text('Save draft'));
      await tester.tap(find.text('Save draft'));
      await tester.pumpAndSettle();
      expect(repository.calls, hasLength(1));
      repository.fail = false;
      await reveal(tester, find.text('Retry same save'));
      await tester.tap(find.text('Retry same save'));
      await tester.pumpAndSettle();
      expect(repository.calls, hasLength(2));
      expect(repository.calls[0], repository.calls[1]);
      await reveal(tester, find.text('Publish version'));
      await tester.tap(find.text('Publish version'));
      await tester.pumpAndSettle();
      expect(repository.calls.last['action'], 'publish');
      expect(repository.calls.last['revision'], 1);
      expect(find.text('Published. Available for new work.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await captureFleet(tester, 'builder-published');
    },
  );
}
