import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/ui/inspection_page.dart';

import 'inspection_editor_coherence_support.dart';
import 'support/native_widget_cleanup.dart';

const boundary = Key('inspection-coherence-render');

Future<void> captureEditor(WidgetTester tester, String name) async {
  final destination = Platform.environment['MAINTENANCE_CAPTURE_DIR'];
  if (destination == null) return;
  await settleEditor(tester);
  final render = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(boundary),
  );
  await tester.runAsync(() async {
    final image = await render.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      expect(bytes, isNotNull);
      await Directory(destination).create(recursive: true);
      await File(
        '$destination/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initializeEditorNative();
    for (final face in ['Regular', 'Bold']) {
      await (FontLoader('Roboto')..addFont(
            File(
              '../../assets/fonts/Roboto-$face.ttf',
            ).readAsBytes().then((bytes) => bytes.buffer.asByteData()),
          ))
          .load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('render incoming inspection review at ${scale}x text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = await editorFixture(tester);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: RepaintBoundary(
            key: boundary,
            child: InspectionPage(
              store: fixture.store,
              jobId: fixture.job,
              updates: fixture.updates,
            ),
          ),
        ),
      );
      await untilEditor(
        tester,
        () => find.byKey(const Key('notes')).evaluate().isNotEmpty,
      );
      await enterEditor(
        tester,
        'notes',
        'Mechanic finding remains typed while new work arrives.',
      );
      await finishNativeWidgetAction(
        tester,
        () => fixture.store.update({
          'meter': 112,
          'answer:condition': {
            'result': 'pass',
            'value': 'Incoming checked condition.',
          },
        }, jobId: fixture.job),
      );
      fixture.updates.value++;
      await untilEditor(
        tester,
        () => find
            .textContaining('Your unsaved changes are still here')
            .evaluate()
            .isNotEmpty,
      );
      expect(
        editorController(tester, 'notes').text,
        'Mechanic finding remains typed while new work arrives.',
      );
      expect(editorController(tester, 'meter').text, '112');
      await tester.ensureVisible(
        find.textContaining('Your unsaved changes are still here'),
      );
      await captureEditor(tester, 'inspection-incoming-dirty-${scale}x');
      await tester.ensureVisible(find.byKey(const Key('notes')));
      await captureEditor(tester, 'inspection-preserved-notes-${scale}x');
      // A second incoming change deliberately omits notification: the first
      // submit must expose it and require another ordinary explicit click.
      await finishNativeWidgetAction(
        tester,
        () => fixture.store.update({'meter': 115}, jobId: fixture.job),
      );
      await tapEditor(tester, find.text('Submit for review'));
      await untilEditor(
        tester,
        () => find.text(changedInspectionMessage).evaluate().isNotEmpty,
      );
      expect(fixture.store.submissions, isEmpty);
      expect(editorController(tester, 'meter').text, '115');
      await tester.ensureVisible(find.text(changedInspectionMessage));
      await captureEditor(tester, 'inspection-review-required-${scale}x');
      await tester.ensureVisible(find.text('Submit for review'));
      expect(find.text('Submit for review').hitTestable(), findsOneWidget);
      await captureEditor(tester, 'inspection-reviewed-submit-${scale}x');
      await tapEditor(tester, find.text('Submit for review'));
      await untilEditor(tester, () => fixture.store.submissions.isNotEmpty);
      expect(
        fixture.store.submissions.single['values']['notes'],
        'Mechanic finding remains typed while new work arrives.',
      );
      expect(fixture.store.submissions.single['values']['meter'], 115);
    });
  }
}
