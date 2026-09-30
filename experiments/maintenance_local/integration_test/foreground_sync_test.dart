import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/local_sync.dart';
import 'package:maintenance_local/main.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Foreground reconnect sends queued work and manual retry is safe', (
    tester,
  ) async {
    if (!Platform.isLinux) {
      throw StateError('Run this two-store rendered fixture on Linux.');
    }
    await RustLib.init();
    final root = await Directory.systemTemp.createTemp('vortice-foreground-');
    final office = await LabStore.open(
      Directory('${root.path}/office'),
      office: true,
    );
    final phone = await LabStore.open(
      Directory('${root.path}/phone'),
      office: false,
    );
    OfficeServer? server;
    Future<void> until(bool Function() done) async {
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while (!done()) {
        if (DateTime.now().isAfter(deadline)) {
          throw StateError('Foreground synchronization timed out.');
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    try {
      await office.createWorkspace();
      server = await OfficeServer.start(office, port: 0);
      final port = server.port;
      await PhoneSync(phone).enroll(server.invitation('127.0.0.1'));
      server.authority.confirm(phone.device);
      await tester.pumpWidget(LabApp(store: phone));
      final PhoneSync foreground =
          (tester.state(find.byType(WorkspacePage)) as dynamic).sync
              as PhoneSync;
      // The rendered app must discover confirmation through its foreground timer.
      await until(() => phone.workspace != null);
      await until(() => phone.setting('lastCompleteSync') != null);
      await until(() => !foreground.busy);
      await server.close();
      server = null;
      await phone.update({
        'fluid': 'pass',
        'guards': 'attention',
        'meter': 12.5,
        'notes': 'Synthetic foreground retry fixture.',
      });
      await phone.attach(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aO7sAAAAASUVORK5CYII=',
        ),
      );
      final queued = await phone.submit();
      await Future<void>.delayed(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(office.submissions, isEmpty);
      expect(phone.submissions.single['_state'], 'queued');
      server = await OfficeServer.start(office, port: port);
      // Do not press Sync now: recovery after the server returns must be automatic.
      await until(() => office.submissions.isNotEmpty);
      await until(() => phone.submissions.single['_state'] != 'queued');
      await until(() => !foreground.busy);
      await office.decide(queued['id'] as String, approve: true);
      await tester.ensureVisible(find.text('Sync now'));
      await tester.tap(find.text('Sync now'));
      await until(() => phone.receipts.isNotEmpty);
      await until(() => !foreground.busy);
      await tester.ensureVisible(find.text('Sync now'));
      await tester.tap(find.text('Sync now'));
      await until(() => !foreground.busy);
      expect(office.submissions.length, 1);
      expect(office.submissions.single['id'], queued['id']);
      expect(phone.receipts.single['decision'], 'approved');
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await server?.close();
      await phone.close();
      await office.close();
      await root.delete(recursive: true);
    }
  });
}
