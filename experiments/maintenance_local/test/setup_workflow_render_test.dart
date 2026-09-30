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
import 'package:maintenance_local/local_sync.dart';
import 'package:maintenance_local/ui/workspace_page.dart';
import 'package:maintenance_local/ui/inspection_page.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/model.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';

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

// This suite talks only to its fresh synthetic TLS server on loopback. Retain
// real HTTP so the UI's verified status cannot be fabricated by a mock result.
class _LoopbackBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
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

Future<void> _enter(WidgetTester tester, Finder target, String value) async {
  await _show(tester, target);
  await tester.enterText(target, value);
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
  final rawImage = find.descendant(of: image, matching: find.byType(RawImage));
  // FileImage decoding has an asynchronous engine callback. Pump while it
  // finishes rather than rasterizing its reserved, still blank layout space.
  await _until(
    tester,
    () =>
        rawImage.evaluate().isNotEmpty &&
        tester.widget<RawImage>(rawImage).image != null,
  );
  final raw = tester.widget<RawImage>(rawImage);
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

Future<void> _mount(
  WidgetTester tester,
  LabStore store,
  _TransportFixture sync,
  double scale,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await _settle(tester);
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
        home: WorkspacePage(store: store, phoneSyncFactory: (_) => sync),
      ),
    ),
  );
  await _settle(tester);
}

