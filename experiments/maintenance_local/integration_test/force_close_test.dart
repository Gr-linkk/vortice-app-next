import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/model.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Acknowledged open-WAL work survives a deliberate Android force-stop',
    (tester) async {
      await RustLib.init();
      final base = await getApplicationSupportDirectory();
      final root = Directory('${base.path}/force-close-acceptance');
      await root.create(recursive: true);
      final marker = File('${root.path}/ready.json');
      const restart = bool.fromEnvironment('CHECK_RESTART');
      final phone = await LabStore.open(
        Directory('${root.path}/phone'),
        office: false,
        now: () => DateTime.now().add(const Duration(days: restart ? 30 : 0)),
      );
      if (!restart) {
        final office = await LabStore.open(
          Directory('${root.path}/synthetic-fixture'),
          office: true,
        );
        await office.createWorkspace();
        await phone.importOfficeBundle(await office.publicBundle());
        await office.close();
        await phone.update({
          'fluid': 'pass',
          'guards': 'attention',
          'meter': 827.5,
          'notes': 'Saved immediately before forced termination.',
        });
        final fixture = Directory(
          '${base.path}/workflow-acceptance/phone/evidence',
        );
        final photo =
            (await fixture
                        .list()
                        .where(
                          (f) =>
                              f is File &&
                              hashPattern.hasMatch(f.uri.pathSegments.last),
                        )
                        .toList())
                    .first
                as File;
        await phone.attach(await photo.readAsBytes());
        final submitted = await phone.submit();
        phone.setSetting('forceCloseProbe', phone.stamp());
        await marker.writeAsString(
          jsonEncode({
            'id': submitted['id'],
            'photo': (submitted['values'] as Json)['photo'],
          }),
          flush: true,
        );
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: Center(
                child: Text('Work saved. Ready for intentional force-close.'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        // Deliberately leave SQLite and its WAL open. The external ADB runner kills
        // this process; this injection phase is expected to lose its test connection.
        await Completer<void>().future;
      } else {
        final ready = jsonDecode(await marker.readAsString()) as Json;
        expect(phone.submissions.single['id'], ready['id']);
        expect(phone.submissions.single['_state'], 'queued');
        expect(valuesOf(await phone.fields())['meter'], 827.5);
        expect(await phone.evidence.complete(ready['photo'] as String), isTrue);
        expect(phone.setting('forceCloseProbe'), isNotNull);
        await File('${root.path}/result.json').writeAsString(
          jsonEncode({
            ...ready,
            'passed': true,
            'openWalForceStop': true,
            'simulatedOfflineDays': 30,
          }),
          flush: true,
        );
        await phone.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
