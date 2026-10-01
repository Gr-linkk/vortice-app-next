import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/model.dart';
import 'package:maintenance_local/ui/inspection_page.dart';

import 'inspection_editor_coherence_support.dart';
import 'support/native_widget_cleanup.dart';

const _first = {
  'notes': 'First captured notes.',
  'meter': '104,5',
  'answer:pressure': '21',
  'answer:condition': 'First captured condition.',
};
const _later = {
  'notes': 'Later platform notes.',
  'meter': '108,75',
  'answer:pressure': '26',
  'answer:condition': 'Later platform condition.',
};

Future<void> _open(WidgetTester tester, EditorFixture fixture) async {
  await tester.pumpWidget(fixture.page());
  await untilEditor(
    tester,
    () => find.byKey(const Key('notes')).evaluate().isNotEmpty,
  );
}

Future<void> _focus(WidgetTester tester, String key) async {
  final field = find.byKey(ValueKey(key));
  await tester.ensureVisible(field);
  await tester.showKeyboard(field);
  await tester.pump();
  expect(tester.testTextInput.isRegistered, isTrue);
  expect(tester.widget<TextField>(field).enabled, isTrue);
}

VoidCallback _action(WidgetTester tester, bool submit) => submit
    ? tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Submit for review'),
          )
          .onPressed!
    : tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Save work'),
          )
          .onPressed!;

Future<void> _platformEdit(WidgetTester tester, String key, String text) async {
  tester.testTextInput.enterText(text);
  await tester.idle();
  expect(tester.widget<TextField>(find.byKey(ValueKey(key))).enabled, isTrue);
  expect(editorController(tester, key).text, text);
}

Future<void> _finished(WidgetTester tester) async {
  await settleEditor(tester);
  await untilEditor(
    tester,
    () =>
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Submit for review'),
            )
            .onPressed !=
        null,
  );
}