// Inject failure alone. Recovery uses the actual PhoneSync and a fresh synthetic
// loopback office, so the verified label requires the real all-job proof.
class _TransportFixture extends PhoneSync {
  _TransportFixture(super.store);
  bool unreachable = true;
  @override
  Future<void> sync() async {
    if (unreachable) {
      const failure = SocketException('Synthetic transport diagnostic');
      lastGuidance = connectionGuidance(failure);
      message = lastGuidance!.message;
      onChange?.call();
      throw failure;
    }
    await super.sync();
  }
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
      'named inspection setup, gallery and truthful status renders at ${scale}x',
      (tester) async {
        tester.view.physicalSize = const Size(412, 915);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final originalPicker = ImagePickerPlatform.instance;
        final picker = _GalleryPicker();
        ImagePickerPlatform.instance = picker;
        late Directory root;
        late LabStore office, phone;
        late OfficeServer server;
        late _TransportFixture sync;
        late String firstId, secondId, firstHash, frozen;
        late Uint8List photo;
        late File photoFile;
        await tester.runAsync(() async {
          root = await Directory.systemTemp.createTemp(
            'maintenance-setup-render-',
          );
          office = await LabStore.open(
            Directory('${root.path}/office'),
            office: true,
            maintenanceOnly: true,
          );
          await OfficeIdentity.load(office);
          await office.createCompany(
            'Synthetic Setup Construction',
            coordinatorName: 'Sam Coordinator',
          );
          final firstEquipment = await office.addEquipment(
            name: 'Synthetic yard generator',
            meterUnit: 'hours',
          );
          final secondEquipment = await office.addEquipment(
            name: 'Synthetic service excavator',
            serial: 'SYNTHETIC-SETUP24',
            meterUnit: 'km',
          );
          final checklist = await office.publishChecklist(
            title: 'Service safety inspection',
            items: [
              {
                'id': 'guards',
                'label': 'Inspect guards',
                'input_type': 'check',
              },
              {
                'id': 'pressure',
                'label': 'Record hydraulic pressure',
                'input_type': 'number',
                'unit': 'psi',
                'min': 10,
                'max': 30,
              },
              {
                'id': 'optional',
                'label': 'Optional equipment comment',
                'input_type': 'text',
                'required': false,
              },
            ],
            provenance: {'kind': 'company-authored'},
          );
          firstId =
              (await office.prepareWork(
                    equipmentId: firstEquipment['id'] as String,
                    templateId: checklist['id'] as String,
                    title: 'Yard generator inspection',
                  ))['id']
                  as String;
          secondId =
              (await office.prepareWork(
                    equipmentId: secondEquipment['id'] as String,
                    templateId: checklist['id'] as String,
                    title: 'Evening excavator inspection',
                  ))['id']
                  as String;
          server = await OfficeServer.start(
            office,
            port: 0,
            address: InternetAddress.loopbackIPv4,
          );
          phone = await LabStore.open(
            Directory('${root.path}/phone'),
            office: false,
            maintenanceOnly: true,
          );
          sync = _TransportFixture(phone);
          await sync.enroll(server.invitation('127.0.0.1'));
          server.authority.confirm(phone.device);
          await phone.importOfficeBundle(await office.publicBundle());
          sync.message = 'Saved on this phone.';
          phone.setSetting(
            'photoRecoveryError',
            'The interrupted photo could not be recovered. Choose the photo again.',
          );
          firstHash = digest(phone.documentFor(firstId)!);
          frozen = canonical(phone.jobContextFor(secondId));
          photo = await _syntheticPng();
          photoFile = File('${root.path}/saved-gallery.png');
          await photoFile.writeAsBytes(photo, flush: true);
        });
        addTearDown(() async {
          ImagePickerPlatform.instance = originalPicker;
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(() async {
            await server.close();
            await phone.close();
            await office.close();
            await root.delete(recursive: true);
          });
        });
        final suffix = scale.toInt();
        await _mount(tester, phone, sync, scale);
        expect(
          find.textContaining('The interrupted photo could not be recovered'),
          findsOneWidget,
        );
        await _capture(tester, 'phone-entry-${suffix}x');
        await _tap(tester, find.text('Update computer connection'));
        expect(
          find.textContaining('Copying on the computer alone'),
          findsOneWidget,
        );
        await _show(tester, find.text('Continue'));
        await _capture(tester, 'phone-paste-instructions-${suffix}x');
        await _tap(tester, find.text('Cancel'));
        await _tap(tester, find.text('Sync now'));
        expect(
          find.textContaining('Cannot reach the computer.'),
          findsOneWidget,
        );
        await _show(tester, find.text('Saved on this phone—waiting to send.'));
        await _capture(tester, 'phone-offline-status-${suffix}x');
        await _tap(tester, find.text('More connection help'));
        await _show(tester, find.textContaining('After changing networks'));
        expect(find.textContaining('TCP 47841'), findsOneWidget);
        await _capture(tester, 'phone-connection-help-${suffix}x');
        final card = find.ancestor(
          of: find.text('Evening excavator inspection'),
          matching: find.byType(Card),
        );
        await _tap(
          tester,
          find.descendant(
            of: card,
            matching: find.widgetWithText(FilledButton, 'Continue inspection'),
          ),
        );
        final page = find.byType(InspectionPage);
        expect(tester.widget<InspectionPage>(page).jobId, secondId);
        expect(
          find.descendant(
            of: page,
            matching: find.text('Evening excavator inspection'),
          ),
          findsOneWidget,
        );
        await _capture(tester, 'named-inspection-entry-${suffix}x');
        final check = find.ancestor(
          of: find.text('Inspect guards'),
          matching: find.byType(Card),
        );
        await _tap(
          tester,
          find.descendant(of: check, matching: find.text('Needs action')),
        );
        await _enter(tester, find.byKey(const Key('answer:pressure')), '35');
        await _enter(
          tester,
          find.byKey(const Key('answer:optional')),
          'Temporary optional response',
        );
        await _tap(tester, find.text('Leave optional step unanswered'));
        await _enter(tester, find.byKey(const Key('meter')), '0');
        await _enter(
          tester,
          find.byKey(const Key('notes')),
          'Synthetic setup inspection. Guard loose and pressure 35 psi; follow-up required.',
        );
        await _show(tester, find.text('Changes are not saved yet.'));
        await _capture(tester, 'named-inspection-unsaved-${suffix}x');
        picker.next = XFile(photoFile.path);
        await _tap(tester, find.text('Choose a saved photo'));
        expect(picker.sources, [ImageSource.gallery]);
        expect(phone.setting('photoRecoveryError'), isNull);
        await _visiblePhoto(tester);
        await _capture(tester, 'named-inspection-gallery-${suffix}x');
        late Json values;
        await tester.runAsync(() async {
          values = valuesOf(await phone.fields(jobId: secondId));
        });
        expect(values['photo'], digest(photo));
        expect(values['answer:optional'], isNull);
        expect(values['answer:pressure'], {'result': 'action', 'value': '35'});
        expect(values['meter'], 0);
        expect(values['unit'], 'km');
        expect(digest(phone.documentFor(firstId)!), firstHash);
        expect(canonical(phone.jobContextFor(secondId)), frozen);
        await _enter(
          tester,
          find.byKey(const Key('notes')),
          'Synthetic setup inspection. Notes saved before a cancelled gallery replacement.',
        );
        await _tap(tester, find.text('Replace inspection photo'));
        await tester.runAsync(() async {
          values = valuesOf(await phone.fields(jobId: secondId));
        });
        expect(values['photo'], digest(photo));
        expect(values['notes'], contains('cancelled gallery replacement'));
        await _show(
          tester,
          find.text(
            'No photo selected. Your inspection notes and readings are saved.',
          ),
        );
        await _capture(tester, 'named-inspection-gallery-cancel-${suffix}x');
        await _tap(tester, find.text('Submit for review'));
        expect(phone.submissions.single['jobId'], secondId);
        expect(canonical(phone.submissions.single['context']), frozen);
        expect(phone.submissions.single['_state'], 'queued');
        await _show(
          tester,
          find.text(
            'Version saved for review. Its sending status is shown above.',
          ),
        );
        await _capture(tester, 'named-inspection-waiting-${suffix}x');
        await _tap(tester, find.byTooltip('Back'));
        expect(
          find.textContaining('The interrupted photo could not be recovered'),
          findsNothing,
        );
        sync.unreachable = false;
        await _tap(tester, find.text('Sync now'));
        await _until(
          tester,
          () =>
              !sync.busy &&
              sync.visibleMessage == 'Saved on the computer. Photos verified.',
        );
        expect(find.textContaining('Cannot reach the computer.'), findsNothing);
        expect(find.text('More connection help'), findsNothing);
        expect(phone.submissions.single['_state'], 'received');
        await tester.runAsync(() async {
          expect(await office.evidence.complete(digest(photo)), isTrue);
          expect(
            await office.evidence.file(digest(photo)).readAsBytes(),
            photo,
          );
        });
        expect(
          digest(office.documentFor(secondId)!),
          digest(phone.documentFor(secondId)!),
        );
        expect(digest(phone.documentFor(firstId)!), firstHash);
        await _show(
          tester,
          find.text('Saved on the computer. Photos verified.'),
        );
        await _capture(tester, 'phone-verified-all-jobs-${suffix}x');
        // Pause only the synthetic binding, retaining proof while making a new
        // local draft. No automatic exchange may hide the downgraded status.
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await _tap(
          tester,
          find.descendant(
            of: card,
            matching: find.widgetWithText(FilledButton, 'Continue inspection'),
          ),
        );
        await _enter(
          tester,
          find.byKey(const Key('notes')),
          'New local notes after verified sending; not yet on the computer.',
        );
        expect(
          find.descendant(
            of: page,
            matching: find.text('Saved on the computer. Photos verified.'),
          ),
          findsNothing,
        );
        await _tap(tester, find.text('Save work'));
        expect(
          find.descendant(
            of: page,
            matching: find.text('Saved on this phone—waiting to send.'),
          ),
          findsOneWidget,
        );
        await _show(tester, find.text('Saved on this phone—waiting to send.'));
        await _capture(tester, 'named-inspection-new-draft-${suffix}x');
        await tester.runAsync(() async {
          expect(
            valuesOf(await office.fields(jobId: secondId))['notes'],
            contains('cancelled gallery replacement'),
          );
        });
        expect(canonical(phone.jobContextFor(secondId)), frozen);
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }
}
