import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
// Exercise the existing gallery plugin seam with a real, decoded PNG.
// ignore: depend_on_referenced_packages
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:maintenance_local/app.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/local_sync.dart';
import 'package:maintenance_local/model.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';
import 'package:maintenance_local/ui/inspection_page.dart';
import 'package:maintenance_local/ui/review_page.dart';

class _LoopbackBinding extends AutomatedTestWidgetsFlutterBinding {
  // Every successful exchange uses this suite's fresh pinned TLS office.
  @override
  bool get overrideHttpClient => false;
}

class _GalleryPicker extends ImagePickerPlatform {
  XFile? next;
  final sources = <ImageSource>[];

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    sources.add(source);
    final result = next;
    next = null;
    return result;
  }
}

const _boundaryKey = Key('work-progress-render-boundary');
const _jobA = 'Morning generator inspection';
const _jobB = 'Evening trailer inspection';
const _returnReason = 'Record the guard follow-up before resubmitting.';

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  for (var frame = 0; frame < 5; frame++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pump(const Duration(milliseconds: 200));
  expect(
    tester.takeException(),
    isNull,
    reason: 'Ordinary work must render without overflow or framework errors.',
  );
}

Future<void> _until(
  WidgetTester tester,
  bool Function() ready, {
  String reason = 'The real native action must finish before inspection.',
}) async {
  for (var frame = 0; frame < 30; frame++) {
    if (ready()) return;
    await _settle(tester);
  }
  expect(ready(), isTrue, reason: reason);
}

Future<void> _show(WidgetTester tester, Finder finder) async {
  await _until(
    tester,
    () => finder.evaluate().length == 1,
    reason: 'The ordinary screen must expose one intended target: $finder',
  );
  // A captured native projection can add context above the target after it
  // first appears. Recheck its final position with a bounded scroll/frame wait.
  for (var attempt = 0; attempt < 30; attempt++) {
    if (finder.evaluate().length == 1) {
      await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
    }
    await _settle(tester);
    if (finder.hitTestable().evaluate().length == 1) return;
  }
  await _capture(tester, 'unreachable-target');
  expect(
    finder.hitTestable(),
    findsOneWidget,
    reason: 'This ordinary action must be reachable at the selected text size.',
  );
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _show(tester, finder);
  await tester.runAsync(() async {
    await tester.tap(finder);
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });
  await _settle(tester);
}

Future<void> _enter(WidgetTester tester, Finder finder, String text) async {
  await _show(tester, finder);
  await tester.enterText(finder, text);
  await _settle(tester);
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Future<void> _choose(
  WidgetTester tester,
  String label,
  String choice, {
  bool last = false,
}) async {
  final field = find.widgetWithText(DropdownButtonFormField<String>, label);
  await _tap(tester, last ? field.last : field);
  await _tap(tester, find.text(choice).last);
}

Finder _jobCard(String id) => find.byKey(ValueKey('inspection:$id'));
Finder _record(String id) => find.byKey(ValueKey('submitted-version:$id'));
Finder _in(Finder parent, Finder child) =>
    find.descendant(of: parent, matching: child);
Finder _approve() => find.widgetWithText(FilledButton, 'Approve this version');

Future<void> _openJob(WidgetTester tester, String id, {bool office = false}) =>
    _tap(
      tester,
      _in(
        _jobCard(id),
        find.widgetWithText(
          FilledButton,
          office ? 'Open inspection' : 'Continue inspection',
        ),
      ),
    );

Future<void> _mount(WidgetTester tester, LabStore store, double scale) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await _settle(tester);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _boundaryKey,
      child: LabApp(store: store, textScale: scale, officePort: 0),
    ),
  );
  await _settle(tester);
}

Future<void> _capture(WidgetTester tester, String name) async {
  final output = Platform.environment['VORTICE_RENDER_OUTPUT'];
  if (output == null || output.isEmpty) return;
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_boundaryKey),
  );
  await tester.runAsync(() async {
    final raster = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await raster.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$output/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
    } finally {
      raster.dispose();
    }
  });
}