Object? _value(Json fields, String key) {
  final value = valuesOf(fields)[key];
  if (key.startsWith('answer:')) return value is Map ? value['value'] : null;
  return value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initializeEditorNative);

  for (final submit in [false, true]) {
    for (final key in _first.keys) {
      testWidgets(
        '${submit ? 'submit' : 'save'} preserves later platform input for $key',
        (tester) async {
          final fixture = await editorFixture(tester);
          await _open(tester, fixture);
          await enterEditor(tester, key, _first[key]!);
          await _focus(tester, key);
          final release = Completer<void>();
          addTearDown(() {
            if (!release.isCompleted) release.complete();
          });
          final gate = fixture.store.queue.run(() => release.future);
          _action(tester, submit)();
          await _platformEdit(tester, key, _later[key]!);
          release.complete();
          await finishNativeWidgetAction(tester, () => gate);
          await _finished(tester);
          expect(editorController(tester, key).text, _later[key]);
          expect(find.textContaining('Unsaved changes —'), findsOneWidget);
          final fields = (await tester.runAsync(
            () => fixture.store.fields(jobId: fixture.job),
          ))!;
          final firstValue = key == 'meter' ? 104.5 : _first[key];
          expect(_value(fields, key), firstValue);
          if (submit) {
            expect(
              find.textContaining('Newer changes are still unsaved.'),
              findsOneWidget,
            );
            expect(fixture.store.submissions, hasLength(1));
            final submittedFields = <String, dynamic>{
              for (final entry
                  in (fixture.store.submissions.single['values'] as Map)
                      .entries)
                entry.key as String: [entry.value],
            };
            expect(_value(submittedFields, key), firstValue);
          }
          // The late edit extends this operation's known native result, rather
          // than conflicting with its own earlier captured value on retry.
          await tapEditor(tester, find.text('Save work'));
          await _finished(tester);
          final saved = (await tester.runAsync(
            () => fixture.store.fields(jobId: fixture.job),
          ))!;
          expect(_value(saved, key), key == 'meter' ? 108.75 : _later[key]);
          expect(conflicts(saved), isEmpty);
          expect(find.textContaining('Unsaved changes —'), findsNothing);
        },
      );
    }
  }

  testWidgets(
    'later edits with the same raw value still retain their identity',
    (tester) async {
      final fixture = await editorFixture(tester);
      await _open(tester, fixture);
      await enterEditor(tester, 'notes', _first['notes']!);
      await _focus(tester, 'notes');
      final release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      final gate = fixture.store.queue.run(() => release.future);
      _action(tester, false)();
      await _platformEdit(tester, 'notes', 'A later intermediate edit.');
      await _platformEdit(tester, 'notes', _first['notes']!);
      release.complete();
      await finishNativeWidgetAction(tester, () => gate);
      await _finished(tester);
      expect(editorController(tester, 'notes').text, _first['notes']);
      expect(find.textContaining('Unsaved changes —'), findsOneWidget);
      await tapEditor(tester, find.text('Save work'));
      expect(find.textContaining('Unsaved changes —'), findsNothing);
    },
  );

  testWidgets(
    'decode failure preserves late input and retry avoids self-conflicts',
    (tester) async {
      final fixture = await editorFixture(tester);
      var fail = false;
      await tester.pumpWidget(
        fixture.page(
          decoder: (bytes) async {
            if (fail) {
              fail = false;
              throw StateError('Synthetic decode interruption.');
            }
            return decodeEditorFields(bytes);
          },
        ),
      );
      await untilEditor(
        tester,
        () => find.byKey(const Key('notes')).evaluate().isNotEmpty,
      );
      await enterEditor(tester, 'notes', _first['notes']!);
      await _focus(tester, 'notes');
      final release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      final gate = fixture.store.queue.run(() => release.future);
      fail = true;
      _action(tester, true)();
      await _platformEdit(tester, 'notes', _later['notes']!);
      release.complete();
      await finishNativeWidgetAction(tester, () => gate);
      await _finished(tester);
      expect(find.text('Synthetic decode interruption.'), findsOneWidget);
      expect(editorController(tester, 'notes').text, _later['notes']);
      expect(fixture.store.submissions, isEmpty);
      await tapEditor(tester, find.text('Save work'));
      final fields = (await tester.runAsync(
        () => fixture.store.fields(jobId: fixture.job),
      ))!;
      expect(_value(fields, 'notes'), _later['notes']);
      expect(conflicts(fields), isEmpty);
    },
  );

  testWidgets(
    'late local input retains a conflict with subsequently queued remote work',
    (tester) async {
      final fixture = await editorFixture(tester);
      final pause = PausedEditorDecode();
      await tester.pumpWidget(fixture.page(decoder: pause.call));
      await untilEditor(
        tester,
        () => find.byKey(const Key('notes')).evaluate().isNotEmpty,
      );
      await enterEditor(tester, 'notes', _first['notes']!);
      await _focus(tester, 'notes');
      final release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      final gate = fixture.store.queue.run(() => release.future);
      pause.arm();
      final releaseDecode = pause.release!;
      addTearDown(() {
        if (!releaseDecode.isCompleted) releaseDecode.complete();
      });
      _action(tester, true)();
      await _platformEdit(tester, 'notes', _later['notes']!);
      release.complete();
      await finishNativeWidgetAction(tester, () => gate);
      await untilEditor(tester, () => pause.entered!.isCompleted);
      await finishNativeWidgetAction(
        tester,
        () => fixture.store.update({
          'notes': 'Concurrent remote notes.',
        }, jobId: fixture.job),
      );
      fixture.updates.value++;
      releaseDecode.complete();
      await _finished(tester);
      expect(editorController(tester, 'notes').text, _later['notes']);
      expect(fixture.store.submissions, isEmpty);
      await tapEditor(tester, find.text('Save work'));
      await untilEditor(
        tester,
        () => find.text('Resolve Inspection notes').evaluate().isNotEmpty,
      );
      final fields = (await tester.runAsync(
        () => fixture.store.fields(jobId: fixture.job),
      ))!;
      expect(
        fields['notes'],
        containsAll([_later['notes'], 'Concurrent remote notes.']),
      );
      expect(conflicts(fields), contains('notes'));
    },
  );

  testWidgets(
    'leaving during a save remains on the inspection when newer input is unsaved',
    (tester) async {
      final fixture = await editorFixture(tester);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: const Scaffold(body: Text('Inspection list')),
        ),
      );
      unawaited(
        navigator.currentState!.push<void>(
          MaterialPageRoute(
            builder: (_) => InspectionPage(
              store: fixture.store,
              jobId: fixture.job,
              updates: fixture.updates,
            ),
          ),
        ),
      );
      await tester.pump();
      await untilEditor(
        tester,
        () => find.byKey(const Key('notes')).evaluate().isNotEmpty,
      );
      await tester.pump(const Duration(milliseconds: 400));
      await enterEditor(tester, 'notes', _first['notes']!);
      await _focus(tester, 'notes');
      final release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      final gate = fixture.store.queue.run(() => release.future);
      final leaving = navigator.currentState!.maybePop();
      await tester.idle();
      await _platformEdit(tester, 'notes', _later['notes']!);
      release.complete();
      await finishNativeWidgetAction(tester, () => gate);
      await leaving;
      await _finished(tester);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('notes')), findsOneWidget);
      expect(editorController(tester, 'notes').text, _later['notes']);
      expect(find.textContaining('Unsaved changes —'), findsOneWidget);
      await tester.runAsync(() => navigator.currentState!.maybePop());
      await settleEditor(tester);
      await tester.pump(const Duration(milliseconds: 400));
      await untilEditor(
        tester,
        () => find.byKey(const Key('notes')).evaluate().isEmpty,
      );
      expect(find.text('Inspection list'), findsOneWidget);
      final fields = (await tester.runAsync(
        () => fixture.store.fields(jobId: fixture.job),
      ))!;
      expect(_value(fields, 'notes'), _later['notes']);
    },
  );
}
