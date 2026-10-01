import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
// Exercise the same platform seam as the existing native gallery render tests.
// ignore: depend_on_referenced_packages
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/model.dart';
import 'package:maintenance_local/src/rust/api/documents.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';
import 'package:maintenance_local/ui/inspection_page.dart';

import 'support/native_widget_cleanup.dart';

const _boundary = Key('independent-inflight-editor-render');
const _firstNotes = 'Synthetic note captured by the command.';
const _lateNotes = 'Synthetic platform note received before the busy repaint.';

class _Fixture {
  _Fixture(this.root, this.store, this.job);
  final Directory root;
  final LabStore store;
  final String job;
  final updates = ValueNotifier<int>(0);
  static final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );

  static Future<_Fixture> open() async {
    final root = await Directory.systemTemp.createTemp('independent-inflight-');
    final store = await LabStore.open(
      Directory('${root.path}/office'),
      office: true,
      maintenanceOnly: true,
    );
    await store.createCompany('Synthetic inflight inspection company');
    final equipment = await store.addEquipment(
      name: 'Synthetic generator',
      meterUnit: 'hours',
    );
    final checklist = await store.publishChecklist(
      title: 'Synthetic inflight checklist',
      items: [
        {
          'id': 'guard',
          'label': 'Inspect synthetic guard',
          'input_type': 'check',
        },
        {
          'id': 'pressure',
          'label': 'Synthetic oil pressure',
          'input_type': 'number',
          'min': 10,
          'max': 30,
          'unit': 'psi',
        },
        {
          'id': 'condition',
          'label': 'Synthetic general condition',
          'input_type': 'text',
        },
      ],
    );
    final job =
        (await store.prepareWork(
              equipmentId: equipment['id'] as String,
              templateId: checklist['id'] as String,
              title: 'Synthetic morning inspection',
            ))['id']
            as String;
    await store.update({
      'answer:guard': {'result': 'pass', 'value': ''},
      'answer:pressure': {'result': 'pass', 'value': '18'},
      'answer:condition': {
        'result': 'pass',
        'value': 'Original synthetic condition',
      },
      'meter': 101,
      'notes': 'Original synthetic note',
    }, jobId: job);
    await store.attach(png, jobId: job);
    return _Fixture(root, store, job);
  }

  Future<void> close() async {
    updates.dispose();
    await store.close();
    await root.delete(recursive: true);
  }

  Widget page({
    double scale = 1,
    bool routed = false,
    Future<Json> Function(Uint8List)? decoder,
  }) => RepaintBoundary(
    key: _boundary,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Roboto',
        scaffoldBackgroundColor: const Color(0xfff7f4ed),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff103d3c),
          primary: const Color(0xff103d3c),
          surface: const Color(0xfff7f4ed),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: routed
          ? Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => InspectionPage(
                          store: store,
                          jobId: job,
                          updates: updates,
                          decodeFields: decoder,
                        ),
                      ),
                    ),
                    child: const Text('Open synthetic inspection'),
                  ),
                ),
              ),
            )
          : InspectionPage(
              store: store,
              jobId: job,
              updates: updates,
              decodeFields: decoder,
            ),
    ),
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var attempt = 0; attempt < 4; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 30));
  }
  expect(tester.takeException(), isNull);
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var attempt = 0; attempt < 80 && !ready(); attempt++) {
    await _settle(tester);
  }
  expect(
    ready(),
    isTrue,
    reason: 'The real native editor operation must finish.',
  );
}

TextEditingController _controller(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(ValueKey(key))).controller!;

Future<_Fixture> _fixture(
  WidgetTester tester, {
  double scale = 1,
  bool routed = false,
  Future<Json> Function(Uint8List)? decoder,
}) async {
  final fixture = (await tester.runAsync(_Fixture.open))!;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await finishNativeWidgetCleanup(tester, fixture.close);
  });
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    fixture.page(scale: scale, routed: routed, decoder: decoder),
  );
  if (routed) {
    await tester.tap(find.text('Open synthetic inspection'));
    await tester.pump();
  }
  await _until(
    tester,
    () => find.byKey(const Key('notes')).evaluate().isNotEmpty,
  );
  await _settle(tester);
  return fixture;
}

