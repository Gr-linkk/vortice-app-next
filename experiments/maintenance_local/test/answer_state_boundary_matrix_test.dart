import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/model.dart';
import 'package:maintenance_local/ui/inspection_page.dart';

import 'inspection_editor_coherence_support.dart';
import 'support/native_widget_cleanup.dart';

enum _Boundary { queued, decoding, installed, repainted, failedRebuilt }

enum _EventKind { type, select, clear }

class _Event {
  const _Event.type(this.value) : kind = _EventKind.type;
  const _Event.select(this.value) : kind = _EventKind.select;
  const _Event.clear() : kind = _EventKind.clear, value = '';
  final _EventKind kind;
  final String value;
}

class _Case {
  const _Case(
    this.name,
    this.id,
    this.boundary, {
    required this.initialRaw,
    this.initialResult = 'pass',
    this.beforeCapture = const [],
    required this.captured,
    required this.events,
    required this.expected,
  });
  final String name, id, initialRaw;
  final String? initialResult;
  final _Boundary boundary;
  final List<_Event> beforeCapture, events;
  final Object? captured, expected;
}

// This is an equivalence-class matrix, not a Cartesian product. Both input
// types exercise stale N/A callbacks; optional null exercises absence versus a
// present tombstone. Each async boundary has a complete-answer control. Sticky
// Action, automatic Pass, invalid/blank clearing, raw numbers and identical
// repeated edits exercise the distinct classification and identity rules.
// The final integration case checks immutable submission and the CRDT fence.
const _cases = <_Case>[
  _Case(
    'number unpainted N/A survives decoded installation',
    'pressure',
    _Boundary.installed,
    initialRaw: '19',
    beforeCapture: [_Event.select('Not applicable')],
    captured: {'result': 'na', 'value': '19'},
    events: [_Event.type('25'), _Event.type('24,5')],
    expected: {'result': 'na', 'value': '24,5'},
  ),
  _Case(
    'text unpainted N/A survives decoded installation',
    'condition',
    _Boundary.installed,
    initialRaw: 'Condition 1',
    beforeCapture: [_Event.select('Not applicable')],
    captured: {'result': 'na', 'value': 'Condition 1'},
    events: [_Event.type('Later'), _Event.type('Latest')],
    expected: {'result': 'na', 'value': 'Latest'},
  ),
  _Case(
    'optional unpainted clear survives decoded installation',
    'optional',
    _Boundary.installed,
    initialRaw: 'Earlier finding',
    initialResult: 'action',
    beforeCapture: [_Event.clear()],
    captured: null,
    events: [_Event.type('New optional response')],
    expected: {'result': 'pass', 'value': 'New optional response'},
  ),
  _Case(
    'text Action survives queued capture and two events',
    'condition',
    _Boundary.queued,
    initialRaw: 'Captured finding',
    initialResult: 'action',
    captured: {'result': 'action', 'value': 'Captured finding'},
    events: [_Event.type('Later finding'), _Event.type('Latest finding')],
    expected: {'result': 'action', 'value': 'Latest finding'},
  ),
  _Case(
    'number Pass becomes Action while write awaits queue',
    'pressure',
    _Boundary.queued,
    initialRaw: '19',
    captured: {'result': 'pass', 'value': '19'},
    events: [_Event.type('35'), _Event.type('25')],
    expected: {'result': 'action', 'value': '25'},
  ),
  _Case(
    'number Action survives acknowledged decode and raw events',
    'pressure',
    _Boundary.decoding,
    initialRaw: '35',
    initialResult: 'action',
    captured: {'result': 'action', 'value': '35'},
    events: [_Event.type('25'), _Event.type('24,5')],
    expected: {'result': 'action', 'value': '24,5'},
  ),
  _Case(
    'identical repeated value still has a newer edit identity',
    'pressure',
    _Boundary.decoding,
    initialRaw: '35',
    initialResult: 'action',
    captured: {'result': 'action', 'value': '35'},
    events: [_Event.type('35'), _Event.type('35')],
    expected: {'result': 'action', 'value': '35'},
  ),
  _Case(
    'unknown number becomes real zero after acknowledgement',
    'pressure',
    _Boundary.decoding,
    initialRaw: 'NaN',
    initialResult: null,
    captured: {'result': null, 'value': 'NaN'},
    events: [_Event.type('0')],
    expected: {'result': 'action', 'value': '0'},
  ),
  _Case(
    'raw comma boundary and units survive acknowledgement',
    'pressure',
    _Boundary.decoding,
    initialRaw: '10,00',
    captured: {'result': 'pass', 'value': '10,00'},
    events: [_Event.type(' 30,00 ')],
    expected: {'result': 'pass', 'value': ' 30,00 '},
  ),
  _Case(
    'invalid number clears Action before next automatic Pass',
    'pressure',
    _Boundary.installed,
    initialRaw: '35',
    initialResult: 'action',
    captured: {'result': 'action', 'value': '35'},
    events: [_Event.type('not a number'), _Event.type('25')],
    expected: {'result': 'pass', 'value': '25'},
  ),
  _Case(
    'blank text clears Action before next automatic Pass',
    'condition',
    _Boundary.decoding,
    initialRaw: 'Captured finding',
    initialResult: 'action',
    captured: {'result': 'action', 'value': 'Captured finding'},
    events: [_Event.type('   '), _Event.type('Fresh response')],
    expected: {'result': 'pass', 'value': 'Fresh response'},
  ),
  _Case(
    'optional clear after acknowledgement replaces full Action intent',
    'optional',
    _Boundary.decoding,
    initialRaw: 'Captured finding',
    initialResult: 'action',
    captured: {'result': 'action', 'value': 'Captured finding'},
    events: [_Event.clear(), _Event.type('Fresh response')],
    expected: {'result': 'pass', 'value': 'Fresh response'},
  ),
  _Case(
    'N/A selected after installation owns subsequent value events',
    'pressure',
    _Boundary.installed,
    initialRaw: '19',
    captured: {'result': 'pass', 'value': '19'},
    events: [_Event.select('Not applicable'), _Event.type('25')],
    expected: {'result': 'na', 'value': '25'},
  ),
  _Case(
    'typing and selections use one current full-answer intent',
    'condition',
    _Boundary.installed,
    initialRaw: 'Captured response',
    captured: {'result': 'pass', 'value': 'Captured response'},
    events: [
      _Event.type('Later response'),
      _Event.select('Needs action'),
      _Event.type('Latest finding'),
      _Event.select('Pass'),
    ],
    expected: {'result': 'pass', 'value': 'Latest finding'},
  ),
  _Case(
    'repainted Action retains ordinary focused-input semantics',
    'condition',
    _Boundary.repainted,
    initialRaw: 'Captured finding',
    initialResult: 'action',
    captured: {'result': 'action', 'value': 'Captured finding'},
    events: [_Event.type('Later finding')],
    expected: {'result': 'action', 'value': 'Later finding'},
  ),
  _Case(
    'acknowledged N/A alone survives decode failure and benign rebuild',
    'pressure',
    _Boundary.failedRebuilt,
    initialRaw: '19',
    beforeCapture: [_Event.select('Not applicable')],
    captured: {'result': 'na', 'value': '19'},
    events: [],
    expected: {'result': 'na', 'value': '19'},
  ),
  _Case(
    'optional tombstone survives decode failure rebuild and new text',
    'optional',
    _Boundary.failedRebuilt,
    initialRaw: 'Earlier finding',
    initialResult: 'action',
    beforeCapture: [_Event.clear()],
    captured: null,
    events: [_Event.type('Fresh response')],
    expected: {'result': 'pass', 'value': 'Fresh response'},
  ),
  _Case(
    'acknowledged Action alone survives failure rebuild and typing',
    'pressure',
    _Boundary.failedRebuilt,
    initialRaw: '35',
    initialResult: 'action',
    captured: {'result': 'action', 'value': '35'},
    events: [_Event.type('25')],
    expected: {'result': 'action', 'value': '25'},
  ),
];

