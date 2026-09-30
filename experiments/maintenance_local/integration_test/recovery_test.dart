import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:maintenance_local/device_authority.dart';
import 'package:maintenance_local/lab_bootstrap.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/local_sync.dart';
import 'package:maintenance_local/main.dart';
import 'package:maintenance_local/model.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => RustLib.init());
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'Office backup, fresh restore and camera-free entry at ${scale}x text',
      (tester) async {
        final root = await Directory.systemTemp.createTemp(
          'sync-lab-rendered-recovery-',
        );
        final captureKey = GlobalKey();
        tester.view.physicalSize = const Size(412, 915);
        tester.view.devicePixelRatio = 1;
        Future<void> waitFor(Finder finder) async {
          final deadline = DateTime.now().add(const Duration(seconds: 20));
          while (finder.evaluate().isEmpty &&
              DateTime.now().isBefore(deadline)) {
            await tester.pump(const Duration(milliseconds: 100));
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
          if (finder.evaluate().isEmpty) {
            debugPrint(
              'Recovery screen at timeout: ${find.byType(Text).evaluate().map((e) => (e.widget as Text).data).whereType<String>().join(' | ')}',
            );
          }
          expect(finder, findsOneWidget);
          await tester.pumpAndSettle();
        }

        Future<void> capture(String name) async {
          await tester.pumpAndSettle();
          final boundary =
              captureKey.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.png,
          ))!.buffer.asUint8List();
          image.dispose();
          final output = Directory(
            Platform.environment['VORTICE_LAB_ACCEPTANCE_OUTPUT'] ??
                '${root.path}/screenshots',
          );
          await output.create(recursive: true);
          await File(
            '${output.path}/$name-${scale}x.png',
          ).writeAsBytes(bytes, flush: true);
        }

        Future<void> enter(String key, String text) async {
          final finder = find.byKey(Key(key));
          await tester.ensureVisible(finder);
          // Checking a backup disables the focused field and detaches input.
          // Clear the test binding's cached target before reopening it.
          tester.binding.focusedEditable = null;
          await tester.showKeyboard(finder);
          await tester.pumpAndSettle();
          await tester.enterText(finder, text);
          await tester.pumpAndSettle();
        }

        Future<void> tap(String label) async {
          final finder = find.text(label);
          await tester.ensureVisible(finder);
          await tester.tap(finder);
          await tester.pumpAndSettle();
        }

        var office = await LabStore.open(
          Directory('${root.path}/source'),
          office: true,
        );
        await office.createWorkspace();
        final identity = await OfficeIdentity.load(office),
            device = office.device;
        await office.update({
          'fluid': 'pass',
          'guards': 'attention',
          'meter': 101.25,
          'notes': 'Synthetic saved-image office recovery.',
        });
        await office.attach(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jWL0AAAAASUVORK5CYII=',
          ),
        );
        final submitted = await office.submit();
        final receipt = await office.decide(
          submitted['id'] as String,
          approve: true,
        );
        final authority = DeviceAuthority(office);
        for (final id in ['retained-phone', 'revoked-phone']) {
          authority.request({
            'device': id,
            'label': id,
            'token': secret(),
            'invitation': authority.invite(),
          });
          authority.confirm(id);
        }
        authority.revoke('revoked-phone');
        await tester.pumpWidget(
          RepaintBoundary(
            key: captureKey,
            child: LabApp(store: office, textScale: scale, officePort: 0),
          ),
        );
        await tester.pumpAndSettle();
        await tap('Back up office computer');
        final backup = Directory('${root.path}/backup'),
            target = Directory('${root.path}/restored');
        await enter('backupDestination', backup.path);
        await tap('Create verified backup');
        await waitFor(find.textContaining('Backup verified:'));
        await tester.ensureVisible(find.textContaining('Backup verified:'));
        await capture('backup-verified');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await office.close();
        final launcherRoot = Directory('${root.path}/launcher');
        office = await LabStore.open(launcherRoot, office: true);
        await tester.pumpWidget(
          RepaintBoundary(
            key: captureKey,
            child: LabApp(store: office, textScale: scale, officePort: 0),
          ),
        );
        await tester.pumpAndSettle();
        await tap('Restore office backup');
        await enter('restoreSource', backup.path);
        await enter('restoreDestination', target.path);
        await enter('restoreFingerprint', '0' * 64);
        await tap('Check backup');
        await waitFor(find.textContaining('Backup checked:'));
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Restore verified office'),
              )
              .onPressed,
          isNull,
        );
        await tester.ensureVisible(find.text('Restore verified office'));
        await capture('restore-pin-mismatch');
        await enter('restoreFingerprint', identity.fingerprint);
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('restoreFingerprint')))
              .controller!
              .text,
          identity.fingerprint,
        );
        expect(find.textContaining('Backup checked:'), findsOneWidget);
        expect(
          find.textContaining('The saved fingerprint does not match'),
          findsNothing,
        );
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Restore verified office'),
              )
              .onPressed,
          isNotNull,
        );
        await tap('Restore verified office');
        await waitFor(find.textContaining('Office backup restored.'));
        final copy = tester
            .widget<WorkspacePage>(find.byType(WorkspacePage))
            .store;
        expect(copy.device, device);
        expect(copy.receipts.single, receipt);
        expect(copy.submissions.single['id'], submitted['id']);
        expect(DeviceAuthority(copy).phones.map((p) => p['status']), [
          'pending',
          'revoked',
        ]);
        await tester.ensureVisible(
          find.textContaining('Office backup restored.'),
        );
        await capture('office-restored');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await copy.close();
        final reopened = await openLabWorkspace(launcherRoot, office: true);
        expect(reopened.device, device);
        expect(
          (await OfficeIdentity.load(reopened)).fingerprint,
          identity.fingerprint,
        );
        await reopened.close();
        final phone = await LabStore.open(
          Directory('${root.path}/phone'),
          office: false,
        );
        await tester.pumpWidget(
          RepaintBoundary(
            key: captureKey,
            child: LabApp(store: phone, textScale: scale),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(FilledButton, 'Paste invitation'),
          findsOneWidget,
        );
        await tester.ensureVisible(find.text('Paste invitation'));
        await capture('phone-paste-entry');
        await tap('Paste invitation');
        expect(find.text('Paste computer invitation'), findsOneWidget);
        await tester.enterText(
          find.byType(TextField),
          '{incomplete invitation',
        );
        await tap('Continue');
        await waitFor(
          find.text('Paste the complete invitation copied from the computer.'),
        );
        expect(phone.setting('pairing'), isNull);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await phone.close();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        await root.delete(recursive: true);
      },
    );
  }
}
