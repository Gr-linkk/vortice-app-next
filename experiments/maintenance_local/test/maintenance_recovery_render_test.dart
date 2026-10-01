import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/app.dart';
import 'package:maintenance_local/device_authority.dart';
import 'package:maintenance_local/lab_bootstrap.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/local_sync.dart';
import 'package:maintenance_local/model.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';
import 'package:maintenance_local/ui/workspace_page.dart';
import 'support/native_widget_cleanup.dart';

const _captureKey = Key('maintenance-recovery-render-boundary');

Future<void> _settle(WidgetTester tester) async {
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
    reason: 'The actual recovery screen must have no errors or overflow.',
  );
}

Future<void> _until(WidgetTester tester, bool Function() complete) async {
  for (var attempt = 0; attempt < 40; attempt++) {
    if (complete()) return;
    await _settle(tester);
  }
  expect(complete(), isTrue, reason: 'The native recovery action must finish.');
}

Future<void> _show(WidgetTester tester, Finder target) async {
  expect(target, findsOneWidget);
  await tester.ensureVisible(target);
  await tester.pump(const Duration(milliseconds: 250));
  expect(
    target.hitTestable(),
    findsOneWidget,
    reason: 'The ordinary recovery action must be reachable at this text size.',
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

Future<void> _enter(WidgetTester tester, String key, String value) async {
  final target = find.byKey(Key(key));
  await _show(tester, target);
  // Checking a backup disables the field and detaches its input connection.
  tester.binding.focusedEditable = null;
  await tester.enterText(target, value);
  await _settle(tester);
}

Future<void> _capture(WidgetTester tester, String name) async {
  final output = Platform.environment['VORTICE_RENDER_OUTPUT'];
  if (output == null || output.isEmpty) return;
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
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

Future<void> _mount(WidgetTester tester, LabStore store, double scale) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await _settle(tester);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _captureKey,
      child: LabApp(store: store, textScale: scale, officePort: 0),
    ),
  );
  await _settle(tester);
}