class _DecodeGate {
  Completer<void>? entered, release;
  bool failure = false;

  void arm({bool fail = false}) {
    entered = Completer<void>();
    release = Completer<void>();
    failure = fail;
  }

  Future<Json> call(Uint8List bytes) async {
    final fields = await decodeEditorFields(bytes);
    final gate = release;
    if (gate != null) {
      release = null;
      entered!.complete();
      await gate.future;
      if (failure) throw StateError('Synthetic matrix decode failure.');
    }
    return fields;
  }
}

Future<EditorFixture> _fixture(WidgetTester tester) async {
  final fixture = (await tester.runAsync(() async {
    final root = await Directory.systemTemp.createTemp('answer-state-matrix-');
    final store = await LabStore.open(
      Directory('${root.path}/office'),
      office: true,
      maintenanceOnly: true,
    );
    await store.createCompany('Synthetic answer-state company');
    final equipment = await store.addEquipment(name: 'Synthetic generator');
    final checklist = await store.publishChecklist(
      title: 'Synthetic boundary checks',
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
      title: 'Synthetic boundary inspection',
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
  _DecodeGate decoder,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(900, 1400);
  await tester.pumpWidget(
    MaterialApp(
      home: InspectionPage(
        store: fixture.store,
        jobId: fixture.job,
        updates: fixture.updates,
        decodeFields: decoder.call,
      ),
    ),
  );
  await untilEditor(tester, () => _field('pressure').evaluate().isNotEmpty);
}

Finder _field(String id) => find.byKey(ValueKey('answer:$id'));
Finder _card(String id) =>
    find.ancestor(of: _field(id), matching: find.byType(Card));
Finder _chip(String id, String label) => find.descendant(
  of: _card(id),
  matching: find.widgetWithText(ChoiceChip, label),
);
Finder _clear(String id) => find.descendant(
  of: _card(id),
  matching: find.widgetWithText(TextButton, 'Leave optional step unanswered'),
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

void _displayed(WidgetTester tester, String id, Object? expected) {
  final answer = expected is Map
      ? Map<String, dynamic>.from(expected)
      : <String, dynamic>{};
  expect(editorController(tester, 'answer:$id').text, answer['value'] ?? '');
  for (final entry in {
    'Pass': 'pass',
    'Needs action': 'action',
    'Not applicable': 'na',
  }.entries) {
    final chip = _chip(id, entry.key);
    if (chip.evaluate().isNotEmpty) {
      expect(
        tester.widget<ChoiceChip>(chip).selected,
        answer['result'] == entry.value,
        reason: '$id must show one complete answer: $expected',
      );
    }
  }
  expect(
    tester.widget<TextField>(_field(id)).enabled,
    answer['result'] != 'na',
  );
  expect(
    find.descendant(
      of: _card(id),
      matching: find.text(
        'Finding recorded. Explain the action needed in the inspection notes.',
      ),
    ),
    answer['result'] == 'action' ? findsOneWidget : findsNothing,
  );
}

void _activeClient(WidgetTester tester, String id, TextField painted) {
  final field = _field(id);
  expect(tester.widget<TextField>(field), same(painted));
  expect(painted.enabled, isTrue);
  final editable = find.descendant(
    of: field,
    matching: find.byType(EditableText),
  );
  expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isTrue);
  expect(tester.testTextInput.isRegistered, isTrue);
  expect(tester.testTextInput.hasAnyClients, isTrue);
  expect(tester.testTextInput.isVisible, isTrue);
}

Future<TextField> _focus(WidgetTester tester, String id) async {
  await tester.ensureVisible(_field(id));
  await tester.showKeyboard(_field(id));
  await settleEditor(tester);
  final painted = tester.widget<TextField>(_field(id));
  _activeClient(tester, id, painted);
  return painted;
}

// No frame is drawn between these pointer/platform events. The assertion before
// every event proves this is the real enabled, registered, focused client, even
// when the model already considers the answer N/A or the operation busy.
Future<void> _events(
  WidgetTester tester,
  String id,
  TextField painted,
  List<_Event> events,
) async {
  for (final event in events) {
    _activeClient(tester, id, painted);
    switch (event.kind) {
      case _EventKind.type:
        await tester.runAsync(() async {
          tester.testTextInput.enterText(event.value);
          await Future<void>.delayed(Duration.zero);
          expect(editorController(tester, 'answer:$id').text, event.value);
        });
      case _EventKind.select:
        expect(
          tester.widget<ChoiceChip>(_chip(id, event.value)).onSelected,
          isNotNull,
        );
        await tester.tap(_chip(id, event.value));
        await tester.idle();
      case _EventKind.clear:
        expect(tester.widget<TextButton>(_clear(id)).onPressed, isNotNull);
        await tester.tap(_clear(id));
        await tester.idle();
        expect(editorController(tester, 'answer:$id').text, '');
    }
  }
}

Future<void> _prepare(WidgetTester tester, _Case row) async {
  await enterEditor(tester, 'answer:${row.id}', row.initialRaw);
  if (row.initialResult != null) {
    await tapEditor(
      tester,
      _chip(row.id, row.initialResult == 'action' ? 'Needs action' : 'Pass'),
    );
  }
  _displayed(tester, row.id, {
    'result': row.initialResult,
    'value': row.initialRaw,
  });
}

Future<void> _race(
  WidgetTester tester,
  EditorFixture fixture,
  _DecodeGate decoder,
  _Case row, {
  bool submit = false,
}) async {
  var painted = await _focus(tester, row.id);
  final command = _command(tester, submit: submit);
  Completer<void>? releaseDecode, releaseQueue;
  Future<bool>? operation;
  try {
    await _events(tester, row.id, painted, row.beforeCapture);
    Completer<void>? queueEntered;
    await tester.runAsync(() async {
      decoder.arm(fail: row.boundary == _Boundary.failedRebuilt);
      releaseDecode = decoder.release!;
      if (row.boundary == _Boundary.queued) {
        queueEntered = Completer<void>();
        releaseQueue = Completer<void>();
      }
      if (queueEntered != null) {
        unawaited(
          fixture.store.queue.run(() async {
            queueEntered!.complete();
            await releaseQueue!.future;
          }),
        );
      }
      // Keep the async command in the real event loop, then leave runAsync to
      // dispatch pointer events and drain their microtasks without a frame.
      operation = Function.apply(command, const []) as Future<bool>;
      if (queueEntered != null) {
        await queueEntered!.future.timeout(const Duration(seconds: 8));
      } else {
        await decoder.entered!.future.timeout(const Duration(seconds: 8));
      }
    });
    if (queueEntered != null) {
      await _events(tester, row.id, painted, row.events);
      await tester.runAsync(() async {
        releaseQueue!.complete();
        await decoder.entered!.future.timeout(const Duration(seconds: 8));
      });
    }
    expect(
      valuesOf(await _fields(tester, fixture))['answer:${row.id}'],
      row.captured,
      reason: 'The durable write contains only frozen captured intent.',
    );
    if (row.boundary == _Boundary.installed) {
      await tester.runAsync(() async {
        releaseDecode!.complete();
        await operation!.timeout(const Duration(seconds: 8));
      });
      _activeClient(tester, row.id, painted);
    }
    if (row.boundary == _Boundary.decoding ||
        row.boundary == _Boundary.installed) {
      await _events(tester, row.id, painted, row.events);
    }
    await tester.runAsync(() async {
      if (!releaseDecode!.isCompleted) releaseDecode!.complete();
      await operation!.timeout(const Duration(seconds: 8));
    });
  } finally {
    if (releaseQueue != null && !releaseQueue!.isCompleted) {
      releaseQueue!.complete();
    }
    if (releaseDecode != null && !releaseDecode!.isCompleted) {
      releaseDecode!.complete();
    }
  }
  await _finished(tester);
  if (row.boundary == _Boundary.failedRebuilt) {
    expect(find.text('Synthetic matrix decode failure.'), findsOneWidget);
    expect(find.textContaining('Unsaved changes —'), findsNothing);
    _displayed(tester, row.id, row.captured);
    final state = tester.state(find.byType(InspectionPage));
    await _open(tester, fixture, decoder);
    expect(tester.state(find.byType(InspectionPage)), same(state));
    _displayed(tester, row.id, row.captured);
  }
  if ((row.boundary == _Boundary.repainted ||
          row.boundary == _Boundary.failedRebuilt) &&
      row.events.isNotEmpty) {
    painted = await _focus(tester, row.id);
    await _events(tester, row.id, painted, row.events);
    await settleEditor(tester);
  }
  _displayed(tester, row.id, row.expected);
  expect(
    find.textContaining('Unsaved changes —'),
    row.events.isEmpty ? findsNothing : findsOneWidget,
  );
  expect(
    valuesOf(await _fields(tester, fixture))['answer:${row.id}'],
    row.captured,
    reason: 'Later input requires a subsequent explicit Save.',
  );
  if (row.id == 'pressure') {
    expect(
      tester.widget<TextField>(_field(row.id)).decoration!.labelText,
      'Reading (psi)',
    );
  }
}

Future<void> _persist(
  WidgetTester tester,
  EditorFixture fixture,
  _Case row,
) async {
  await tapEditor(tester, find.text('Save work'));
  await _finished(tester);
  final fields = await _fields(tester, fixture);
  expect(valuesOf(fields)['answer:${row.id}'], row.expected);
  expect(conflicts(fields), isEmpty);
  _displayed(tester, row.id, row.expected);
  expect(find.textContaining('Unsaved changes —'), findsNothing);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initializeEditorNative);
  for (final row in _cases) {
    testWidgets('answer-state matrix: ${row.name}', (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = await _fixture(tester);
      final decoder = _DecodeGate();
      await _open(tester, fixture, decoder);
      await _prepare(tester, row);
      await _race(tester, fixture, decoder, row);
      await _persist(tester, fixture, row);
      expect(fixture.store.submissions, isEmpty);
    });
  }

  testWidgets(
    'answer-state matrix: frozen submission and remote conflict fence',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = await _fixture(tester);
      final decoder = _DecodeGate();
      const row = _Case(
        'submission',
        'pressure',
        _Boundary.decoding,
        initialRaw: '35',
        initialResult: 'action',
        captured: {'result': 'action', 'value': '35'},
        events: [_Event.type('25'), _Event.select('Pass'), _Event.type('24,5')],
        expected: {'result': 'pass', 'value': '24,5'},
      );
      await _open(tester, fixture, decoder);
      await _prepare(tester, row);
      await _race(tester, fixture, decoder, row, submit: true);
      expect(fixture.store.submissions, hasLength(1));
      final submitted = fixture.store.submissions.single;
      final frozen = canonical(submitted);
      expect(submitted['values']['answer:pressure'], row.captured);
      final bytes = base64Decode(submitted['document'] as String);
      expect(submitted['documentHash'], digest(bytes));
      expect(
        valuesOf((await tester.runAsync(() => decodeEditorFields(bytes)))!),
        submitted['values'],
      );

      const incoming = {'result': 'action', 'value': '18'};
      await finishNativeWidgetAction(
        tester,
        () => fixture.store.update({
          'answer:pressure': incoming,
        }, jobId: fixture.job),
      );
      fixture.updates.value++;
      await settleEditor(tester);
      _displayed(tester, row.id, row.expected);
      await tapEditor(tester, find.text('Submit for review'));
      await untilEditor(
        tester,
        () => find.text('Resolve Oil pressure').evaluate().isNotEmpty,
      );
      final fields = await _fields(tester, fixture);
      expect(conflicts(fields), contains('answer:pressure'));
      expect(fields['answer:pressure'], containsAll([row.expected, incoming]));
      expect(fixture.store.submissions, hasLength(1));
      expect(canonical(fixture.store.submissions.single), frozen);
    },
  );
}
