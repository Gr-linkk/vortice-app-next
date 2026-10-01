import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
// The picker interface is the existing plugin's synthetic test seam.
// ignore: depend_on_referenced_packages
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:maintenance_local/app.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/model.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';
import 'package:maintenance_local/ui/review_page.dart';
import 'support/native_widget_cleanup.dart';

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

const _boundaryKey = Key('maintenance-render-boundary');

Future<void> _settle(WidgetTester tester) async {
  // Native Rust, SQLite, file decoding and the synthetic office socket run in
  // real time. Bounded frame waits also allow routes and floating labels to
  // settle without waiting forever on an active native-loading spinner.
  await tester.pump(const Duration(milliseconds: 400));
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pump(const Duration(milliseconds: 200));
  expect(
    tester.takeException(),
    isNull,
    reason:
        'The actual screen must render without framework errors or overflow.',
  );
}

Future<void> _show(WidgetTester tester, Finder target) async {
  expect(target, findsOneWidget);
  await tester.ensureVisible(target);
  await tester.pump(const Duration(milliseconds: 250));
  expect(
    target.hitTestable(),
    findsOneWidget,
    reason: 'The ordinary action must be reachable at this text size.',
  );
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await _show(tester, target);
  await tester.runAsync(() async {
    await tester.tap(target);
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });
  await _settle(tester);
}

Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    if (done()) return;
    await _settle(tester);
  }
  expect(
    done(),
    isTrue,
    reason: 'The native UI action must finish before its record is inspected.',
  );
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Future<void> _enter(WidgetTester tester, Finder target, String value) async {
  await _show(tester, target);
  await tester.enterText(target, value);
  await _settle(tester);
}

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

Future<void> _capture(WidgetTester tester, String name) async {
  final output = Platform.environment['VORTICE_RENDER_OUTPUT'];
  if (output == null || output.isEmpty) return;
  await tester.pump();
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
}

Future<void> _visiblePhoto(WidgetTester tester) async {
  final image = find.byType(Image);
  await _show(tester, image);
  // FileImage decoding has an asynchronous engine callback. Pump while it
  // finishes rather than rasterizing its reserved, still blank layout space.
  await _until(
    tester,
    () =>
        tester
            .widget<RawImage>(
              find.descendant(of: image, matching: find.byType(RawImage)),
            )
            .image !=
        null,
  );
  final raw = tester.widget<RawImage>(
    find.descendant(of: image, matching: find.byType(RawImage)),
  );
  expect(raw.image, isNotNull, reason: 'The saved gallery photo must render.');
}

