import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/model.dart';
import 'package:maintenance_local/ui/inspection_page.dart';

import 'inspection_editor_coherence_support.dart';
import 'support/native_widget_cleanup.dart';

const _render = Key('answer-ack-classification-render');
const _unsaved = 'Earlier changes saved. Newer changes are still unsaved.';

class _DecodeGate {
  Completer<void>? entered;
  Completer<void>? release;
  bool fail = false;

  void arm({bool failure = false}) {
    entered = Completer<void>();
    release = Completer<void>();
    fail = failure;
  }

  Future<Json> call(Uint8List bytes) async {
    final fields = await decodeEditorFields(bytes);
    final gate = release;
    if (gate != null) {
      release = null;
      final shouldFail = fail;
      entered!.complete();
      await gate.future;
      if (shouldFail) throw StateError('Synthetic postwrite decode failure.');
    }
    return fields;
  }
}

Future<EditorFixture> _fixture(WidgetTester tester) async {
  final fixture = (await tester.runAsync(() async {
    final root = await Directory.systemTemp.createTemp('answer-ack-');
    final store = await LabStore.open(
      Directory('${root.path}/office'),
      office: true,
      maintenanceOnly: true,
    );
    await store.createCompany('Synthetic classification company');
    final equipment = await store.addEquipment(name: 'Synthetic generator');
    final checklist = await store.publishChecklist(
      title: 'Synthetic classification checks',
      items: [
        {'id': 'guard', 'label': 'Inspect guard', 'input_type': 'check'},
        {
          'id': 'pressure',
          'label': 'Oil pressure',
          'input_type': 'number',
          'min': 10,
          'max': 30,
          'unit': 'psi',
          'allow_na': true,
        },
        {
          'id': 'condition',
          'label': 'General condition',
          'input_type': 'text',
          'allow_na': true,
        },
        {
          'id': 'optional',
          'label': 'Optional response',
          'input_type': 'text',
          'required': false,
        },
      ],
    );
    final job = await store.prepareWork(
      equipmentId: equipment['id'] as String,
      templateId: checklist['id'] as String,
      title: 'Morning classification inspection',
    );
    final fixture = EditorFixture(root, store, job['id'] as String);
    await fixture.fill();
    return fixture;
  }))!;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await finishNativeWidgetCleanup(tester, fixture.close);
  });
  return fixture;
}

Future<void> _open(
  WidgetTester tester,
  EditorFixture fixture,
  _DecodeGate decoder, {
  double scale = 1,
  bool phone = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = phone
      ? const Size(412, 915)
      : const Size(900, 1400);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _render,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: 'Roboto'),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: InspectionPage(
          store: fixture.store,
          jobId: fixture.job,
          updates: fixture.updates,
          decodeFields: decoder.call,
        ),
      ),
    ),
  );
  await untilEditor(
    tester,
    () => find.byKey(const Key('answer:pressure')).evaluate().isNotEmpty,
  );
}

Finder _field(String id) => find.byKey(ValueKey('answer:$id'));
Finder _card(String id) =>
    find.ancestor(of: _field(id), matching: find.byType(Card));
Finder _chip(String id, String label) => find.descendant(
  of: _card(id),
  matching: find.widgetWithText(ChoiceChip, label),
);

VoidCallback _command(WidgetTester tester, {bool submit = false}) => submit
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

Future<Json> _fields(WidgetTester tester, EditorFixture fixture) async =>
    (await tester.runAsync(() => fixture.store.fields(jobId: fixture.job)))!;

Future<void> _finished(WidgetTester tester) async {
  await settleEditor(tester);
  await untilEditor(tester, () {
    final button = find.widgetWithText(OutlinedButton, 'Save work');
    return button.evaluate().isNotEmpty &&
        tester.widget<OutlinedButton>(button).onPressed != null;
  });
}

void _displayed(WidgetTester tester, String id, String raw, String? result) {
  expect(editorController(tester, 'answer:$id').text, raw);
  for (final entry in {
    'Pass': 'pass',
    'Needs action': 'action',
    'Not applicable': 'na',
  }.entries) {
    final chip = _chip(id, entry.key);
    if (chip.evaluate().isNotEmpty) {
      expect(
        tester.widget<ChoiceChip>(chip).selected,
        result == entry.value,
        reason: '$id must display the complete $result/$raw answer.',
      );
    }
  }
  expect(tester.widget<TextField>(_field(id)).enabled, result != 'na');
  expect(
    find.descendant(
      of: _card(id),
      matching: find.text(
        'Finding recorded. Explain the action needed in the inspection notes.',
      ),
    ),
    result == 'action' ? findsOneWidget : findsNothing,
  );
}