Future<Uint8List> _photo() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(const Color(0xffe4ece6), BlendMode.src);
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTWH(20, 35, 360, 180),
      const Radius.circular(16),
    ),
    Paint()..color = const Color(0xff103d3c),
  );
  final label = TextPainter(
    text: const TextSpan(
      text: 'SYNTHETIC RECOVERY PHOTO\nSaved inspection evidence',
      style: TextStyle(fontFamily: 'Roboto', fontSize: 20, color: Colors.white),
    ),
    textAlign: TextAlign.center,
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: 340);
  label.paint(canvas, const Offset(30, 95));
  label.dispose();
  final picture = recorder.endRecording();
  final image = await picture.toImage(400, 250);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
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
      'normal maintenance backup restore and reopen renders at ${scale}x text',
      (tester) async {
        tester.view.physicalSize = const Size(412, 915);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        late Directory root;
        final live = <LabStore>{};
        await tester.runAsync(() async {
          root = await Directory.systemTemp.createTemp(
            'maintenance-recovery-render-',
          );
        });
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await finishNativeWidgetCleanup(tester, () async {
            for (final store in live) {
              await store.close();
            }
            await root.delete(recursive: true);
          });
        });

        late LabStore source;
        late OfficeIdentity identity;
        late Json submitted, receipt;
        late String jobId, frozen, photoHash;
        late Uint8List photo;
        await tester.runAsync(() async {
          source = await LabStore.open(
            Directory('${root.path}/source'),
            office: true,
            maintenanceOnly: true,
          );
          live.add(source);
          // Establish identity before catalog/documents, as normal startup does.
          identity = await OfficeIdentity.load(source);
          await source.createCompany(
            'Synthetic Recovery Construction',
            coordinatorName: 'Sam Coordinator',
          );
          final equipment = await source.addEquipment(
            name: 'Synthetic recovery excavator',
            serial: 'SYNTHETIC-R24',
            meterUnit: 'hours',
          );
          final template = await source.publishChecklist(
            title: 'Recovery inspection',
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
            ],
            provenance: {'kind': 'company-authored'},
          );
          final job = await source.prepareWork(
            equipmentId: equipment['id'] as String,
            templateId: template['id'] as String,
            title: 'Saved inspection for recovery',
          );
          jobId = job['id'] as String;
          frozen = canonical(source.jobContextFor(jobId));
          await source.update({
            'answer:guards': {'result': 'action', 'value': ''},
            'answer:pressure': {'result': 'action', 'value': '35'},
            'meter': 0,
            'notes':
                'Synthetic recovery record. Guard and pressure need follow-up.',
          }, jobId: jobId);
          photo = await _photo();
          photoHash = await source.attach(photo, jobId: jobId);
          submitted = await source.submit(jobId: jobId);
          receipt = await source.decide(
            submitted['id'] as String,
            approve: true,
          );
          final authority = DeviceAuthority(source);
          for (final phone in ['retained-phone', 'revoked-phone']) {
            authority.request({
              'device': phone,
              'label': phone,
              'token': secret(),
              'invitation': authority.invite(),
            });
            authority.confirm(phone);
          }
          authority.revoke('revoked-phone');
          authority.invite();
        });
        final sourceDevice = source.device;
        final suffix = scale.toInt();
        final backup = Directory('${root.path}/backup');
        final target = Directory('${root.path}/restored');
        final launcherRoot = Directory('${root.path}/launcher');
        await _mount(tester, source, scale);
        await _tap(tester, find.text('Back up office computer'));
        await _enter(tester, 'backupDestination', backup.path);
        await _show(tester, find.text('Create verified backup'));
        await _capture(tester, 'maintenance-backup-form-${suffix}x');
        await _tap(tester, find.text('Create verified backup'));
        await _until(
          tester,
          () => find.textContaining('Backup verified:').evaluate().isNotEmpty,
        );
        await _show(tester, find.textContaining('Backup verified:'));
        await _capture(tester, 'maintenance-backup-verified-${suffix}x');
        await tester.runAsync(() async {
          final manifest =
              jsonDecode(
                    await File('${backup.path}/manifest.json').readAsString(),
                  )
                  as Json;
          expect(manifest['format'], 'maintenance-local-office');
          expect(manifest['version'], 2);
        });
        await tester.pumpWidget(const SizedBox.shrink());
        await _settle(tester);
        await tester.runAsync(() async {
          await source.close();
          live.remove(source);
        });

        late LabStore launcher;
        await tester.runAsync(() async {
          launcher = await openLabWorkspace(
            launcherRoot,
            office: true,
            maintenanceOnly: true,
          );
          live.add(launcher);
        });
        await _mount(tester, launcher, scale);
        expect(find.text('Start with your company'), findsOneWidget);
        await _tap(tester, find.text('Restore office backup'));
        expect(find.text('Recover the same office'), findsOneWidget);
        await _capture(tester, 'maintenance-restore-entry-${suffix}x');
        await _enter(tester, 'restoreSource', backup.path);
        await _enter(tester, 'restoreDestination', target.path);
        await _enter(tester, 'restoreFingerprint', '0' * 64);
        await _tap(tester, find.text('Check backup'));
        await _until(
          tester,
          () => find.textContaining('Backup checked:').evaluate().isNotEmpty,
        );
        final restore = find.widgetWithText(
          FilledButton,
          'Restore verified office',
        );
        expect(tester.widget<FilledButton>(restore).onPressed, isNull);
        await _show(
          tester,
          find.textContaining('The saved fingerprint does not match'),
        );
        await _capture(tester, 'maintenance-restore-pin-mismatch-${suffix}x');
        expect(
          await tester.runAsync(target.exists),
          isFalse,
          reason:
              'An incorrect saved fingerprint must not publish a workspace.',
        );
        await _enter(tester, 'restoreFingerprint', identity.fingerprint);
        expect(
          find.textContaining('The saved fingerprint does not match'),
          findsNothing,
        );
        expect(tester.widget<FilledButton>(restore).onPressed, isNotNull);
        await _show(tester, find.text('Restore verified office'));
        await _capture(tester, 'maintenance-restore-ready-${suffix}x');
        await _tap(tester, find.text('Restore verified office'));
        await _until(
          tester,
          () => find
              .textContaining('Office backup restored.')
              .evaluate()
              .isNotEmpty,
        );
        final copy = tester
            .widget<WorkspacePage>(find.byType(WorkspacePage))
            .store;
        // Normal UI closes the empty launcher after publishing its pointer.
        live.remove(launcher);
        live.add(copy);
        expect(copy.root.absolute.path, target.absolute.path);
        expect(copy.device, sourceDevice);
        expect(
          copy.setting('localMaintenanceApplication'),
          'org.vortice.next.maintenance_local',
        );
        expect(copy.setting('localMaintenanceRole'), 'linux-office');
        expect(copy.submissions.single['id'], submitted['id']);
        expect(copy.receipts.single, receipt);
        expect(canonical(copy.jobContextFor(jobId)), frozen);
        expect(DeviceAuthority(copy).phones.map((phone) => phone['status']), [
          'pending',
          'revoked',
        ]);
        expect(copy.db.select('SELECT * FROM invites'), isEmpty);
        await tester.runAsync(() async {
          expect(
            jsonDecode(
              await File(
                '${target.path}/maintenance-local-owner.json',
              ).readAsString(),
            ),
            {
              'application': 'org.vortice.next.maintenance_local',
              'role': 'linux-office',
              'version': 1,
            },
          );
          expect(await copy.evidence.complete(photoHash), isTrue);
          expect(await copy.evidence.file(photoHash).readAsBytes(), photo);
        });
        await _show(tester, find.textContaining('Office backup restored.'));
        await _capture(tester, 'maintenance-office-restored-${suffix}x');
        await _until(
          tester,
          () => find.text('Approved inspection').evaluate().isNotEmpty,
        );
        await _tap(tester, find.text('Approved inspection').last);
        expect(find.text('Recovery inspection · checklist v1'), findsOneWidget);
        expect(find.text('Needs action · 35 psi'), findsOneWidget);
        await _until(tester, () {
          final images = find.byType(RawImage);
          return images.evaluate().isNotEmpty &&
              tester.widget<RawImage>(images.first).image != null;
        });
        await _show(tester, find.text('Reviewed by Sam Coordinator'));
        await _capture(tester, 'maintenance-restored-review-${suffix}x');
        await tester.pumpWidget(const SizedBox.shrink());
        await _settle(tester);
        await finishNativeWidgetCleanup(tester, () async {
          await copy.close();
          live.remove(copy);
        });

        late LabStore reopened;
        await tester.runAsync(() async {
          reopened = await openLabWorkspace(
            launcherRoot,
            office: true,
            maintenanceOnly: true,
          );
          live.add(reopened);
          expect(reopened.root.absolute.path, target.absolute.path);
          expect(reopened.device, sourceDevice);
          expect(
            (await OfficeIdentity.load(reopened)).fingerprint,
            identity.fingerprint,
          );
          expect(canonical(reopened.jobContextFor(jobId)), frozen);
          expect(reopened.receipts.single, receipt);
          expect(
            DeviceAuthority(reopened).phones.map((phone) => phone['status']),
            ['pending', 'revoked'],
          );
        });
        await _mount(tester, reopened, scale);
        await _show(tester, find.text('Approved inspection').last);
        await _capture(tester, 'maintenance-office-reopened-${suffix}x');
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }
}
