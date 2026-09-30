import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/local_sync.dart';
import 'package:maintenance_local/main.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Office ordinary setup, confirmation, exact review and lost-phone recovery',
    (tester) async {
      await RustLib.init();
      const path = String.fromEnvironment('ACCEPTANCE_ROOT');
      if (path.isEmpty || !Platform.isLinux) {
        throw StateError(
          'Use the guarded office acceptance command with an isolated root.',
        );
      }
      final root = Directory(path);
      await root.create(recursive: true);
      final store = await LabStore.open(
        Directory('$path/office'),
        office: true,
      );
      final captureKey = GlobalKey();
      Future<void> capture(String name) async {
        await tester.pumpAndSettle();
        final boundary =
            captureKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        await File('$path/$name.png').writeAsBytes(
          (await image.toByteData(
            format: ui.ImageByteFormat.png,
          ))!.buffer.asUint8List(),
          flush: true,
        );
        image.dispose();
      }

      Future<void> until(bool Function() condition, String description) async {
        final deadline = DateTime.now().add(const Duration(minutes: 15));
        while (!condition()) {
          if (DateTime.now().isAfter(deadline)) {
            throw StateError('Timed out waiting for $description');
          }
          await tester.pump(const Duration(milliseconds: 300));
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }
        await tester.pumpAndSettle();
      }

      await tester.pumpWidget(
        RepaintBoundary(
          key: captureKey,
          child: LabApp(
            store: store,
            textScale: double.parse(
              const String.fromEnvironment('TEXT_SCALE', defaultValue: '1'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (store.workspace == null) {
        await tester.ensureVisible(find.text('Create demo workspace'));
        await tester.tap(find.text('Create demo workspace'));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.text('Connect or replace a phone'));
      await tester.tap(find.text('Connect or replace a phone'));
      await tester.pumpAndSettle();
      final OfficeServer server =
          (tester.state(find.byType(WorkspacePage, skipOffstage: false))
                      as dynamic)
                  .server
              as OfficeServer;
      const host = String.fromEnvironment(
        'PHONE_HOST',
        defaultValue: '127.0.0.1',
      );
      Future<void> writeInvitation(String name) async {
        final pending = File('$path/.$name.pending');
        await pending.writeAsString(server.invitation(host), flush: true);
        await pending.rename('$path/$name');
      }

      await writeInvitation('invitation.json');
      await capture('office-setup');
      await until(
        () => find.text('Codes match — allow this phone').evaluate().isNotEmpty,
        'phone enrollment',
      );
      await capture('office-confirmation');
      await tester.ensureVisible(
        find.text('Codes match — allow this phone').first,
      );
      await tester.tap(find.text('Codes match — allow this phone').first);
      await tester.pumpAndSettle();
      await File('$path/confirmed').writeAsString('yes', flush: true);
      await until(() => store.submissions.isNotEmpty, 'submitted work');
      final submission = store.submissions.first;
      final photo = (submission['values'] as Map)['photo'] as String;
      while (!await store.evidence.complete(photo)) {
        await tester.pump(const Duration(milliseconds: 300));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Awaiting review'));
      await tester.tap(find.text('Awaiting review'));
      await tester.pumpAndSettle();
      await capture('office-submitted-version');
      await tester.ensureVisible(find.text('Approve this version'));
      await tester.tap(find.text('Approve this version'));
      await tester.pumpAndSettle();
      expect(store.receipts.single['decision'], 'approved');
      await capture('office-approved');
      await File(
        '$path/approved.json',
      ).writeAsString(jsonEncode(store.receipts.single), flush: true);
      await until(
        () => File('$path/revoke-now').existsSync(),
        'recovery stage',
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Connect or replace a phone'));
      await tester.tap(find.text('Connect or replace a phone'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Revoke phone').first);
      await tester.tap(find.text('Revoke phone').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Revoke phone'));
      await tester.pumpAndSettle();
      expect(server.authority.phones.first['status'], 'revoked');
      await writeInvitation('replacement-invitation.json');
      await capture('office-revoked');
      await until(
        () => find.text('Codes match — allow this phone').evaluate().isNotEmpty,
        'replacement enrollment',
      );
      await tester.ensureVisible(
        find.text('Codes match — allow this phone').first,
      );
      await tester.tap(find.text('Codes match — allow this phone').first);
      await tester.pumpAndSettle();
      await until(
        () => File('$path/finish').existsSync(),
        'physical phone assertions',
      );
      await File('$path/office-result.json').writeAsString(
        jsonEncode({
          'submissions': store.submissions,
          'receipts': store.receipts,
          'blobs': await store.evidence.manifest(),
          'devices': server.authority.phones,
          'passed': true,
        }),
        flush: true,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await store.close();
    },
    timeout: const Timeout(Duration(minutes: 30)),
  );
}