Future<Uint8List> _syntheticPng() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(const Color(0xffe4ece6), BlendMode.src);
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTWH(40, 50, 400, 220),
      const Radius.circular(20),
    ),
    Paint()..color = const Color(0xff103d3c),
  );
  final caption = TextPainter(
    text: const TextSpan(
      text: 'SYNTHETIC INSPECTION PHOTO\nGenerator guard and gauge',
      style: TextStyle(fontFamily: 'Roboto', fontSize: 24, color: Colors.white),
    ),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
  )..layout(maxWidth: 350);
  caption.paint(canvas, const Offset(65, 110));
  caption.dispose();
  final picture = recorder.endRecording();
  final raster = await picture.toImage(480, 320);
  try {
    final bytes = await raster.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  } finally {
    raster.dispose();
    picture.dispose();
  }
}

Future<void> _visiblePhoto(WidgetTester tester) async {
  final image = find.byType(Image);
  await _show(tester, image);
  final raw = _in(image, find.byType(RawImage));
  await _until(
    tester,
    () =>
        raw.evaluate().length == 1 &&
        tester.widget<RawImage>(raw).image != null,
    reason: 'The actual saved PNG must finish engine decoding.',
  );
}

Future<void> _reviewActionsVisible(WidgetTester tester) async {
  // A real upward swipe exposes the review footer after evidence and notices
  // establish their final height, including both actions at large text.
  expect(
    _in(find.byType(ReviewPage), find.byType(SingleChildScrollView)),
    findsOneWidget,
  );
  final size = tester.view.physicalSize / tester.view.devicePixelRatio;
  await tester.dragFrom(
    Offset(size.width / 2, size.height - 100),
    const Offset(0, -500),
  );
  await _settle(tester);
  final actions = [
    _approve(),
    find.widgetWithText(OutlinedButton, 'Return with a reason'),
  ];
  for (final action in actions) {
    expect(action.hitTestable(), findsOneWidget);
    final rect = tester.getRect(action);
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(size.height));
  }
}

Future<void> _createOrdinaryWork(WidgetTester tester, LabStore office) async {
  expect(find.text('Start with your company'), findsOneWidget);
  await _tap(tester, find.text('Create company'));
  await _enter(
    tester,
    find.byKey(const Key('preparation-name')),
    'Synthetic Progress Construction',
  );
  await _enter(tester, _field('Coordinator name'), 'Sam Coordinator');
  await _tap(tester, find.text('Create company'));

  for (final equipment in [
    ('Synthetic yard generator', 'Operating hours'),
    ('Synthetic service trailer', 'No meter'),
  ]) {
    await _tap(tester, find.text('Add equipment'));
    await _enter(
      tester,
      find.byKey(const Key('preparation-name')),
      equipment.$1,
    );
    await _choose(tester, 'Equipment meter', equipment.$2);
    await _tap(tester, find.text('Save equipment'));
  }

  await _tap(tester, find.text('Author checklist'));
  await _enter(
    tester,
    find.byKey(const Key('preparation-name')),
    'Guard and pressure inspection',
  );
  await _enter(
    tester,
    _field('What should the mechanic inspect?'),
    'Inspect guards',
  );
  await _tap(tester, find.text('Add step'));
  await _enter(
    tester,
    _field('What should the mechanic inspect?').last,
    'Record hydraulic pressure',
  );
  await _choose(tester, 'Response', 'Numeric reading', last: true);
  await _enter(tester, _field('Reading unit (for example psi or °C)'), 'psi');
  await _enter(tester, _field('Expected minimum (optional)'), '10');
  await _enter(tester, _field('Expected maximum (optional)'), '30');
  await _tap(
    tester,
    find.widgetWithText(SwitchListTile, 'Allow not applicable').last,
  );
  await _tap(tester, find.text('Add step'));
  await _enter(
    tester,
    _field('What should the mechanic inspect?').last,
    'Optional equipment comment',
  );
  await _choose(tester, 'Response', 'Written response', last: true);
  await _tap(
    tester,
    find.widgetWithText(SwitchListTile, 'Required response').last,
  );
  await _tap(tester, find.text('Publish checklist'));
  expect(office.templates.single['items'], hasLength(3));

  for (final job in [
    (_jobA, 'Synthetic yard generator'),
    (_jobB, 'Synthetic service trailer'),
  ]) {
    await _tap(tester, find.text('Prepare inspection'));
    await _choose(tester, 'Equipment', job.$2);
    await _enter(tester, find.byKey(const Key('preparation-name')), job.$1);
    await _tap(tester, find.text('Prepare inspection'));
  }
  expect(office.catalog?['coordinatorName'], 'Sam Coordinator');
  expect(office.equipment, hasLength(2));
  expect(office.jobs, hasLength(2));
}