Future<Uint8List> _syntheticPng() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(const Color(0xffe4ece6), BlendMode.src);
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTWH(50, 70, 380, 180),
      const Radius.circular(20),
    ),
    Paint()..color = const Color(0xff103d3c),
  );
  final title = TextPainter(
    text: const TextSpan(
      text: 'SYNTHETIC INSPECTION PHOTO\nGuard and gauge test fixture',
      style: TextStyle(fontFamily: 'Roboto', fontSize: 22, color: Colors.white),
    ),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
  )..layout(maxWidth: 350);
  title.paint(canvas, const Offset(65, 125));
  title.dispose();
  final picture = recorder.endRecording();
  final image = await picture.toImage(480, 320);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

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
    final loader = FontLoader('Roboto')
      ..addFont(
        File(
          '../../assets/fonts/Roboto-Regular.ttf',
        ).readAsBytes().then(ByteData.sublistView),
      );
    await loader.load();
    final bold = FontLoader('Roboto')
      ..addFont(
        File(
          '../../assets/fonts/Roboto-Bold.ttf',
        ).readAsBytes().then(ByteData.sublistView),
      );
    await bold.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'ordinary office and mechanic workflow renders at ${scale}x text',
      (tester) async {
        tester.view.physicalSize = const Size(412, 915);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final originalPicker = ImagePickerPlatform.instance;
        final picker = _GalleryPicker();
        ImagePickerPlatform.instance = picker;
        final stores = <LabStore>[];
        late Directory root;
        await tester.runAsync(() async {
          root = await Directory.systemTemp.createTemp('maintenance-render-');
        });
        addTearDown(() async {
          ImagePickerPlatform.instance = originalPicker;
          await tester.pumpWidget(const SizedBox.shrink());
          await finishNativeWidgetCleanup(tester, () async {
            for (final store in stores) {
              await store.close();
            }
            await root.delete(recursive: true);
          });
        });
        late LabStore office;
        await tester.runAsync(() async {
          office = await LabStore.open(
            Directory('${root.path}/office'),
            office: true,
            now: () => DateTime.utc(2026, 9, 30, 8),
          );
          stores.add(office);
        });
        final suffix = scale.toInt();
        await _mount(tester, office, scale);
        expect(find.text('Start with your company'), findsOneWidget);
        await _capture(tester, 'office-empty-${suffix}x');
        await _tap(tester, find.text('Create company'));
        await _enter(
          tester,
          find.byKey(const Key('preparation-name')),
          'Synthetic North Construction',
        );
        await _enter(tester, _field('Coordinator name'), 'Sam Coordinator');
        await _capture(tester, 'company-form-${suffix}x');
        await _tap(tester, find.text('Create company'));
        expect(office.catalog?['coordinatorName'], 'Sam Coordinator');

        await _tap(tester, find.text('Add equipment'));
        await _enter(
          tester,
          find.byKey(const Key('preparation-name')),
          'Synthetic tracked excavator',
        );
        await _enter(
          tester,
          _field('Serial or equipment ID (optional)'),
          'SYNTHETIC-EX24',
        );
        await _choose(tester, 'Equipment meter', 'Kilometres');
        await _capture(tester, 'equipment-form-${suffix}x');
        await _tap(tester, find.text('Save equipment'));
        expect(office.equipment.single['meterUnit'], 'km');

        await _tap(tester, find.text('Author checklist'));
        await _enter(
          tester,
          find.byKey(const Key('preparation-name')),
          'Morning equipment inspection',
        );
        await _enter(
          tester,
          _field('What should the mechanic inspect?'),
          'Inspect guards and visible leaks',
        );
        await _tap(tester, find.text('Add step'));
        await _enter(
          tester,
          _field('What should the mechanic inspect?').last,
          'Record hydraulic pressure',
        );
        await _choose(tester, 'Response', 'Numeric reading', last: true);
        await _enter(
          tester,
          _field('Reading unit (for example psi or °C)'),
          'psi',
        );
        await _enter(tester, _field('Expected minimum (optional)'), '10');
        await _enter(tester, _field('Expected maximum (optional)'), '30');
        await _capture(tester, 'checklist-numeric-${suffix}x');
        await _tap(tester, find.text('Add step'));
        await _enter(
          tester,
          _field('What should the mechanic inspect?').last,
          'Describe equipment condition',
        );
        await _choose(tester, 'Response', 'Written response', last: true);
        await _show(tester, find.text('Publish checklist'));
        await _capture(tester, 'checklist-publish-${suffix}x');
        await _tap(tester, find.text('Publish checklist'));
        expect(
          (office.templates.single['items'] as List).map(
            (i) => i['input_type'],
          ),
          ['check', 'number', 'text'],
        );

        await _tap(tester, find.text('Prepare inspection'));
        await _enter(
          tester,
          find.byKey(const Key('preparation-name')),
          'Start-of-shift inspection',
        );
        await _capture(tester, 'prepare-form-${suffix}x');
        await _tap(tester, find.text('Prepare inspection'));
        expect(office.jobs, hasLength(1));
        final jobId = office.jobs.single['id'] as String;
        final frozen = canonical(office.jobContextFor(jobId));
        await _show(tester, find.text('Open inspection'));
        await _capture(tester, 'office-prepared-${suffix}x');

        late LabStore phone;
        late Uint8List photo;
        late File photoFile;
        await tester.runAsync(() async {
          phone = await LabStore.open(
            Directory('${root.path}/phone'),
            office: false,
            now: () => DateTime.utc(2026, 9, 30, 8),
          );
          stores.add(phone);
          await phone.importOfficeBundle(await office.publicBundle());
          photo = await _syntheticPng();
          photoFile = File('${root.path}/synthetic-gallery.png');
          await photoFile.writeAsBytes(photo, flush: true);
        });
        await _mount(tester, phone, scale);
        await _tap(tester, find.text('Continue inspection'));
        final items =
            phone.jobContextFor(jobId)['checklistSnapshot']['items'] as List;
        await _tap(
          tester,
          find.descendant(
            of: find.widgetWithText(Card, 'Inspect guards and visible leaks'),
            matching: find.text('Needs action'),
          ),
        );
        await _enter(
          tester,
          find.byKey(ValueKey('answer:${items[1]['id']}')),
          '35',
        );
        await _enter(
          tester,
          find.byKey(ValueKey('answer:${items[2]['id']}')),
          'Checked before use; guard requires tightening.',
        );
        await _enter(tester, find.byKey(const Key('meter')), '0');
        await _enter(
          tester,
          find.byKey(const Key('notes')),
          'Guard loose; pressure 35 psi. Isolate equipment for follow-up.',
        );
        await _capture(tester, 'phone-readings-${suffix}x');
        picker.next = XFile(photoFile.path);
        await _tap(tester, find.text('Choose a saved photo'));
        expect(picker.sources, [ImageSource.gallery]);
        late Json recorded;
        await tester.runAsync(() async {
          recorded = valuesOf(await phone.fields(jobId: jobId));
        });
        expect(
          recorded['photo'],
          isA<String>(),
          reason:
              'Gallery selection must finish attaching before the draft is inspected.',
        );
        final photoHash = recorded['photo'] as String;
        expect(photoHash, digest(photo));
        await _visiblePhoto(tester);
        await _capture(tester, 'phone-photo-${suffix}x');

        await _enter(
          tester,
          find.byKey(const Key('notes')),
          'Guard loose; saved before cancelled picker.',
        );
        await _tap(tester, find.text('Replace inspection photo'));
        await tester.runAsync(() async {
          recorded = valuesOf(await phone.fields(jobId: jobId));
        });
        expect(recorded['photo'], photoHash);
        expect(
          recorded['notes'],
          'Guard loose; saved before cancelled picker.',
        );
        expect(picker.sources, [ImageSource.gallery, ImageSource.gallery]);
        await _show(
          tester,
          find.text(
            'No photo selected. Your inspection notes and readings are saved.',
          ),
        );
        await _capture(tester, 'phone-picker-cancel-${suffix}x');
        await _tap(tester, find.text('Save work'));
        await _tap(tester, find.text('Submit for review'));
        expect(phone.submissions, hasLength(1));
        final first = phone.submissions.single;
        expect(first['_state'], 'queued');
        expect(first['values']['meter'], 0);
        expect(first['values']['unit'], 'km');
        expect(canonical(first['context']), frozen);
        await _tap(tester, find.byTooltip('Back'));
        await _until(
          tester,
          () => find.text('Waiting to send').evaluate().isNotEmpty,
        );
        await _show(tester, find.text('Waiting to send').last);
        await _capture(tester, 'phone-submitted-${suffix}x');

        Future<void> deliver(Json submission) async {
          await finishNativeWidgetAction(tester, () async {
            office.saveDocument(phone.documentFor(jobId)!, jobId: jobId);
            await office.evidence.add(photo);
            // Match the transport envelope: local queue state is not part of
            // the immutable submission payload or its receipt hash.
            final payload = Map<String, dynamic>.from(submission)
              ..remove('_state');
            await office.acceptSubmission(payload, phone.device);
          });
        }

        await deliver(first);
        await _mount(tester, office, scale);
        await _until(
          tester,
          () => find.text('Awaiting review').evaluate().isNotEmpty,
        );
        await _tap(tester, find.text('Awaiting review').last);
        expect(
          find.descendant(
            of: find.byType(ReviewPage),
            matching: find.text('Start-of-shift inspection'),
          ),
          findsOneWidget,
        );
        expect(
          find.text('Morning equipment inspection · checklist v1'),
          findsOneWidget,
        );
        expect(find.text('Needs action · 35 psi'), findsOneWidget);
        await _capture(tester, 'office-review-${suffix}x');
        await _tap(tester, find.text('Return with a reason'));
        await _enter(
          tester,
          _field('Reason for return'),
          'Record the follow-up inspection notes.',
        );
        await _capture(tester, 'office-return-dialog-${suffix}x');
        await _tap(tester, find.text('Continue'));
        await _until(tester, () => office.receipts.isNotEmpty);
        expect(office.receipts.single['decision'], 'returned');
        await _show(
          tester,
          find.text('Returned: Record the follow-up inspection notes.'),
        );
        await _capture(tester, 'office-returned-${suffix}x');

        await finishNativeWidgetAction(tester, () async {
          await phone.importOfficeBundle(await office.publicBundle());
        });
        await _mount(tester, phone, scale);
        await _tap(tester, find.text('Continue inspection'));
        await _enter(
          tester,
          find.byKey(const Key('notes')),
          'Follow-up recorded. Guard and pressure findings remain visible for coordinator review.',
        );
        await _tap(tester, find.text('Submit for review'));
        await _until(tester, () => phone.submissions.length == 2);
        expect(phone.submissions, hasLength(2));
        final second = phone.submissions.last;
        expect(second['predecessorId'], first['id']);
        expect(canonical(second['context']), frozen);
        await deliver(second);
        await _mount(tester, office, scale);
        await _until(
          tester,
          () => find.text('Awaiting review').evaluate().isNotEmpty,
        );
        await _tap(tester, find.text('Awaiting review').last);
        await _until(
          tester,
          () =>
              tester
                  .widget<FilledButton>(
                    find.widgetWithText(FilledButton, 'Approve this version'),
                  )
                  .onPressed !=
              null,
        );
        await _show(tester, find.text('Approve this version'));
        await _capture(tester, 'office-approve-action-${suffix}x');
        await _tap(tester, find.text('Approve this version'));
        await _until(tester, () => office.receipts.length == 2);
        expect(office.receipts, hasLength(2));
        expect(office.receipts.last['decision'], 'approved');
        expect(office.receipts.last['values'], second['values']);
        await _show(tester, find.text('Reviewed by Sam Coordinator'));
        await _capture(tester, 'office-approved-${suffix}x');
        await _tap(tester, find.byTooltip('Back'));
        await _until(
          tester,
          () => find.text('Approved inspection').evaluate().isNotEmpty,
        );
        expect(find.text('Approved inspection'), findsWidgets);
        expect(
          find.text('Returned — Record the follow-up inspection notes.'),
          findsOneWidget,
        );
        await _show(tester, find.text('Approved inspection').last);
        await _capture(tester, 'office-history-${suffix}x');
        expect(
          first['values']['notes'],
          'Guard loose; saved before cancelled picker.',
        );
        expect(canonical(office.jobContextFor(jobId)), frozen);
        await tester.pumpWidget(const SizedBox.shrink());
        await _settle(tester);
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }
}
