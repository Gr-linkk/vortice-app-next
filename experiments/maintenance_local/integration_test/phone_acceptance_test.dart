import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/local_sync.dart';
import 'package:maintenance_local/main.dart';
import 'package:maintenance_local/model.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Physical phone save, restart, transfer and replacement assertions',
    (tester) async {
      await RustLib.init();
      const phase = String.fromEnvironment('PHASE', defaultValue: 'save');
      const encoded = String.fromEnvironment('INVITE');
      final base = await getApplicationSupportDirectory();
      final root = Directory(
        '${base.path}/physical-acceptance/${phase == 'restore' ? 'replacement' : 'phone'}',
      );
      final store = await LabStore.open(
        root,
        office: false,
        now: () => DateTime.now().add(const Duration(days: 30)),
      );
      final sync = PhoneSync(store);
      final timer = Stopwatch()..start();
      Future<void> until(Future<bool> Function() condition) async {
        final deadline = DateTime.now().add(const Duration(minutes: 5));
        while (!await condition()) {
          if (DateTime.now().isAfter(deadline)) {
            throw StateError(
              'Timed out waiting for office confirmation/review.',
            );
          }
          await tester.pump(const Duration(milliseconds: 250));
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      }

      if (phase == 'save' || phase == 'restore') {
        await sync.enroll(
          utf8.decode(base64Decode(encoded)),
          label: phase == 'restore'
              ? 'Replacement S24 test'
              : 'S24 physical test',
        );
        await until(() async {
          await sync.sync();
          return store.workspace != null;
        });
      }
      if (phase == 'save') {
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
        await store.attach(await photo.readAsBytes());
        await tester.pumpWidget(
          MaterialApp(home: InspectionPage(store: store)),
        );
        await tester.pumpAndSettle();
        // The test runner removes the USB route before the saved work below.
        await File(
          '${base.path}/physical-acceptance/offline-ready',
        ).writeAsString('ready', flush: true);
        await Future<void>.delayed(const Duration(seconds: 15));
        await expectLater(sync.sync(), throwsA(anything));
        await tester.tap(find.text('Pass').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Needs attention').last);
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('meter')), '314.25');
        await tester.enterText(
          find.byKey(const Key('notes')),
          'Physical S24 offline check: inspect loose guard.',
        );
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Submit for review'));
        await tester.tap(find.text('Submit for review'));
        await tester.pumpAndSettle();
        expect(store.submissions.length, 1);
        expect(store.submissions.single['_state'], 'queued');
      } else if (phase == 'send') {
        expect(store.submissions.length, 1);
        expect(valuesOf(await store.fields())['meter'], 314.25);
        final originalId = store.submissions.single['id'];
        await sync.sync();
        await until(() async {
          await sync.sync();
          return store.receipts.isNotEmpty;
        });
        expect(store.submissions.single['id'], originalId);
        expect(store.receipts.single['decision'], 'approved');
        await tester.pumpWidget(LabApp(store: store));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Approved'));
        await tester.tap(find.text('Approved'));
        await tester.pumpAndSettle();
        expect(find.text('314.25 hours'), findsOneWidget);
      } else if (phase == 'revoked') {
        final c = PinnedConnection(sync.pairing!);
        await expectLater(c.request('/bundle', {}), throwsStateError);
        c.close();
      } else if (phase == 'restore') {
        await sync.sync();
        expect(store.submissions.length, 1);
        expect(store.receipts.single['decision'], 'approved');
        expect(valuesOf(await store.fields())['meter'], 314.25);
        expect(
          await store.evidence.complete(
            (store.submissions.single['values'] as Json)['photo'] as String,
          ),
          isTrue,
        );
        await tester.pumpWidget(LabApp(store: store));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Approved'));
        await tester.tap(find.text('Approved'));
        await tester.pumpAndSettle();
        expect(find.text('314.25 hours'), findsOneWidget);
      }
      final result = {
        'phase': phase,
        'milliseconds': timer.elapsedMilliseconds,
        'submissions': store.submissions,
        'receipts': store.receipts,
        'blobs': await store.evidence.manifest(),
        'passed': true,
      };
      await File(
        '${base.path}/physical-acceptance/$phase-result.json',
      ).writeAsString(jsonEncode(result), flush: true);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await store.close();
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