Future<void> _sync(WidgetTester tester, LabStore phone, LabStore office) async {
  await _tap(tester, find.text('Sync now'));
  await _until(
    tester,
    () =>
        phone.jobs.every((job) {
          final id = job['id'] as String;
          return digest(phone.documentFor(id)!) ==
              digest(office.documentFor(id)!);
        }) &&
        phone.submissions.every((s) => s['_state'] == 'received'),
    reason: 'Pinned TLS must deliver every real saved job and queued command.',
  );
  await _until(
    tester,
    () => find
        .text('Saved on the computer. Photos verified.')
        .evaluate()
        .isNotEmpty,
    reason:
        'A successful exchange must establish the real complete-photo proof.',
  );
}

void main() {
  _LoopbackBinding();
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
      'ordinary current draft, exact review and correction render at ${scale}x',
      (tester) async {
        tester.view.physicalSize = const Size(412, 915);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        // Suspend the synthetic app's automatic sender so each offline and
        // queued phase stays observable. Explicit Sync now uses real transport.
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        final originalPicker = ImagePickerPlatform.instance;
        final picker = _GalleryPicker();
        ImagePickerPlatform.instance = picker;
        late Directory root;
        late LabStore office, phone;
        OfficeServer? server;
        var port = 0;
        final releaseRead = Completer<void>();
        addTearDown(() async {
          if (!releaseRead.isCompleted) releaseRead.complete();
          ImagePickerPlatform.instance = originalPicker;
          await tester.pumpWidget(const SizedBox.shrink());
          await _settle(tester);
          // Disposing a route can leave a captured native read in flight. Pump
          // its fake-zone continuations before awaiting real SQLite shutdown.
          var phoneIdle = false, officeIdle = false;
          unawaited(phone.queue.idle.then((_) => phoneIdle = true));
          unawaited(office.queue.idle.then((_) => officeIdle = true));
          await _until(tester, () => phoneIdle && officeIdle);
          await tester.runAsync(() async {
            await server?.close().timeout(const Duration(seconds: 10));
            await phone.close().timeout(const Duration(seconds: 10));
            await office.close().timeout(const Duration(seconds: 10));
            await root.delete(recursive: true);
          });
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        });
        await tester.runAsync(() async {
          root = await Directory.systemTemp.createTemp('lf002-render-');
          office = await LabStore.open(
            Directory('${root.path}/office'),
            office: true,
            maintenanceOnly: true,
            now: () => DateTime.utc(2026, 9, 30, 8),
          );
          phone = await LabStore.open(
            Directory('${root.path}/phone'),
            office: false,
            maintenanceOnly: true,
            now: () => DateTime.utc(2026, 9, 30, 9),
          );
        });
        final suffix = scale.toInt();
        await _mount(tester, office, scale);
        await _createOrdinaryWork(tester, office);
        final a = office.jobs.first['id'] as String;
        final b = office.jobs.last['id'] as String;
        final frozenA = canonical(office.jobContextFor(a));
        final frozenB = canonical(office.jobContextFor(b));
        await _show(tester, _in(_jobCard(a), find.textContaining('Prepared')));
        await _capture(tester, 'progress-office-prepared-${suffix}x');

        late Uint8List photo;
        late File gallery;
        await tester.runAsync(() async {
          server = await OfficeServer.start(
            office,
            port: 0,
            address: InternetAddress.loopbackIPv4,
          );
          port = server!.port;
          final enrollment = PhoneSync(phone);
          await enrollment.enroll(server!.invitation('127.0.0.1'));
          server!.authority.confirm(phone.device);
          await enrollment.sync();
          photo = await _syntheticPng();
          gallery = File('${root.path}/synthetic-gallery.png');
          await gallery.writeAsBytes(photo, flush: true);
        });
        var bBefore = digest(phone.documentFor(b)!);
        final items =
            phone.jobContextFor(a)['checklistSnapshot']['items'] as List;
        final pressure = items[1]['id'] as String;
        await _mount(tester, phone, scale);
        await _openJob(tester, a);
        await _tap(
          tester,
          _in(
            find.widgetWithText(Card, 'Inspect guards'),
            find.text('Needs action'),
          ),
        );
        await _tap(tester, find.text('Save work'));
        await _tap(tester, find.byTooltip('Back'));
        await _show(
          tester,
          _in(_jobCard(a), find.textContaining('Incomplete')),
        );
        expect(
          _in(_jobCard(a), find.text('Required steps: 1 of 2 recorded')),
          findsOneWidget,
        );
        await _capture(tester, 'phone-partial-draft-${suffix}x');
        await _openJob(tester, a);
        await _enter(tester, find.byKey(ValueKey('answer:$pressure')), '35');
        await _enter(tester, find.byKey(const Key('meter')), '0');
        await _enter(
          tester,
          find.byKey(const Key('notes')),
          'Guard loose; inspect before use. Pressure is 35 psi.',
        );
        picker.next = XFile(gallery.path);
        await _tap(tester, find.text('Choose a saved photo'));
        expect(picker.sources, [ImageSource.gallery]);
        await _visiblePhoto(tester);
        await _capture(tester, 'phone-real-gallery-${suffix}x');
        await _tap(tester, find.text('Submit for review'));
        expect(phone.submissions, hasLength(1));
        final approvedVersion = Map<String, dynamic>.from(
          phone.submissions.single,
        );
        expect(approvedVersion['values']['meter'], 0);
        expect(approvedVersion['values']['answer:$pressure'], {
          'result': 'action',
          'value': '35',
        });
        expect(approvedVersion['values']['answer:${items[2]['id']}'], isNull);
        await _tap(tester, find.byTooltip('Back'));
        await _sync(tester, phone, office);
        await tester.runAsync(() async {
          expect(await office.evidence.complete(digest(photo)), isTrue);
          expect(
            await office.evidence.file(digest(photo)).readAsBytes(),
            photo,
          );
        });
        await _mount(tester, office, scale);
        await _tap(tester, _record(approvedVersion['id'] as String));
        await _until(
          tester,
          () => tester.widget<FilledButton>(_approve()).onPressed != null,
        );
        await _show(tester, _approve());
        await _capture(tester, 'office-exact-approval-${suffix}x');
        await _tap(tester, _approve());
        await _until(tester, () => office.receipts.length == 1);
        final approval = canonical(office.receipts.single);
        await _show(tester, find.text('Reviewed by Sam Coordinator'));
        await _capture(tester, 'office-approved-history-${suffix}x');

        await _mount(tester, phone, scale);
        await _sync(tester, phone, office);
        expect(canonical(phone.receipts.single), approval);
        await _openJob(tester, a);
        await _tap(tester, find.text('Submit for review'));
        expect(phone.submissions, hasLength(1));
        expect(
          find.textContaining('is approved. Its saved decision is unchanged'),
          findsOneWidget,
        );
        await _show(
          tester,
          find.textContaining('is approved. Its saved decision is unchanged'),
        );
        await _capture(tester, 'phone-unchanged-approved-command-${suffix}x');
        await _tap(tester, find.byTooltip('Back'));
        await _openJob(tester, b);
        expect(
          tester.widget<InspectionPage>(find.byType(InspectionPage)).jobId,
          b,
        );
        expect(find.byKey(const Key('meter')), findsNothing);
        await _show(
          tester,
          find.text('This equipment has no meter reading to record.'),
        );
        await _capture(tester, 'phone-other-job-no-meter-${suffix}x');
        await _tap(
          tester,
          _in(
            find.widgetWithText(Card, 'Record hydraulic pressure'),
            find.text('Not applicable'),
          ),
        );
        await _tap(tester, find.text('Save work'));
        await _tap(tester, find.byTooltip('Back'));
        bBefore = digest(phone.documentFor(b)!);
        await tester.runAsync(() async {
          final bValues = valuesOf(await phone.fields(jobId: b));
          expect(bValues['meter'], isNull);
          expect(bValues['answer:$pressure'], {'result': 'na', 'value': ''});
        });
        expect(phone.activeJobId, b);
        await tester.runAsync(() async {
          await server!.close();
          server = null;
        });
        await _tap(tester, find.text('Sync now'));
        expect(
          find.textContaining('Cannot reach the computer.'),
          findsOneWidget,
        );
        await _openJob(tester, a);
        await _enter(
          tester,
          find.byKey(const Key('notes')),
          'Offline follow-up: the guard still needs tightening.',
        );
        await _tap(tester, find.text('Save work'));
        await _tap(tester, find.byTooltip('Back'));
        await _show(tester, _in(_jobCard(a), find.textContaining('Ready')));
        expect(
          _in(_jobCard(a), find.text('Required steps: 2 of 2 recorded')),
          findsOneWidget,
        );
        expect(
          _in(_jobCard(a), find.text('Approved inspection')),
          findsNothing,
        );
        await _capture(tester, 'phone-offline-draft-after-approval-${suffix}x');
        await _show(tester, _record(approvedVersion['id'] as String));
        expect(
          _in(
            _record(approvedVersion['id'] as String),
            find.text('Approved inspection'),
          ),
          findsOneWidget,
        );
        await _capture(tester, 'phone-immutable-earlier-approval-${suffix}x');
        expect(canonical(phone.receipts.single), approval);
        expect(phone.submissions, hasLength(1));
        expect(
          digest(phone.documentFor(a)!),
          isNot(approvedVersion['documentHash']),
        );
        expect(digest(phone.documentFor(b)!), bBefore);
        await _openJob(tester, a);
        await _enter(
          tester,
          find.byKey(const Key('notes')),
          approvedVersion['values']['notes'] as String,
        );
        await _tap(tester, find.text('Save work'));
        await _tap(tester, find.byTooltip('Back'));
        await _show(tester, _in(_jobCard(a), find.textContaining('Ready')));
        expect(
          digest(phone.documentFor(a)!),
          isNot(approvedVersion['documentHash']),
        );
        expect(
          _in(_jobCard(a), find.textContaining('Current submitted record')),
          findsNothing,
        );
        await _capture(
          tester,
          'phone-reverted-values-current-draft-${suffix}x',
        );
        await _openJob(tester, a);
        await _enter(
          tester,
          find.byKey(const Key('notes')),
          'Offline follow-up: the guard still needs tightening.',
        );
        await _tap(tester, find.text('Submit for review'));
        expect(phone.submissions, hasLength(2));
        final returnedVersion = Map<String, dynamic>.from(
          phone.submissions.last,
        );
        expect(returnedVersion['predecessorId'], approvedVersion['id']);
        expect(returnedVersion['_state'], 'queued');
        await _tap(tester, find.byTooltip('Back'));
        await _show(
          tester,
          _in(
            _record(returnedVersion['id'] as String),
            find.text('Waiting to send'),
          ),
        );
        await _capture(tester, 'phone-new-version-queued-${suffix}x');
        await tester.pumpWidget(const SizedBox.shrink());
        await _settle(tester);
        await tester.runAsync(() async {
          await phone.close();
          phone = await LabStore.open(
            Directory('${root.path}/phone'),
            office: false,
            maintenanceOnly: true,
            now: () => DateTime.utc(2026, 9, 30, 10),
          );
        });
        await _mount(tester, phone, scale);
        expect(phone.submissions, hasLength(2));
        expect(phone.submissions.last['id'], returnedVersion['id']);
        expect(phone.submissions.last['_state'], 'queued');
        expect(canonical(phone.receipts.single), approval);
        expect(digest(phone.documentFor(b)!), bBefore);
        await _show(
          tester,
          _in(
            _record(returnedVersion['id'] as String),
            find.text('Waiting to send'),
          ),
        );
        await _capture(tester, 'phone-queued-restart-${suffix}x');
        await tester.runAsync(() async {
          server = await OfficeServer.start(
            office,
            port: port,
            address: InternetAddress.loopbackIPv4,
          );
        });
        await _sync(tester, phone, office);
        await _mount(tester, office, scale);
        await _show(tester, find.textContaining('Awaiting review (1)'));
        await _capture(tester, 'office-pending-and-decided-${suffix}x');
        await _tap(tester, _record(returnedVersion['id'] as String));
        expect(
          tester.widget<ReviewPage>(find.byType(ReviewPage)).submission['id'],
          returnedVersion['id'],
        );
        await _tap(tester, find.text('Return with a reason'));
        await _enter(tester, _field('Reason for return'), _returnReason);
        await _capture(tester, 'office-return-reason-${suffix}x');
        await _tap(tester, find.text('Continue'));
        await _until(tester, () => office.receipts.length == 2);
        await _show(tester, find.text('Returned: $_returnReason'));
        await _capture(tester, 'office-exact-return-${suffix}x');

        await _mount(tester, phone, scale);
        await _sync(tester, phone, office);
        await _openJob(tester, b);
        await _tap(tester, find.byTooltip('Back'));
        expect(phone.activeJobId, b);
        await _tap(tester, _record(returnedVersion['id'] as String));
        await _tap(tester, find.text('Open current inspection'));
        expect(
          tester.widget<InspectionPage>(find.byType(InspectionPage)).jobId,
          a,
        );
        expect(phone.activeJobId, a);
        await _show(
          tester,
          _in(
            find.byType(InspectionPage),
            find.text('Returned: $_returnReason'),
          ),
        );
        await _capture(tester, 'phone-return-routes-correct-job-${suffix}x');
        await _tap(tester, find.text('Submit for review'));
        expect(phone.submissions, hasLength(2));
        expect(
          find.textContaining('was returned: $_returnReason'),
          findsOneWidget,
        );
        await _enter(
          tester,
          find.byKey(const Key('notes')),
          'Follow-up recorded: guard finding retained for office review.',
        );
        await _tap(tester, find.text('Submit for review'));
        expect(phone.submissions, hasLength(3));
        final correction = Map<String, dynamic>.from(phone.submissions.last);
        expect(correction['jobId'], a);
        expect(correction['predecessorId'], returnedVersion['id']);
        expect(
          correction['documentHash'],
          isNot(returnedVersion['documentHash']),
        );
        expect(canonical(correction['context']), frozenA);
        expect(digest(phone.documentFor(b)!), bBefore);
        await _tap(tester, find.byTooltip('Back'));
        // Returning from the editor reveals the pinned immutable review route.
        if (find.byType(ReviewPage).evaluate().isNotEmpty) {
          await _tap(tester, find.byTooltip('Back'));
        }
        await _sync(tester, phone, office);
        await _mount(tester, office, scale);
        await _show(tester, find.textContaining('Awaiting review (1)'));
        await _capture(tester, 'office-correction-pending-${suffix}x');
        await _show(tester, find.textContaining('Reviewed history (2)'));
        await _capture(tester, 'office-correction-decided-history-${suffix}x');
        expect(_record(approvedVersion['id'] as String), findsOneWidget);
        expect(_record(returnedVersion['id'] as String), findsOneWidget);
        expect(_record(correction['id'] as String), findsOneWidget);
        expect(canonical(office.receipts.first), approval);
        expect(canonical(office.jobContextFor(a)), frozenA);
        expect(canonical(office.jobContextFor(b)), frozenB);
        expect(
          approvedVersion['values']['notes'],
          'Guard loose; inspect before use. Pressure is 35 psi.',
        );

        // A complete matching .part is still not published evidence. Rendering
        // and repeated progress reads must neither promote it nor enable approval.
        final photoHash = digest(photo);
        await tester.runAsync(() async {
          await office.evidence
              .file(photoHash)
              .rename('${office.evidence.file(photoHash).path}.part');
        });
        await _tap(tester, _record(correction['id'] as String));
        await _until(
          tester,
          () => find
              .text('Waiting for the complete photo.')
              .evaluate()
              .isNotEmpty,
        );
        expect(tester.widget<FilledButton>(_approve()).onPressed, isNull);
        await _show(tester, _approve());
        await _reviewActionsVisible(tester);
        await _capture(
          tester,
          'office-complete-partial-photo-guard-${suffix}x',
        );
        await tester.runAsync(() async {
          expect(await office.evidence.complete(photoHash), isFalse);
          expect(
            await File('${office.evidence.file(photoHash).path}.part').exists(),
            isTrue,
          );
          await File(
            '${office.evidence.file(photoHash).path}.part',
          ).rename(office.evidence.file(photoHash).path);
        });
        await _tap(tester, find.byTooltip('Back'));

        // Hold the actual serial queue: pending reads must keep approval disabled.
        await _show(tester, _record(correction['id'] as String));
        final readStarted = Completer<void>();
        var readFinished = false;
        final heldRead = office.queue.run(() async {
          readStarted.complete();
          await releaseRead.future;
        });
        unawaited(heldRead.then((_) => readFinished = true));
        // Queue continuations created by widgets live in the fake frame zone.
        // Pump them instead of blocking runAsync while waiting for that zone.
        await _until(tester, () => readStarted.isCompleted);
        await _tap(tester, _record(correction['id'] as String));
        expect(tester.widget<FilledButton>(_approve()).onPressed, isNull);
        await _visiblePhoto(tester);
        await _show(tester, _approve());
        await _reviewActionsVisible(tester);
        await _capture(tester, 'office-pending-read-guard-${suffix}x');
        releaseRead.complete();
        await _until(tester, () => readFinished);
        await _until(
          tester,
          () => tester.widget<FilledButton>(_approve()).onPressed != null,
        );

        // Real later document bytes invalidate this still-open review. A
        // lifecycle refresh drives the same update signal as ordinary sync.
        await tester.runAsync(() async {
          await office.update({
            'notes': 'Later work after this exact submission.',
          }, jobId: a);
        });
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await _until(
          tester,
          () => find
              .text(
                'Work has changed. Return this version and request a new submission.',
              )
              .evaluate()
              .isNotEmpty,
        );
        expect(tester.widget<FilledButton>(_approve()).onPressed, isNull);
        await _visiblePhoto(tester);
        await _show(tester, _approve());
        await _reviewActionsVisible(tester);
        await _capture(tester, 'office-stale-current-review-guard-${suffix}x');
        expect(office.receipts, hasLength(2));
        expect(canonical(office.receipts.first), approval);
      },
      timeout: const Timeout(Duration(minutes: 6)),
    );
  }
}