Future<void> _saved(
  WidgetTester tester,
  EditorFixture fixture,
  String id,
  String raw,
  String? result,
) async {
  await tapEditor(tester, find.text('Save work'));
  await _finished(tester);
  final fields = await _fields(tester, fixture);
  expect(valuesOf(fields)['answer:$id'], {'result': result, 'value': raw});
  expect(conflicts(fields), isEmpty);
  _displayed(tester, id, raw, result);
  expect(find.textContaining('Unsaved changes —'), findsNothing);
}

// Start the real enabled command, wait for its durable captured answer to reach
// decode (after acknowledgement), then deliver keyboard events to the exact
// still-painted enabled and focused EditableText. There is deliberately no
// frame pump between invoking the command and sending the platform input.
Future<void> _afterAck(
  WidgetTester tester,
  EditorFixture fixture,
  _DecodeGate decoder, {
  required String id,
  required Object? captured,
  required List<String> later,
  bool submit = false,
  bool beforeReplacementPaint = false,
  bool failure = false,
  Finder? selectBeforeCommand,
  Future<void> Function()? incoming,
}) async {
  final command = _command(tester, submit: submit);
  final field = _field(id);
  await tester.ensureVisible(field);
  await tester.showKeyboard(field);
  await settleEditor(tester);
  final painted = tester.widget<TextField>(field);
  final editable = find.descendant(
    of: field,
    matching: find.byType(EditableText),
  );
  expect(painted.enabled, isTrue);
  expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isTrue);
  expect(tester.testTextInput.hasAnyClients, isTrue);
  expect(tester.testTextInput.isVisible, isTrue);
  if (selectBeforeCommand != null) {
    await tester.tap(selectBeforeCommand);
    await tester.idle();
  }
  Completer<void>? release;
  try {
    await tester.runAsync(() async {
      decoder.arm(failure: failure);
      final gate = decoder.release!;
      release = gate;
      // The production callback returns the async save result even though the
      // button's VoidCallback type discards it. Observing that completion lets
      // the prepaint case prove installation without scheduling a frame.
      final operation = Function.apply(command, const []) as Future<bool>;
      await decoder.entered!.future.timeout(const Duration(seconds: 8));
      expect(
        valuesOf(await fixture.store.fields(jobId: fixture.job))['answer:$id'],
        captured,
      );
      if (beforeReplacementPaint) {
        gate.complete();
        await operation.timeout(const Duration(seconds: 8));
      }
      expect(tester.widget<TextField>(field), same(painted));
      expect(painted.enabled, isTrue);
      expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isTrue);
      expect(tester.testTextInput.isRegistered, isTrue);
      expect(tester.testTextInput.hasAnyClients, isTrue);
      for (final raw in later) {
        tester.testTextInput.enterText(raw);
        await Future<void>.delayed(Duration.zero);
        expect(editorController(tester, 'answer:$id').text, raw);
      }
      if (incoming != null) await incoming();
      if (!gate.isCompleted) gate.complete();
    });
  } finally {
    if (release != null && !release!.isCompleted) release!.complete();
  }
  await _finished(tester);
  expect(find.textContaining('Unsaved changes —'), findsOneWidget);
}

