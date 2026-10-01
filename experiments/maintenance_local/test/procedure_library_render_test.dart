import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/model.dart';
import 'package:maintenance_local/procedure_library_store.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';
import 'package:maintenance_local/ui/preparation_page.dart';
import 'package:maintenance_local/ui/procedure_publication_page.dart';

const _boundaryKey = Key('procedure-library-render-boundary');

Future<void> _settle(WidgetTester tester) async {
  // SQLite, filesystem and the native document bridge run in real time. Keep
  // waits bounded, and check every action for render failures and overflow.
  await tester.pump(const Duration(milliseconds: 700));
  for (var attempt = 0; attempt < 6; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
  expect(
    tester.takeException(),
    isNull,
    reason: 'The actual procedure screen must render without overflow.',
  );
}

Future<void> _show(WidgetTester tester, Finder target) async {
  expect(target, findsOneWidget);
  await Scrollable.ensureVisible(tester.element(target), alignment: 0.15);
  await tester.pump(const Duration(milliseconds: 250));
  expect(
    target.hitTestable(),
    findsOneWidget,
    reason: 'The ordinary action must remain reachable at this text size.',
  );
  expect(tester.takeException(), isNull);
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await _show(tester, target);
  await tester.runAsync(() async {
    await tester.tap(target);
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });
  await _settle(tester);
}

Future<void> _enter(WidgetTester tester, String key, String value) async {
  final field = find.byKey(Key(key));
  await _show(tester, field);
  await tester.enterText(field, value);
  await _settle(tester);
}

String _text(WidgetTester tester, String key) =>
    tester.widget<TextFormField>(find.byKey(Key(key))).controller!.text;

Future<void> _capture(WidgetTester tester, String name) async {
  final output = Platform.environment['VORTICE_RENDER_OUTPUT'];
  if (output == null || output.isEmpty) return;
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
  expect(
    tester.hasRunningAnimations,
    isFalse,
    reason: 'Acceptance PNGs must show a stable screen after transitions.',
  );
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_boundaryKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$output/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
    } finally {
      image.dispose();
    }
  });
  expect(tester.takeException(), isNull);
}