Future<void> _enter(WidgetTester tester, String key, String value) async {
  final field = find.byKey(ValueKey(key));
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
  await _settle(tester);
}

VoidCallback _command(WidgetTester tester, {required bool submit}) => submit
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

bool _ready(WidgetTester tester) =>
    find.widgetWithText(OutlinedButton, 'Save work').evaluate().isNotEmpty &&
    tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Save work'),
            )
            .onPressed !=
        null;

Future<Json> _values(WidgetTester tester, _Fixture fixture) async => valuesOf(
  (await tester.runAsync(() => fixture.store.fields(jobId: fixture.job)))!,
);

Future<void> _show(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.12);
  await tester.pump();
}

Future<void> _capture(WidgetTester tester, String name) async {
  final destination = Platform.environment['VORTICE_RENDER_OUTPUT'];
  if (destination == null || destination.isEmpty) return;
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_boundary),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$destination/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data!.buffer.asUint8List(), flush: true);
    } finally {
      image.dispose();
    }
  });
}

Future<void> _heldCommand(
  WidgetTester tester,
  _Fixture fixture, {
  required String field,
  required String late,
  required bool submit,
  VoidCallback? action,
}) async {
  final finder = find.byKey(ValueKey(field));
  await tester.ensureVisible(finder);
  await tester.showKeyboard(finder);
  await tester.pump();
  expect(tester.testTextInput.isRegistered, isTrue);
  expect(tester.widget<TextField>(finder).enabled, isTrue);
  final release = Completer<void>();
  addTearDown(() {
    if (!release.isCompleted) release.complete();
  });
  final holding = fixture.store.queue.run(() => release.future);
  (action ?? _command(tester, submit: submit))();
  // Deliver actual platform text to the enabled last-painted editor, without
  // pumping the busy-state frame or directly invoking a field callback.
  tester.testTextInput.enterText(late);
  await tester.idle();
  expect(tester.widget<TextField>(finder).enabled, isTrue);
  expect(_controller(tester, field).text, late);
  release.complete();
  await finishNativeWidgetAction(tester, () => holding);
  // Repaint the actual busy state before waiting for its terminal controls.
  await _settle(tester);
  await _until(tester, () => _ready(tester));
  await _settle(tester);
}

Future<void> _runCommand(WidgetTester tester, {bool submit = false}) async {
  _command(tester, submit: submit)();
  await _settle(tester);
  await _until(tester, () => _ready(tester));
  await _settle(tester);
}

Future<void> _assertFrozen(WidgetTester tester, _Fixture fixture) async {
  for (final record in fixture.store.submissions) {
    final bytes = base64Decode(record['document'] as String);
    expect(record['documentHash'], digest(bytes));
    final fields = (await tester.runAsync(
      () async => jsonDecode(await documentValues(bytes: bytes)) as Json,
    ))!;
    expect(
      record['values'],
      valuesOf(fields),
      reason:
          'Frozen submitted values must describe its exact native document.',
    );
  }
}

Future<void> _assertRetained(
  WidgetTester tester,
  _Fixture fixture,
  String key,
  String raw,
  Object? expected,
) async {
  final values = await _values(tester, fixture);
  final stored = values[key];
  final visible = _controller(tester, key).text;
  final durable = canonical(stored) == canonical(expected);
  expect(
    durable || visible == raw,
    isTrue,
    reason:
        'A platform edit accepted by the last enabled form must be durable or visibly retained. key=$key; stored=$stored; visible=$visible; intent=$raw.',
  );
  if (!durable) {
    expect(
      find.textContaining('Unsaved changes —'),
      findsOneWidget,
      reason: 'Retained input must be identified as unsaved.',
    );
  }
  await _assertFrozen(tester, fixture);
}