Future<void> _capture(WidgetTester tester, String name) async {
  final output = Platform.environment['ANSWER_ACK_RENDER_DIR'];
  if (output == null) return;
  await tester.ensureVisible(_card('pressure'));
  await settleEditor(tester);
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_render),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      await Directory(output).create(recursive: true);
      await File('$output/$name.png').writeAsBytes(bytes.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initializeEditorNative();
    final fonts = FontLoader('Roboto')
      ..addFont(
        File(
          '../../assets/fonts/Roboto-Regular.ttf',
        ).readAsBytes().then(ByteData.sublistView),
      )
      ..addFont(
        File(
          '../../assets/fonts/Roboto-Bold.ttf',
        ).readAsBytes().then(ByteData.sublistView),
      );
    await fonts.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  testWidgets(
    'numeric explicit Action survives ack and two late platform events',
    (tester) async {
      final fixture = await _fixture(tester);
      final decoder = _DecodeGate();
      await _open(tester, fixture, decoder);
      await tapEditor(tester, _chip('pressure', 'Needs action'));
      await enterEditor(tester, 'answer:pressure', '35');
      _displayed(tester, 'pressure', '35', 'action');
      await _afterAck(
        tester,
        fixture,
        decoder,
        id: 'pressure',
        captured: {'result': 'action', 'value': '35'},
        later: ['25', '24,5'],
      );
      _displayed(tester, 'pressure', '24,5', 'action');
      expect(find.text(_unsaved), findsOneWidget);
      await _saved(tester, fixture, 'pressure', '24,5', 'action');
      expect(fixture.store.submissions, isEmpty);
    },
  );

  testWidgets('text Action survives decoded replacement before its first paint', (
    tester,
  ) async {
    final fixture = await _fixture(tester);
    final decoder = _DecodeGate();
    await _open(tester, fixture, decoder);
    await tapEditor(tester, _chip('condition', 'Needs action'));
    await enterEditor(tester, 'answer:condition', 'First action finding.');
    await _afterAck(
      tester,
      fixture,
      decoder,
      id: 'condition',
      captured: {'result': 'action', 'value': 'First action finding.'},
      later: ['Later action finding.'],
      beforeReplacementPaint: true,
    );
    _displayed(tester, 'condition', 'Later action finding.', 'action');
    await _saved(
      tester,
      fixture,
      'condition',
      'Later action finding.',
      'action',
    );
    // Ordinary blank input still clears Action; subsequent text is automatic Pass.
    await enterEditor(tester, 'answer:condition', '   ');
    _displayed(tester, 'condition', '   ', null);
    await enterEditor(tester, 'answer:condition', 'Ordinary response.');
    await _saved(tester, fixture, 'condition', 'Ordinary response.', 'pass');
  });

  for (final id in ['pressure', 'condition']) {
    testWidgets(
      '$id N/A selected before repaint survives acknowledged keyboard input',
      (tester) async {
        final fixture = await _fixture(tester);
        final decoder = _DecodeGate();
        await _open(tester, fixture, decoder);
        final first = id == 'pressure' ? '19' : 'Condition 1';
        final late = id == 'pressure' ? '25' : 'Late platform response';
        await _afterAck(
          tester,
          fixture,
          decoder,
          id: id,
          captured: {'result': 'na', 'value': first},
          later: [late],
          selectBeforeCommand: _chip(id, 'Not applicable'),
        );
        _displayed(tester, id, late, 'na');
        await _saved(tester, fixture, id, late, 'na');
        await tapEditor(tester, _chip(id, 'Pass'));
        _displayed(tester, id, late, 'pass');
      },
    );
  }

  testWidgets(
    'automatic out-of-range Action retains existing in-range typing semantics',
    (tester) async {
      final fixture = await _fixture(tester);
      final decoder = _DecodeGate();
      await _open(tester, fixture, decoder);
      await enterEditor(tester, 'answer:pressure', '35');
      _displayed(tester, 'pressure', '35', 'action');
      await _afterAck(
        tester,
        fixture,
        decoder,
        id: 'pressure',
        captured: {'result': 'action', 'value': '35'},
        later: ['25'],
      );
      await _saved(tester, fixture, 'pressure', '25', 'action');
      await tapEditor(tester, _chip('pressure', 'Pass'));
      await _saved(tester, fixture, 'pressure', '25', 'pass');
    },
  );

  testWidgets(
    'unknown number uses zero and inclusive numeric boundaries normally',
    (tester) async {
      final fixture = await _fixture(tester);
      final decoder = _DecodeGate();
      await _open(tester, fixture, decoder);
      await enterEditor(tester, 'answer:pressure', 'NaN');
      _displayed(tester, 'pressure', 'NaN', null);
      await _afterAck(
        tester,
        fixture,
        decoder,
        id: 'pressure',
        captured: {'result': null, 'value': 'NaN'},
        later: ['0'],
      );
      await _saved(tester, fixture, 'pressure', '0', 'action');
      await tapEditor(tester, _chip('pressure', 'Pass'));
      await enterEditor(tester, 'answer:pressure', '10');
      _displayed(tester, 'pressure', '10', 'pass');
      await enterEditor(tester, 'answer:pressure', '30');
      await _saved(tester, fixture, 'pressure', '30', 'pass');
      await enterEditor(tester, 'answer:pressure', '30.01');
      _displayed(tester, 'pressure', '30.01', 'action');
    },
  );

  testWidgets(
    'late invalid numeric input clears Action rather than making every answer sticky',
    (tester) async {
      final fixture = await _fixture(tester);
      final decoder = _DecodeGate();
      await _open(tester, fixture, decoder);
      await tapEditor(tester, _chip('pressure', 'Needs action'));
      await enterEditor(tester, 'answer:pressure', '35');
      await _afterAck(
        tester,
        fixture,
        decoder,
        id: 'pressure',
        captured: {'result': 'action', 'value': '35'},
        later: ['not a number'],
      );
      await _saved(tester, fixture, 'pressure', 'not a number', null);
      await enterEditor(tester, 'answer:pressure', '25');
      await _saved(tester, fixture, 'pressure', '25', 'pass');
    },
  );

  testWidgets(
    'acknowledged optional null remains cleared when typing resumes on old frame',
    (tester) async {
      final fixture = await _fixture(tester);
      final decoder = _DecodeGate();
      await _open(tester, fixture, decoder);
      await enterEditor(tester, 'answer:optional', 'Earlier optional finding.');
      await tapEditor(tester, _chip('optional', 'Needs action'));
      final clear = find.descendant(
        of: _card('optional'),
        matching: find.text('Leave optional step unanswered'),
      );
      await _afterAck(
        tester,
        fixture,
        decoder,
        id: 'optional',
        captured: null,
        later: ['New optional response.'],
        selectBeforeCommand: clear,
      );
      await _saved(
        tester,
        fixture,
        'optional',
        'New optional response.',
        'pass',
      );
    },
  );

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'raw numeric value and psi survive ack at ${scale.toInt()}x phone text',
      (tester) async {
        final fixture = await _fixture(tester);
        final decoder = _DecodeGate();
        await _open(tester, fixture, decoder, scale: scale, phone: true);
        await enterEditor(tester, 'answer:pressure', '10,00');
        await _afterAck(
          tester,
          fixture,
          decoder,
          id: 'pressure',
          captured: {'result': 'pass', 'value': '10,00'},
          later: [' 30,00 '],
        );
        _displayed(tester, 'pressure', ' 30,00 ', 'pass');
        expect(
          tester.widget<TextField>(_field('pressure')).decoration!.labelText,
          'Reading (psi)',
        );
        expect(
          find.text(
            'Reading (psi) · Required · Expected 10–30 psi · Not applicable allowed',
          ),
          findsOneWidget,
        );
        await _capture(tester, 'raw-pressure-unsaved-${scale.toInt()}x');
        await _saved(tester, fixture, 'pressure', ' 30,00 ', 'pass');
        await _capture(tester, 'raw-pressure-saved-${scale.toInt()}x');
      },
    );
  }

  testWidgets(
    'postwrite decode failure preserves displayed Action through rebuild and retry',
    (tester) async {
      final fixture = await _fixture(tester);
      final decoder = _DecodeGate();
      await _open(tester, fixture, decoder);
      await tapEditor(tester, _chip('pressure', 'Needs action'));
      await enterEditor(tester, 'answer:pressure', '35');
      await _afterAck(
        tester,
        fixture,
        decoder,
        id: 'pressure',
        captured: {'result': 'action', 'value': '35'},
        later: ['25'],
        failure: true,
      );
      expect(find.text('Synthetic postwrite decode failure.'), findsOneWidget);
      fixture.updates.value++;
      await settleEditor(tester);
      _displayed(tester, 'pressure', '25', 'action');
      expect(valuesOf(await _fields(tester, fixture))['answer:pressure'], {
        'result': 'action',
        'value': '35',
      });
      await _saved(tester, fixture, 'pressure', '25', 'action');
      expect(fixture.store.submissions, isEmpty);
    },
  );

  testWidgets(
    'late full answer preserves immutable submission and concurrent conflict fence',
    (tester) async {
      final fixture = await _fixture(tester);
      final decoder = _DecodeGate();
      await _open(tester, fixture, decoder);
      await tapEditor(tester, _chip('pressure', 'Needs action'));
      await enterEditor(tester, 'answer:pressure', '35');
      await _afterAck(
        tester,
        fixture,
        decoder,
        id: 'pressure',
        captured: {'result': 'action', 'value': '35'},
        later: ['25'],
        submit: true,
      );
      _displayed(tester, 'pressure', '25', 'action');
      expect(fixture.store.submissions, hasLength(1));
      final submitted = Map<String, dynamic>.from(
        fixture.store.submissions.single,
      );
      final frozen = canonical(submitted);
      expect(submitted['values']['answer:pressure'], {
        'result': 'action',
        'value': '35',
      });
      final submittedBytes = base64Decode(submitted['document'] as String);
      expect(submitted['documentHash'], digest(submittedBytes));
      expect(
        valuesOf(
          (await tester.runAsync(() => decodeEditorFields(submittedBytes)))!,
        ),
        submitted['values'],
      );
      await finishNativeWidgetAction(
        tester,
        () => fixture.store.update({
          'answer:pressure': {'result': 'pass', 'value': '18'},
        }, jobId: fixture.job),
      );
      fixture.updates.value++;
      await settleEditor(tester);
      _displayed(tester, 'pressure', '25', 'action');
      await tapEditor(tester, find.text('Submit for review'));
      await untilEditor(
        tester,
        () => find.text('Resolve Oil pressure').evaluate().isNotEmpty,
      );
      final fields = await _fields(tester, fixture);
      expect(conflicts(fields), contains('answer:pressure'));
      expect(
        fields['answer:pressure'],
        containsAll([
          {'result': 'action', 'value': '25'},
          {'result': 'pass', 'value': '18'},
        ]),
      );
      expect(fixture.store.submissions, hasLength(1));
      expect(canonical(fixture.store.submissions.single), frozen);
    },
  );
}
