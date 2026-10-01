import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/model.dart';

import 'inspection_editor_coherence_support.dart';
import 'support/native_widget_cleanup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initializeEditorNative);

  testWidgets(
    'clean incoming work refreshes notes, checks, photo and readings',
    (tester) async {
      final fixture = await editorFixture(tester, ready: false);
      await tester.pumpWidget(fixture.page());
      await untilEditor(
        tester,
        () => find.byKey(const Key('notes')).evaluate().isNotEmpty,
      );
      expect(editorController(tester, 'notes').text, '');
      await finishNativeWidgetAction(
        tester,
        () => fixture.fill(revision: 2, notes: 'Incoming finding.'),
      );
      fixture.updates.value++;
      await untilEditor(
        tester,
        () => editorController(tester, 'notes').text == 'Incoming finding.',
      );
      expect(editorController(tester, 'meter').text, '102');
      expect(editorController(tester, 'answer:pressure').text, '20');
      expect(editorController(tester, 'answer:condition').text, 'Condition 2');
      expect(find.text('Replace inspection photo'), findsOneWidget);
      await untilEditor(tester, () => find.byType(Image).evaluate().isNotEmpty);
      expect(
        (tester.widget<Image>(find.byType(Image)).image as FileImage).file.path,
        fixture.store.evidence.file(digest([...EditorFixture.png, 2])).path,
      );
      final guard = find.ancestor(
        of: find.text('Inspect guard'),
        matching: find.byType(Card),
      );
      final action = tester.widget<ChoiceChip>(
        find.descendant(
          of: guard,
          matching: find.widgetWithText(ChoiceChip, 'Needs action'),
        ),
      );
      expect(action.selected, isTrue);
      await tapEditor(tester, find.text('Submit for review'));
      await untilEditor(tester, () => fixture.store.submissions.isNotEmpty);
      final submitted = fixture.store.submissions.single;
      expect(
        submitted['values']['notes'],
        editorController(tester, 'notes').text,
      );
      expect(
        submitted['documentHash'],
        digest(fixture.store.documentFor(fixture.job)!),
      );
    },
  );

  testWidgets(
    'initial native decode overtaken by a write never displays old bytes',
    (tester) async {
      final fixture = await editorFixture(tester, ready: false);
      final pause = PausedEditorDecode()..arm();
      final release = pause.release!;
      await tester.pumpWidget(fixture.page(decoder: pause.call));
      await untilEditor(tester, () => pause.entered!.isCompleted);
      await finishNativeWidgetAction(
        tester,
        () => fixture.fill(notes: 'Arrived during initial decode.'),
      );
      release.complete();
      await untilEditor(
        tester,
        () => find.byKey(const Key('notes')).evaluate().isNotEmpty,
      );
      expect(
        editorController(tester, 'notes').text,
        'Arrived during initial decode.',
      );
      await tapEditor(tester, find.text('Submit for review'));
      await untilEditor(tester, () => fixture.store.submissions.isNotEmpty);
      expect(
        fixture.store.submissions.single['values']['notes'],
        'Arrived during initial decode.',
      );
    },
  );

  testWidgets(
    'missed notification blocks the first submit and requires a new click',
    (tester) async {
      final fixture = await editorFixture(tester);
      await tester.pumpWidget(fixture.page());
      await untilEditor(
        tester,
        () => find.byKey(const Key('notes')).evaluate().isNotEmpty,
      );
      await finishNativeWidgetAction(
        tester,
        () => fixture.fill(notes: 'Unseen incoming notes.', revision: 2),
      );
      await tapEditor(tester, find.text('Submit for review'));
      await untilEditor(
        tester,
        () => find.text(changedInspectionMessage).evaluate().isNotEmpty,
      );
      expect(fixture.store.submissions, isEmpty);
      expect(editorController(tester, 'notes').text, 'Unseen incoming notes.');
      await tapEditor(tester, find.text('Submit for review'));
      await untilEditor(tester, () => fixture.store.submissions.isNotEmpty);
    },
  );

  testWidgets(
    'submit before an incoming repaint still fences the last shown version',
    (tester) async {
      final fixture = await editorFixture(tester);
      final pause = PausedEditorDecode();
      await tester.pumpWidget(fixture.page(decoder: pause.call));
      await untilEditor(
        tester,
        () => find.byKey(const Key('notes')).evaluate().isNotEmpty,
      );
      final submit = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Submit for review'),
          )
          .onPressed!;
      pause.arm();
      final release = pause.release!;
      await finishNativeWidgetAction(
        tester,
        () => fixture.store.update({
          'notes': 'Incoming before repaint.',
        }, jobId: fixture.job),
      );
      fixture.updates.value++;
      await untilEditor(tester, () => pause.entered!.isCompleted);
      release.complete();
      // Drain the decode continuation without drawing the changed form. Invoke
      // the still-rendered action to model an input event before the next frame.
      await tester.idle();
      expect(
        editorController(tester, 'notes').text,
        'Incoming before repaint.',
      );
      submit();
      await untilEditor(
        tester,
        () =>
            fixture.store.submissions.isNotEmpty ||
            (find.text(changedInspectionMessage).evaluate().isNotEmpty &&
                tester
                        .widget<FilledButton>(
                          find.widgetWithText(
                            FilledButton,
                            'Submit for review',
                          ),
                        )
                        .onPressed !=
                    null),
      );
      expect(
        fixture.store.submissions,
        isEmpty,
        reason:
            'Decoding newer bytes does not mean that the operator saw them.',
      );
      await tapEditor(tester, find.text('Submit for review'));
      await untilEditor(tester, () => fixture.store.submissions.isNotEmpty);
    },
  );

  testWidgets(
    'dirty save merges intent but does not submit unseen clean fields',
    (tester) async {
      final fixture = await editorFixture(tester);
      await tester.pumpWidget(fixture.page());
      await untilEditor(
        tester,
        () => find.byKey(const Key('notes')).evaluate().isNotEmpty,
      );
      await enterEditor(tester, 'notes', 'My typed finding.');
      await finishNativeWidgetAction(tester, () async {
        await fixture.store.update({
          'answer:pressure': {'result': 'pass', 'value': '25'},
          'meter': 110,
        }, jobId: fixture.job);
        await fixture.store.attach([
          ...EditorFixture.png,
          3,
        ], jobId: fixture.job);
      });
      await tapEditor(tester, find.text('Submit for review'));
      await untilEditor(
        tester,
        () => find.text(changedInspectionMessage).evaluate().isNotEmpty,
      );
      expect(fixture.store.submissions, isEmpty);
      expect(editorController(tester, 'notes').text, 'My typed finding.');
      expect(editorController(tester, 'meter').text, '110');
      expect(editorController(tester, 'answer:pressure').text, '25');
      await tapEditor(tester, find.text('Submit for review'));
      await untilEditor(tester, () => fixture.store.submissions.isNotEmpty);
      expect(
        fixture.store.submissions.single['values']['notes'],
        'My typed finding.',
      );
      expect(fixture.store.submissions.single['values']['meter'], 110);
      expect(
        fixture.store.submissions.single['values']['photo'],
        digest([...EditorFixture.png, 3]),
      );
    },
  );

  testWidgets(
    'typing before an incoming repaint retains the original merge base',
    (tester) async {
      final fixture = await editorFixture(tester);
      final pause = PausedEditorDecode();
      await tester.pumpWidget(fixture.page(decoder: pause.call));
      await untilEditor(
        tester,
        () => find.byKey(const Key('notes')).evaluate().isNotEmpty,
      );
      final priorField = tester.widget<TextField>(
        find.byKey(const Key('notes')),
      );
      pause.arm();
      final release = pause.release!;
      await finishNativeWidgetAction(
        tester,
        () => fixture.store.update({
          'notes': 'Concurrent before repaint.',
        }, jobId: fixture.job),
      );
      fixture.updates.value++;
      await untilEditor(tester, () => pause.entered!.isCompleted);
      release.complete();
      await tester.idle();
      priorField.controller!.text = 'Typed before repaint.';
      priorField.onChanged!('Typed before repaint.');
      await settleEditor(tester);
      expect(editorController(tester, 'notes').text, 'Typed before repaint.');
      await tapEditor(tester, find.text('Submit for review'));
      await untilEditor(
        tester,
        () => find.text('Resolve Inspection notes').evaluate().isNotEmpty,
      );
      expect(fixture.store.submissions, isEmpty);
      final fields = (await tester.runAsync(
        () => fixture.store.fields(jobId: fixture.job),
      ))!;
      expect(
        fields['notes'],
        containsAll(['Typed before repaint.', 'Concurrent before repaint.']),
      );
    },
  );

  testWidgets('a late incoming decode preserves newly typed invalid input', (
    tester,
  ) async {
    final fixture = await editorFixture(tester);
    final pause = PausedEditorDecode();
    await tester.pumpWidget(fixture.page(decoder: pause.call));
    await untilEditor(
      tester,
      () => find.byKey(const Key('notes')).evaluate().isNotEmpty,
    );
    pause.arm();
    final release = pause.release!;
    await finishNativeWidgetAction(
      tester,
      () => fixture.store.update({
        'notes': 'Incoming refreshed notes.',
      }, jobId: fixture.job),
    );
    fixture.updates.value++;
    await untilEditor(tester, () => pause.entered!.isCompleted);
    await enterEditor(tester, 'notes', 'Typed during incoming read.');
    await enterEditor(tester, 'meter', 'not a reading');
    release.complete();
    await untilEditor(
      tester,
      () => find
          .textContaining('Your unsaved changes are still here')
          .evaluate()
          .isNotEmpty,
    );
    expect(
      editorController(tester, 'notes').text,
      'Typed during incoming read.',
    );
    expect(editorController(tester, 'meter').text, 'not a reading');
    await tapEditor(tester, find.text('Submit for review'));
    expect(fixture.store.submissions, isEmpty);
    expect(find.textContaining('Enter a valid meter reading'), findsOneWidget);
    expect(
      editorController(tester, 'notes').text,
      'Typed during incoming read.',
    );
    expect(editorController(tester, 'meter').text, 'not a reading');
  });

  testWidgets(
    'dirty typed fields survive refresh and expose actual CRDT conflicts',
    (tester) async {
      final fixture = await editorFixture(tester);
      await tester.pumpWidget(fixture.page());
      await untilEditor(
        tester,
        () => find.byKey(const Key('notes')).evaluate().isNotEmpty,
      );
      await enterEditor(tester, 'notes', 'Local notes.');
      await enterEditor(tester, 'meter', '105');
      await enterEditor(tester, 'answer:pressure', '24');
      await enterEditor(tester, 'answer:condition', 'Local condition.');
      final guard = find.ancestor(
        of: find.text('Inspect guard'),
        matching: find.byType(Card),
      );
      await tapEditor(
        tester,
        find.descendant(
          of: guard,
          matching: find.widgetWithText(ChoiceChip, 'Not applicable'),
        ),
      );
      await finishNativeWidgetAction(
        tester,
        () => fixture.fill(notes: 'Remote notes.', revision: 2),
      );
      fixture.updates.value++;
      await untilEditor(
        tester,
        () => find
            .textContaining('Your unsaved changes are still here')
            .evaluate()
            .isNotEmpty,
      );
      expect(editorController(tester, 'notes').text, 'Local notes.');
      expect(editorController(tester, 'meter').text, '105');
      expect(editorController(tester, 'answer:pressure').text, '24');
      expect(
        editorController(tester, 'answer:condition').text,
        'Local condition.',
      );
      expect(find.text('Replace inspection photo'), findsOneWidget);
      expect(
        tester
            .widget<ChoiceChip>(
              find.descendant(
                of: guard,
                matching: find.widgetWithText(ChoiceChip, 'Not applicable'),
              ),
            )
            .selected,
        isTrue,
      );
      await tapEditor(tester, find.text('Submit for review'));
      await untilEditor(
        tester,
        () => find.text('Resolve Inspection notes').evaluate().isNotEmpty,
      );
      expect(fixture.store.submissions, isEmpty);
      final fields = (await tester.runAsync(
        () => fixture.store.fields(jobId: fixture.job),
      ))!;
      expect(
        conflicts(fields),
        containsAll([
          'notes',
          'meter',
          'answer:guard',
          'answer:pressure',
          'answer:condition',
        ]),
      );
      expect(fields['notes'], containsAll(['Local notes.', 'Remote notes.']));
      await tapEditor(tester, find.text('Use: Local notes.'));
      await untilEditor(
        tester,
        () => find.text('Resolve Inspection notes').evaluate().isEmpty,
      );
      expect(fixture.store.submissions, isEmpty);
    },
  );

  testWidgets(
    'write queued ahead of dirty save is merged and held for review',
    (tester) async {
      final fixture = await editorFixture(tester);
      await tester.pumpWidget(fixture.page());
      await untilEditor(
        tester,
        () => find.byKey(const Key('notes')).evaluate().isNotEmpty,
      );
      await enterEditor(tester, 'notes', 'Queued local finding.');
      final release = Completer<void>();
      final gate = fixture.store.queue.run(() => release.future);
      final incoming = fixture.store.update({'meter': 120}, jobId: fixture.job);
      await tapEditor(tester, find.text('Submit for review'));
      release.complete();
      await finishNativeWidgetAction(tester, () async {
        await gate;
        await incoming;
      });
      await untilEditor(
        tester,
        () => find.text(changedInspectionMessage).evaluate().isNotEmpty,
      );
      expect(fixture.store.submissions, isEmpty);
      expect(editorController(tester, 'notes').text, 'Queued local finding.');
      expect(editorController(tester, 'meter').text, '120');
    },
  );

  testWidgets('incoming work during saved draft decoding requires review', (
    tester,
  ) async {
    final fixture = await editorFixture(tester);
    final pause = PausedEditorDecode();
    await tester.pumpWidget(fixture.page(decoder: pause.call));
    await untilEditor(
      tester,
      () => find.byKey(const Key('notes')).evaluate().isNotEmpty,
    );
    await enterEditor(tester, 'notes', 'Saved local finding.');
    pause.arm();
    final release = pause.release!;
    await tapEditor(tester, find.text('Submit for review'));
    await untilEditor(tester, () => pause.entered!.isCompleted);
    await finishNativeWidgetAction(
      tester,
      () => fixture.store.update({'meter': 130}, jobId: fixture.job),
    );
    release.complete();
    await untilEditor(
      tester,
      () => find.text(changedInspectionMessage).evaluate().isNotEmpty,
    );
    expect(fixture.store.submissions, isEmpty);
    expect(editorController(tester, 'notes').text, 'Saved local finding.');
    expect(editorController(tester, 'meter').text, '130');
  });

  testWidgets(
    'queued submit validates its start snapshot against displayed bytes',
    (tester) async {
      final fixture = await editorFixture(tester);
      final pause = PausedEditorDecode();
      await tester.pumpWidget(fixture.page(decoder: pause.call));
      await untilEditor(
        tester,
        () => find.byKey(const Key('notes')).evaluate().isNotEmpty,
      );
      pause.arm();
      final releaseDecode = pause.release!;
      await tapEditor(tester, find.text('Submit for review'));
      await untilEditor(tester, () => pause.entered!.isCompleted);
      final releaseQueue = Completer<void>();
      final gate = fixture.store.queue.run(() => releaseQueue.future);
      final incoming = fixture.store.update({
        'notes': 'Queued unseen notes.',
      }, jobId: fixture.job);
      releaseDecode.complete();
      await settleEditor(tester);
      releaseQueue.complete();
      await finishNativeWidgetAction(tester, () async {
        await gate;
        await incoming;
      });
      await untilEditor(
        tester,
        () => find.text(changedInspectionMessage).evaluate().isNotEmpty,
      );
      expect(fixture.store.submissions, isEmpty);
      expect(editorController(tester, 'notes').text, 'Queued unseen notes.');
      await tapEditor(tester, find.text('Submit for review'));
      await untilEditor(tester, () => fixture.store.submissions.isNotEmpty);
    },
  );

  testWidgets(
    'ordinary known dirty edits submit once and exact retry retains history',
    (tester) async {
      final fixture = await editorFixture(tester);
      await tester.pumpWidget(fixture.page());
      await untilEditor(
        tester,
        () => find.byKey(const Key('notes')).evaluate().isNotEmpty,
      );
      await enterEditor(tester, 'notes', 'First explicit finding.');
      await tapEditor(tester, find.text('Submit for review'));
      await untilEditor(tester, () => fixture.store.submissions.isNotEmpty);
      final first = Map<String, dynamic>.from(fixture.store.submissions.single)
        ..remove('_state');
      await finishNativeWidgetAction(
        tester,
        () => fixture.store.decide(first['id'] as String, approve: true),
      );
      final receipt = canonical(fixture.store.receipts.single);
      await tapEditor(tester, find.text('Submit for review'));
      expect(fixture.store.submissions, hasLength(1));
      await enterEditor(tester, 'notes', 'Second explicit finding.');
      await tapEditor(tester, find.text('Submit for review'));
      await untilEditor(tester, () => fixture.store.submissions.length == 2);
      final second = fixture.store.submissions.last;
      expect(second['submissionRevision'], 2);
      expect(second['predecessorId'], first['id']);
      expect(second['documentHash'], isNot(first['documentHash']));
      expect(canonical(fixture.store.receipts.single), receipt);
      expect(
        canonical(
          Map<String, dynamic>.from(fixture.store.submissions.first)
            ..remove('_state'),
        ),
        canonical(first),
      );
      expect(
        digest(base64Decode(second['document'] as String)),
        second['documentHash'],
      );
    },
  );
}