Future<void> _fieldCase(
  WidgetTester tester, {
  required String key,
  required String raw,
  required Object expected,
  required bool submit,
  double scale = 1,
}) async {
  final fixture = await _fixture(tester, scale: scale);
  final clicked = {...await _values(tester, fixture), 'notes': _firstNotes};
  await _enter(tester, 'notes', _firstNotes);
  await _heldCommand(tester, fixture, field: key, late: raw, submit: submit);
  await _assertRetained(tester, fixture, key, raw, expected);
  if (submit) {
    expect(fixture.store.submissions, hasLength(1));
    expect(
      fixture.store.submissions.single['values'],
      clicked,
      reason:
          'The in-flight command submits the clicked version, not later unsaved platform input.',
    );
  } else {
    expect(fixture.store.submissions, isEmpty);
  }
  final originalRecords = canonical(fixture.store.submissions);
  if (key == 'notes') {
    await _show(tester, find.byKey(const Key('notes')));
    await _capture(
      tester,
      'notes-${submit ? 'submit' : 'save'}-retained-${scale.toInt()}x',
    );
    await _show(tester, find.textContaining('Unsaved changes —'));
    await _capture(
      tester,
      'notes-${submit ? 'submit' : 'save'}-unsaved-${scale.toInt()}x',
    );
  }
  await _runCommand(tester);
  expect((await _values(tester, fixture))[key], expected);
  expect(
    canonical(fixture.store.submissions),
    originalRecords,
    reason: 'Saving later input cannot rewrite a frozen submitted record.',
  );
  await _runCommand(tester, submit: true);
  expect(fixture.store.submissions.last['values'][key], expected);
  await _assertFrozen(tester, fixture);
}

class _Picker extends ImagePickerPlatform {
  _Picker(this.path);
  final String path;
  final entered = Completer<void>(), release = Completer<void>();
  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    expect(source, ImageSource.gallery);
    entered.complete();
    await release.future;
    return XFile(path);
  }
}

class _DecodeGate {
  bool armed = false;
  final entered = Completer<void>(), release = Completer<void>();
  Json? savedFields;

  Future<Json> call(Uint8List bytes) async {
    final fields = jsonDecode(await documentValues(bytes: bytes)) as Json;
    if (armed && !entered.isCompleted) {
      savedFields = fields;
      entered.complete();
      await release.future;
    }
    return fields;
  }
}