Future<void> _mount(WidgetTester tester, LabStore store, double scale) async {
  await tester.pumpWidget(
    RepaintBoundary(
      key: _boundaryKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xfff7f4ed),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xff103d3c),
            primary: const Color(0xff103d3c),
            surface: const Color(0xfff7f4ed),
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xfff7f4ed),
            foregroundColor: Color(0xff103d3c),
          ),
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
            filled: true,
            fillColor: Colors.white,
          ),
          cardTheme: const CardThemeData(
            color: Colors.white,
            elevation: 0,
            margin: EdgeInsets.symmetric(vertical: 8),
          ),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: PreparationPage(store: store, step: PreparationStep.checklist),
      ),
    ),
  );
  await _settle(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await RustLib.init(
      externalLibrary: ExternalLibrary.open(
        File(
          Platform.environment['MAINTENANCE_NATIVE_LIBRARY'] ??
              'rust/target/debug/librust_lib_sync_lab.so',
        ).absolute.path,
      ),
    );
    for (final face in ['Regular', 'Bold']) {
      await (FontLoader('Roboto')..addFont(
            File(
              '../../assets/fonts/Roboto-$face.ttf',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'ordinary procedure copy, failure recovery and preparation at ${scale}x',
      (tester) async {
        tester.view.physicalSize = const Size(412, 915);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        late Directory root;
        late LabStore store;
        late Json source, originalJob, equipment;
        await tester.runAsync(() async {
          root = await Directory.systemTemp.createTemp('procedure-render-');
          store = await LabStore.open(
            Directory('${root.path}/office'),
            office: true,
            maintenanceOnly: true,
          );
          await store.createCompany(
            'Synthetic Procedure Construction',
            coordinatorName: 'Sam Coordinator',
          );
          final first = await store.addEquipment(
            name: 'Synthetic yard generator',
            serial: 'SYNTHETIC-GEN-1',
          );
          equipment = await store.addEquipment(
            name: 'Synthetic service excavator',
            serial: 'SYNTHETIC-EX-24',
            meterUnit: 'km',
          );
          source = await store.publishChecklist(
            title: 'Daily hydraulic safety inspection',
            provenance: {
              'kind': 'manual-reference',
              'reference': 'Synthetic service manual, section 4.2',
            },
            items: [
              {
                'id': 'guards',
                'label': 'Inspect guards and emergency stop before starting',
                'input_type': 'check',
                'required': true,
                'allow_na': true,
              },
              {
                'id': 'pressure',
                'label': 'Record hydraulic pressure at idle',
                'input_type': 'number',
                'unit': 'bar',
                'min': 0,
                'max': 20,
              },
              {
                'id': 'condition',
                'label': 'Describe any visible leaks or damaged hoses',
                'input_type': 'text',
                'required': false,
                'allow_na': false,
                'unit': null,
                'min': null,
                'max': null,
              },
              {
                'id': 'ambient',
                'label': 'Record the ambient temperature if known',
                'input_type': 'number',
                'unit': '',
                'min': null,
                'max': null,
                'required': false,
              },
            ],
          );
          originalJob = await store.prepareWork(
            equipmentId: first['id'] as String,
            templateId: source['id'] as String,
            title: 'Original generator inspection',
          );
        });
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(() async {
            await store.close();
            await root.delete(recursive: true);
          });
        });
        final sourceBytes = canonical(source);
        final jobBytes = canonical(originalJob);
        final suffix = '${scale.toInt()}x';
        await _mount(tester, store, scale);
        await _capture(tester, 'preparation-entry-$suffix');
        await _tap(
          tester,
          find.byKey(const Key('preparation-checklist-library')),
        );
        await _capture(tester, 'library-entry-$suffix');

        await _tap(
          tester,
          find.byKey(Key('procedure-preview-${source['id']}')),
        );
        expect(
          find.descendant(
            of: find.byType(ProcedurePublicationPage),
            matching: find.textContaining(
              'Synthetic service manual, section 4.2',
            ),
          ),
          findsOneWidget,
        );
        await _capture(tester, 'source-preview-entry-$suffix');
        await _show(tester, find.byKey(const Key('procedure-preview-step-1')));
        await _capture(tester, 'source-preview-instructions-$suffix');
        await _tap(tester, find.byKey(const Key('procedure-publication-copy')));
        expect(
          find.textContaining('Daily hydraulic safety inspection'),
          findsWidgets,
        );
        await _capture(tester, 'copy-editor-entry-$suffix');

        final copiedItems = canonical(store.procedureDrafts.single['items']);
        await _enter(tester, 'procedure-title', 'Hydraulic inspection copy');
        await _tap(tester, find.byKey(const Key('procedure-save')));
        expect(
          canonical(store.procedureDrafts.single['items']),
          copiedItems,
          reason: 'A title-only save preserves absent, null, empty and zero.',
        );
        await _enter(
          tester,
          'procedure-step-label-0',
          'Inspect guards and verify the emergency stop',
        );
        await _enter(tester, 'procedure-step-unit-1', 'kPa');
        await _enter(tester, 'procedure-step-min-1', '0');
        await _enter(tester, 'procedure-step-max-1', '125');
        await _show(tester, find.byKey(const Key('procedure-step-unit-1')));
        await _capture(tester, 'copy-editor-numeric-limits-$suffix');
        await _tap(tester, find.byKey(const Key('procedure-step-required-2')));
        await _tap(tester, find.byKey(const Key('procedure-step-na-2')));
        await _tap(tester, find.byKey(const Key('procedure-add-step')));
        await _enter(
          tester,
          'procedure-step-label-4',
          'Describe follow-up work needed after this inspection',
        );
        await _tap(tester, find.byKey(const Key('procedure-step-type-4')));
        await _tap(tester, find.text('Written response').last);
        await _capture(tester, 'copy-editor-added-step-$suffix');
        await _tap(tester, find.byKey(const Key('procedure-save')));
        final saved = store.procedureDrafts.single;
        final draftId = saved['id'] as String;
        expect(saved['title'], 'Hydraulic inspection copy');
        expect(saved['items'][1]['min'], 0);
        expect(saved['items'][1]['unit'], 'kPa');
        expect(saved['items'][2]['required'], isTrue);
        expect(saved['items'][2]['allow_na'], isTrue);
        expect(saved['items'][4]['input_type'], 'text');
        expect(saved['source']['publicationId'], source['id']);
        await tester.pageBack();
        await _settle(tester);
        expect(find.text('Preview checklist'), findsOneWidget);
        await tester.pageBack();
        await _settle(tester);
        await _show(tester, find.byKey(Key('procedure-open-$draftId')));
        await _capture(tester, 'saved-copy-library-$suffix');
        await _tap(tester, find.byKey(Key('procedure-open-$draftId')));
        expect(_text(tester, 'procedure-title'), 'Hydraulic inspection copy');
        expect(_text(tester, 'procedure-step-unit-1'), 'kPa');
        expect(_text(tester, 'procedure-step-min-1'), '0');
        await _capture(tester, 'reopened-editor-entry-$suffix');

        // Failed validation must leave the attempted values visible and the
        // durable copy intact, rather than resetting the form.
        await _enter(tester, 'procedure-step-min-1', '200');
        await _tap(tester, find.byKey(const Key('procedure-save')));
        expect(
          find.text('Maximum must be at least the minimum.'),
          findsOneWidget,
        );
        expect(_text(tester, 'procedure-step-min-1'), '200');
        expect(store.procedureDrafts.single['items'][1]['min'], 0);
        await _show(tester, find.byKey(const Key('procedure-step-max-1')));
        await _capture(tester, 'validation-failure-retained-$suffix');
        await _enter(tester, 'procedure-step-min-1', '0');

        // An incomplete draft can be saved. Publication explains what remains
        // required and stays unavailable without touching the source.
        await _enter(tester, 'procedure-title', '');
        await _tap(tester, find.byKey(const Key('procedure-save')));
        expect(
          tester
              .widget<OutlinedButton>(
                find.byKey(const Key('procedure-publish')),
              )
              .onPressed,
          isNull,
        );
        expect(_text(tester, 'procedure-title'), isEmpty);
        expect(_text(tester, 'procedure-step-unit-1'), 'kPa');
        expect(store.templates, hasLength(1));
        await _show(tester, find.textContaining('Drafts can be unfinished.'));
        await _capture(tester, 'unfinished-draft-publish-guidance-$suffix');

        // A second actual writer changes the saved copy while this editor is
        // open. The stale editor must not replace it; reload is an explicit act.
        await tester.runAsync(() async {
          final current = store.procedureDrafts.single;
          await store.saveProcedureDraft(
            draftId: draftId,
            expectedRevision: current['revision'] as int,
            title: 'Coordinator corrected hydraulic inspection',
            items: (current['items'] as List)
                .map((item) => Map<String, dynamic>.from(item as Map))
                .toList(),
            operationId: 'external-editor-save-$suffix',
          );
        });
        await _enter(tester, 'procedure-title', 'Unsaved local proposal');
        await _tap(tester, find.byKey(const Key('procedure-save')));
        expect(
          store.procedureDrafts.single['title'],
          'Coordinator corrected hydraulic inspection',
        );
        expect(_text(tester, 'procedure-title'), 'Unsaved local proposal');
        await _show(tester, find.textContaining('This draft changed since'));
        await _capture(tester, 'stale-editor-error-$suffix');
        await _show(tester, find.byKey(const Key('procedure-reload')));
        await _capture(tester, 'stale-editor-reload-action-$suffix');
        await _tap(tester, find.byKey(const Key('procedure-reload')));
        await _capture(tester, 'stale-reload-confirmation-$suffix');
        await _tap(tester, find.byKey(const Key('procedure-confirm-reload')));
        expect(
          _text(tester, 'procedure-title'),
          'Coordinator corrected hydraulic inspection',
        );
        await _show(tester, find.byKey(const Key('procedure-title')));
        await _capture(tester, 'stale-editor-reloaded-$suffix');

        await _enter(tester, 'procedure-title', 'Hydraulic inspection copy');
        await _tap(tester, find.byKey(const Key('procedure-save')));
        await _tap(tester, find.byKey(const Key('procedure-publish')));
        expect(store.templates, hasLength(2));
        final publication = store.templates.last;
        expect(publication['id'], isNot(source['id']));
        expect(publication['version'], 1);
        expect(publication['items'][1]['min'], 0);
        expect(publication['items'][1]['unit'], 'kPa');
        expect(canonical(store.templates.first), sourceBytes);
        expect(canonical(store.jobs.first), jobBytes);
        expect(find.text('Preview checklist'), findsOneWidget);
        expect(
          find.textContaining('Independent copy · Source:'),
          findsOneWidget,
        );
        await _capture(tester, 'published-copy-preview-entry-$suffix');
        final referenceHeader = find.descendant(
          of: find.byKey(const Key('procedure-source-reference')),
          matching: find.text('Source reference'),
        );
        await _tap(tester, referenceHeader);
        expect(find.textContaining(source['hash'] as String), findsOneWidget);
        await _capture(tester, 'published-copy-source-reference-$suffix');
        await _tap(tester, referenceHeader);

        await _tap(tester, find.byKey(const Key('procedure-equipment')));
        await _tap(tester, find.text('Synthetic service excavator').last);
        final equipmentField = find.byKey(const Key('procedure-equipment'));
        final selectedName = find.descendant(
          of: equipmentField,
          matching: find.text('Synthetic service excavator'),
        );
        expect(selectedName, findsOneWidget);
        expect(
          tester.getRect(selectedName).bottom,
          lessThanOrEqualTo(tester.getRect(equipmentField).bottom),
          reason: 'The full selected equipment name must fit its field.',
        );
        expect(
          find.byKey(const Key('procedure-selected-equipment')),
          findsOneWidget,
        );
        await _enter(
          tester,
          'procedure-inspection-title',
          'Afternoon excavator inspection',
        );
        await _show(tester, find.byKey(const Key('procedure-prepare')));
        await _capture(tester, 'prepare-copy-equipment-$suffix');
        await _tap(tester, find.byKey(const Key('procedure-prepare')));
        expect(store.jobs, hasLength(2));
        final prepared = store.jobs.last;
        expect(prepared['equipmentId'], equipment['id']);
        expect(prepared['checklistSnapshot'], publication);
        expect(prepared['snapshotHash'], contentHash(publication));
        expect(canonical(store.jobs.first), jobBytes);
        await _show(tester, find.byKey(const Key('procedure-prepared-done')));
        await _capture(tester, 'inspection-prepared-$suffix');
        await _tap(tester, find.byKey(const Key('procedure-prepared-done')));

        // Another window can finalize a copy while this editor remains open.
        // Its next attempted write must retain the local proposal and lead to
        // a reload into the finalized, read-only record.
        await _tap(tester, find.byKey(Key('procedure-copy-${source['id']}')));
        final concurrent = store.procedureDrafts.last;
        await tester.runAsync(() async {
          await store.publishProcedureDraft(
            draftId: concurrent['id'] as String,
            expectedRevision: concurrent['revision'] as int,
            operationId: 'external-editor-publish-$suffix',
          );
        });
        await _enter(tester, 'procedure-title', 'Unsaved after publication');
        await _tap(tester, find.byKey(const Key('procedure-save')));
        expect(_text(tester, 'procedure-title'), 'Unsaved after publication');
        await _show(tester, find.textContaining('This draft was published.'));
        await _capture(tester, 'concurrent-publication-error-$suffix');
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('procedure-save')))
              .onPressed,
          isNull,
        );
        await _tap(tester, find.byKey(const Key('procedure-reload')));
        await _tap(tester, find.byKey(const Key('procedure-confirm-reload')));
        expect(find.byKey(const Key('procedure-save')), findsNothing);
        expect(
          tester
              .widget<TextFormField>(find.byKey(const Key('procedure-title')))
              .enabled,
          isFalse,
        );
        await _show(
          tester,
          find.textContaining('This copy has been published'),
        );
        await _capture(tester, 'concurrent-publication-read-only-$suffix');
        expect(canonical(store.templates.first), sourceBytes);
        expect(canonical(store.jobs.first), jobBytes);
      },
    );
  }
}
