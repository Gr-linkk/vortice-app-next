import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/model.dart';
import 'inspection_editor_coherence_support.dart';
import 'support/native_widget_cleanup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initializeEditorNative);
  testWidgets(
    'platform typing before busy repaint must remain saved or unsaved',
    (tester) async {
      final fixture = await editorFixture(tester);
      await tester.pumpWidget(fixture.page());
      await untilEditor(
        tester,
        () => find.byKey(const Key('notes')).evaluate().isNotEmpty,
      );
      await enterEditor(tester, 'notes', 'Captured first.');
      final finder = find.byKey(const Key('notes'));
      await tester.showKeyboard(finder);
      await tester.pump();
      expect(tester.testTextInput.isRegistered, true);
      expect(tester.widget<TextField>(finder).enabled, true);
      final submit = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Submit for review'),
          )
          .onPressed!;
      final release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      final gate = fixture.store.queue.run(() => release.future);
      submit();
      // The last painted field is enabled; deliver an ordinary platform edit
      // before the busy-state frame. No disabled onChanged callback is invoked.
      tester.testTextInput.enterText('Late before busy repaint.');
      await tester.idle();
      expect(tester.widget<TextField>(finder).enabled, true);
      expect(
        editorController(tester, 'notes').text,
        'Late before busy repaint.',
      );
      release.complete();
      await finishNativeWidgetAction(tester, () => gate);
      await untilEditor(tester, () => fixture.store.submissions.isNotEmpty);
      final fields = (await tester.runAsync(
        () => fixture.store.fields(jobId: fixture.job),
      ))!;
      final stored = valuesOf(fields)['notes'];
      final visible = editorController(tester, 'notes').text;
      expect(
        stored == 'Late before busy repaint.' ||
            visible == 'Late before busy repaint.',
        true,
        reason:
            'Ordinary platform input was received while the last painted editor was enabled, then discarded. Stored=$stored; visible=$visible.',
      );
    },
  );
}