Future<void> _withoutPainting(
  WidgetTester tester,
  bool Function() ready,
) async {
  for (var i = 0; i < 80 && !ready(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.idle();
  }
  expect(
    ready(),
    isTrue,
    reason:
        'The native operation must reach the synthetic picker without painting another form.',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await RustLib.init(
      externalLibrary: ExternalLibrary.open(
        Platform.environment['MAINTENANCE_NATIVE_LIBRARY'] ??
            File('rust/target/debug/librust_lib_sync_lab.so').absolute.path,
      ),
    );
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
    'independent platform notes arriving before submit busy repaint are retained',
    (tester) => _fieldCase(
      tester,
      key: 'notes',
      raw: _lateNotes,
      expected: _lateNotes,
      submit: true,
    ),
  );

  final cases = <({String key, String raw, Object expected})>[
    (key: 'notes', raw: _lateNotes, expected: _lateNotes),
    (
      key: 'answer:condition',
      raw: 'Synthetic late checklist description',
      expected: {
        'result': 'pass',
        'value': 'Synthetic late checklist description',
      },
    ),
    (
      key: 'answer:pressure',
      raw: '35',
      expected: {'result': 'action', 'value': '35'},
    ),
  ];
  for (final submit in [false, true]) {
    for (final entry in cases) {
      if (submit && entry.key == 'notes') continue;
      if (submit && entry.key == 'answer:condition') continue;
      if (!submit && entry.key == 'answer:pressure') continue;
      testWidgets(
        '${submit ? 'submit' : 'save'} preserves late platform ${entry.key} including a new dirty key',
        (tester) => _fieldCase(
          tester,
          key: entry.key,
          raw: entry.raw,
          expected: entry.expected,
          submit: submit,
        ),
      );
    }
    testWidgets(
      '2x ${submit ? 'submit' : 'save'} retains later notes and immutable records',
      (tester) => _fieldCase(
        tester,
        key: 'notes',
        raw: _lateNotes,
        expected: _lateNotes,
        submit: submit,
        scale: 2,
      ),
    );

    testWidgets(
      '${submit ? 'submit' : 'save'} on an initially clean form retains new platform edits',
      (tester) async {
        final fixture = await _fixture(tester);
        await _heldCommand(
          tester,
          fixture,
          field: 'notes',
          late: _lateNotes,
          submit: submit,
        );
        await _assertRetained(tester, fixture, 'notes', _lateNotes, _lateNotes);
        await _runCommand(tester);
        expect((await _values(tester, fixture))['notes'], _lateNotes);
        await _assertFrozen(tester, fixture);
      },
    );

    testWidgets(
      '${submit ? 'submit' : 'save'} post-write decode window retains newly received platform text',
      (tester) async {
        final decode = _DecodeGate();
        addTearDown(() {
          if (!decode.release.isCompleted) decode.release.complete();
        });
        final fixture = await _fixture(tester, scale: 2, decoder: decode.call);
        await _enter(tester, 'notes', _firstNotes);
        final finder = find.byKey(const Key('notes'));
        await tester.showKeyboard(finder);
        await tester.pump();
        final before = digest(fixture.store.documentFor(fixture.job)!);
        decode.armed = true;
        _command(tester, submit: submit)();
        await _withoutPainting(tester, () => decode.entered.isCompleted);
        expect(digest(fixture.store.documentFor(fixture.job)!), isNot(before));
        expect(
          valuesOf(decode.savedFields!)['notes'],
          _firstNotes,
          reason:
              'The injected wait occurs after the real captured write, without replacing native results.',
        );
        expect(tester.widget<TextField>(finder).enabled, isTrue);
        tester.testTextInput.enterText(_lateNotes);
        await tester.idle();
        expect(_controller(tester, 'notes').text, _lateNotes);
        decode.release.complete();
        await _settle(tester);
        await _until(tester, () => _ready(tester));
        await _assertRetained(tester, fixture, 'notes', _lateNotes, _lateNotes);
        if (submit) {
          expect(
            fixture.store.submissions.single['values']['notes'],
            _firstNotes,
          );
        }
        await _show(tester, finder);
        await _capture(
          tester,
          '${submit ? 'submit' : 'save'}-postwrite-decode-retained-2x',
        );
        await _runCommand(tester);
        expect((await _values(tester, fixture))['notes'], _lateNotes);
        await _assertFrozen(tester, fixture);
      },
    );

    testWidgets(
      '${submit ? 'submit' : 'save'} retains invalid later meter input and requires correction on retry',
      (tester) async {
        final fixture = await _fixture(tester);
        await _enter(tester, 'meter', '102');
        await _heldCommand(
          tester,
          fixture,
          field: 'meter',
          late: 'not a meter',
          submit: submit,
        );
        expect(_controller(tester, 'meter').text, 'not a meter');
        expect(find.textContaining('Unsaved changes —'), findsOneWidget);
        final document = digest(fixture.store.documentFor(fixture.job)!);
        final records = canonical(fixture.store.submissions);
        await _runCommand(tester, submit: true);
        expect(digest(fixture.store.documentFor(fixture.job)!), document);
        expect(canonical(fixture.store.submissions), records);
        expect(_controller(tester, 'meter').text, 'not a meter');
        expect(
          find.textContaining('Enter a valid meter reading'),
          findsOneWidget,
        );
        await _enter(tester, 'meter', '103.5');
        await _runCommand(tester, submit: true);
        expect((await _values(tester, fixture))['meter'], 103.5);
        expect(fixture.store.submissions.last['values']['meter'], 103.5);
        await _assertFrozen(tester, fixture);
      },
    );

    testWidgets(
      '${submit ? 'submit' : 'save'} retains a real checklist choice pointer event before repaint',
      (tester) async {
        final fixture = await _fixture(tester);
        await _enter(tester, 'notes', _firstNotes);
        final card = find.ancestor(
          of: find.text('Inspect synthetic guard'),
          matching: find.byType(Card),
        );
        final choice = find.descendant(
          of: card,
          matching: find.widgetWithText(ChoiceChip, 'Needs action'),
        );
        await tester.ensureVisible(choice);
        await tester.pump();
        expect(tester.widget<ChoiceChip>(choice).onSelected, isNotNull);
        final release = Completer<void>();
        addTearDown(() {
          if (!release.isCompleted) release.complete();
        });
        final holding = fixture.store.queue.run(() => release.future);
        _command(tester, submit: submit)();
        await tester.tap(choice);
        await tester.idle();
        expect(
          tester.widget<ChoiceChip>(choice).onSelected,
          isNotNull,
          reason: 'The pointer targets the enabled last-painted chip.',
        );
        release.complete();
        await finishNativeWidgetAction(tester, () => holding);
        await _until(tester, () => _ready(tester));
        final values = await _values(tester, fixture);
        expect(
          values['answer:guard']['result'] == 'action' ||
              tester.widget<ChoiceChip>(choice).selected,
          isTrue,
        );
        await _runCommand(tester);
        expect((await _values(tester, fixture))['answer:guard'], {
          'result': 'action',
          'value': '',
        });
        await _assertFrozen(tester, fixture);
      },
    );

    if (!submit) {
      testWidgets(
        '${submit ? 'submit' : 'save'} database failure retains exact late input for an explicit retry',
        (tester) async {
          final fixture = await _fixture(tester, scale: 2);
          await _enter(tester, 'notes', _firstNotes);
          fixture.store.db.execute(
            "CREATE TRIGGER synthetic_inflight_failure BEFORE UPDATE ON documents BEGIN SELECT RAISE(ABORT, 'synthetic inflight write failure'); END",
          );
          final before = digest(fixture.store.documentFor(fixture.job)!);
          await _heldCommand(
            tester,
            fixture,
            field: 'notes',
            late: _lateNotes,
            submit: submit,
          );
          expect(digest(fixture.store.documentFor(fixture.job)!), before);
          expect(fixture.store.submissions, isEmpty);
          expect(_controller(tester, 'notes').text, _lateNotes);
          expect(find.textContaining('Unsaved changes —'), findsOneWidget);
          await tester.ensureVisible(find.byKey(const Key('notes')));
          await _capture(
            tester,
            '${submit ? 'submit' : 'save'}-failed-retained-2x',
          );
          fixture.store.db.execute('DROP TRIGGER synthetic_inflight_failure');
          await _runCommand(tester, submit: true);
          expect((await _values(tester, fixture))['notes'], _lateNotes);
          expect(
            fixture.store.submissions.single['values']['notes'],
            _lateNotes,
          );
          await _assertFrozen(tester, fixture);
        },
      );

      testWidgets(
        'leaving the editor after a dirty save cannot hide late unsaved input',
        (tester) async {
          final fixture = await _fixture(tester, routed: true);
          await _enter(tester, 'notes', _firstNotes);
          final finder = find.byKey(const Key('notes'));
          await tester.ensureVisible(finder);
          await tester.showKeyboard(finder);
          await tester.pump();
          final release = Completer<void>();
          addTearDown(() {
            if (!release.isCompleted) release.complete();
          });
          final holding = fixture.store.queue.run(() => release.future);
          final pop = Navigator.of(
            tester.element(find.byType(InspectionPage)),
          ).maybePop();
          await tester.idle();
          if (find.byType(InspectionPage).evaluate().isNotEmpty) {
            expect(tester.widget<TextField>(finder).enabled, isTrue);
            tester.testTextInput.enterText(_lateNotes);
            await tester.idle();
          }
          release.complete();
          await finishNativeWidgetAction(tester, () => holding);
          await pop;
          await _until(
            tester,
            () =>
                find.byType(InspectionPage).evaluate().isEmpty ||
                _ready(tester),
          );
          final stored = (await _values(tester, fixture))['notes'];
          final present = find.byType(InspectionPage).evaluate().isNotEmpty;
          if (!submit) {
            expect(
              stored == _lateNotes ||
                  present && _controller(tester, 'notes').text == _lateNotes,
              isTrue,
              reason: 'PopScope must not leave residual unsaved input behind.',
            );
            if (stored != _lateNotes) {
              expect(present, isTrue);
              expect(find.textContaining('Unsaved changes —'), findsOneWidget);
              await _runCommand(tester);
              expect((await _values(tester, fixture))['notes'], _lateNotes);
              await tester.tap(find.byType(BackButton));
              await _settle(tester);
            }
          }
          expect(find.text('Open synthetic inspection'), findsOneWidget);
          expect(fixture.store.submissions, isEmpty);
        },
      );
    }
  }

  testWidgets(
    'photo intent waits for an explicit retry while late notes remain unsaved',
    (tester) async {
      final fixture = await _fixture(tester, scale: 2);
      final file = File('${fixture.root.path}/synthetic-gallery.png');
      await tester.runAsync(() => file.writeAsBytes(_Fixture.png, flush: true));
      final original = ImagePickerPlatform.instance;
      final picker = _Picker(file.path)..release.complete();
      ImagePickerPlatform.instance = picker;
      addTearDown(() => ImagePickerPlatform.instance = original);
      await _enter(tester, 'notes', _firstNotes);
      final button = find.ancestor(
        of: find.text('Replace inspection photo'),
        matching: find.byWidgetPredicate((widget) => widget is OutlinedButton),
      );
      await _heldCommand(
        tester,
        fixture,
        field: 'notes',
        late: _lateNotes,
        submit: false,
        action: tester.widget<OutlinedButton>(button).onPressed!,
      );
      expect(
        picker.entered.isCompleted,
        isFalse,
        reason: 'Choosing a photo must wait while residual input is unsaved.',
      );
      await _assertRetained(tester, fixture, 'notes', _lateNotes, _lateNotes);
      expect(fixture.store.setting('pendingInspectionPhoto'), isNull);
      await _show(tester, find.byKey(const Key('notes')));
      await _capture(tester, 'photo-intent-late-notes-unsaved-2x');
      final retry = tester.widget<OutlinedButton>(button).onPressed!;
      await tester.runAsync(() async {
        retry();
        for (
          var attempt = 0;
          attempt < 80 && !picker.entered.isCompleted;
          attempt++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await _settle(tester);
      expect(
        picker.entered.isCompleted,
        isTrue,
        reason: 'The explicit retry must reach the platform photo picker.',
      );
      await _until(
        tester,
        () =>
            _ready(tester) &&
            fixture.store.setting('pendingInspectionPhoto') == null,
      );
      expect((await _values(tester, fixture))['notes'], _lateNotes);
      expect(fixture.store.setting('pendingInspectionPhoto'), isNull);
      expect(fixture.store.submissions, isEmpty);
    },
  );

  testWidgets(
    'photo follow-up retains input accepted by the last enabled form while picker waits',
    (tester) async {
      final fixture = await _fixture(tester, scale: 2);
      final file = File('${fixture.root.path}/synthetic-gallery.png');
      await tester.runAsync(() => file.writeAsBytes(_Fixture.png, flush: true));
      final original = ImagePickerPlatform.instance;
      final picker = _Picker(file.path);
      ImagePickerPlatform.instance = picker;
      addTearDown(() {
        if (!picker.release.isCompleted) picker.release.complete();
        ImagePickerPlatform.instance = original;
      });
      await _enter(tester, 'notes', _firstNotes);
      final finder = find.byKey(const Key('notes'));
      await tester.showKeyboard(finder);
      await tester.pump();
      final button = find.ancestor(
        of: find.text('Replace inspection photo'),
        matching: find.byWidgetPredicate((widget) => widget is OutlinedButton),
      );
      final action = tester.widget<OutlinedButton>(button).onPressed!;
      await tester.runAsync(() async {
        action();
        for (
          var attempt = 0;
          attempt < 80 && !picker.entered.isCompleted;
          attempt++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      expect(picker.entered.isCompleted, isTrue);
      expect(tester.widget<TextField>(finder).enabled, isTrue);
      tester.testTextInput.enterText(_lateNotes);
      await tester.idle();
      expect(_controller(tester, 'notes').text, _lateNotes);
      picker.release.complete();
      await _settle(tester);
      await _until(tester, () => _ready(tester));
      await _assertRetained(tester, fixture, 'notes', _lateNotes, _lateNotes);
      expect(fixture.store.setting('pendingInspectionPhoto'), isNull);
      await _runCommand(tester);
      expect((await _values(tester, fixture))['notes'], _lateNotes);
      await _show(tester, find.byKey(const Key('notes')));
      await _capture(tester, 'photo-followup-late-notes-2x');
    },
  );
}
