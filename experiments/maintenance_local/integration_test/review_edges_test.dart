import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/main.dart';
import 'package:maintenance_local/model.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';

Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
  await tester.pumpAndSettle();
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1);
  final root = Directory(
    '${(await getApplicationSupportDirectory()).path}/review-edge-evidence',
  );
  await root.create(recursive: true);
  await File('${root.path}/$name.png').writeAsBytes(
    (await image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List(),
    flush: true,
  );
  image.dispose();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => RustLib.init());
  testWidgets('Resolving a notes conflict preserves an unsaved meter reading', (
    tester,
  ) async {
    final root = await Directory.systemTemp.createTemp('vortice-review-edges-');
    final office = await LabStore.open(
      Directory('${root.path}/office'),
      office: true,
    );
    final phone = await LabStore.open(
      Directory('${root.path}/phone'),
      office: false,
    );
    try {
      await office.createWorkspace();
      await office.update({
        'fluid': 'pass',
        'guards': 'attention',
        'meter': 10,
        'notes': 'Initial note.',
      });
      await phone.importOfficeBundle(await office.publicBundle());
      await office.update({'notes': 'Office note.'});
      await phone.update({'notes': 'Phone note.'});
      await phone.importOfficeBundle(await office.publicBundle());
      expect(conflicts(await phone.fields()), contains('notes'));
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: LabApp(store: phone, textScale: 2),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Continue inspection'));
      await tester.tap(find.text('Continue inspection'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('meter')));
      await tester.enterText(find.byKey(const Key('meter')), '121.75');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Use: Phone note.'));
      await capture(tester, key, 'conflict-before-choice');
      await tester.tap(find.text('Use: Phone note.'));
      await tester.pumpAndSettle();
      final meter = tester.widget<TextField>(find.byKey(const Key('meter')));
      expect(meter.controller!.text, '121.75');
      expect(valuesOf(await phone.fields())['meter'], 121.75);
      expect(valuesOf(await phone.fields())['notes'], 'Phone note.');
      expect(conflicts(await phone.fields()), isEmpty);
      await tester.ensureVisible(find.byKey(const Key('meter')));
      await capture(tester, key, 'conflict-preserved-meter');
      await tester.ensureVisible(find.text('Save work'));
      await tester.tap(find.text('Save work'));
      await tester.pumpAndSettle();
      expect(valuesOf(await phone.fields())['meter'], 121.75);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await office.update({'notes': 'Another office note.'});
      await phone.importOfficeBundle(await office.publicBundle());
      await tester.ensureVisible(find.text('Continue inspection'));
      await tester.tap(find.text('Continue inspection'));
      await tester.pumpAndSettle();
      expect(find.text('Use: Phone note.'), findsOneWidget);
      // A later saved update must not be silently overwritten by an older choice.
      await phone.update({'notes': 'Newer unseen note.'});
      await tester.ensureVisible(find.text('Use: Phone note.'));
      await tester.tap(find.text('Use: Phone note.'));
      await tester.pumpAndSettle();
      expect(conflicts(await phone.fields()), contains('notes'));
      expect(find.text('Use: Newer unseen note.'), findsOneWidget);
      await capture(tester, key, 'new-arrival-remains-conflict');
      await tester.ensureVisible(find.text('Use: Newer unseen note.'));
      await tester.tap(find.text('Use: Newer unseen note.'));
      await tester.pumpAndSettle();
      expect(conflicts(await phone.fields()), isEmpty);
      expect(valuesOf(await phone.fields())['meter'], 121.75);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await phone.close();
      await office.close();
      await root.delete(recursive: true);
    }
  });
  if (Platform.isLinux) {
    testWidgets(
      'Missing photo refreshes in place; return, correct and approve retain history',
      (tester) async {
        final root = await Directory.systemTemp.createTemp(
          'vortice-return-review-',
        );
        final office = await LabStore.open(
          Directory('${root.path}/office'),
          office: true,
        );
        Future<void> until(bool Function() done) async {
          final deadline = DateTime.now().add(const Duration(seconds: 12));
          while (!done()) {
            if (DateTime.now().isAfter(deadline)) {
              throw StateError('Review did not update.');
            }
            await Future<void>.delayed(const Duration(milliseconds: 200));
            await tester.pump();
          }
          await tester.pumpAndSettle();
        }

        Future<void> tap(String text) async {
          await tester.ensureVisible(find.text(text));
          await tester.tap(find.text(text));
          await tester.pumpAndSettle();
        }

        FilledButton approveButton() => tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Approve this version'),
        );
        try {
          await office.createWorkspace();
          await office.update({
            'fluid': 'pass',
            'guards': 'attention',
            'meter': 48.5,
            'notes': 'Initial inspection note.',
          });
          final recorder = ui.PictureRecorder();
          Canvas(recorder).drawRect(
            const Rect.fromLTWH(0, 0, 200, 100),
            Paint()..color = const Color(0xff103d3c),
          );
          final image = await recorder.endRecording().toImage(200, 100);
          final photoBytes = (await image.toByteData(
            format: ui.ImageByteFormat.png,
          ))!.buffer.asUint8List();
          image.dispose();
          final hash = await office.attach(photoBytes);
          await office.submit();
          await office.evidence.file(hash).delete();
          final key = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(
              key: key,
              child: LabApp(store: office, textScale: 2),
            ),
          );
          await tester.pumpAndSettle();
          await tap('Awaiting review');
          expect(approveButton().onPressed, isNull);
          expect(find.text('Waiting for the complete photo.'), findsOneWidget);
          await tester.ensureVisible(find.text('Approve this version'));
          await capture(tester, key, 'missing-photo-blocks-approval');
          await office.evidence.add(photoBytes);
          // Incoming evidence must make the already-open review usable.
          await until(() => approveButton().onPressed != null);
          await tap('Return with a reason');
          await tap('Continue');
          expect(find.text('Explain what needs to change.'), findsOneWidget);
          expect(office.receipts, isEmpty);
          await tap('Return with a reason');
          await tester.enterText(
            find.byType(TextField),
            'Please confirm the guard was secured.',
          );
          await tap('Continue');
          expect(office.receipts.single['decision'], 'returned');
          final returned = jsonEncode(office.receipts.single);
          await tester.ensureVisible(
            find.text('Returned: Please confirm the guard was secured.'),
          );
          await capture(tester, key, 'returned-with-reason');
          await tester.pageBack();
          await tester.pumpAndSettle();
          await tap('Open inspection');
          await tester.ensureVisible(find.byKey(const Key('notes')));
          await tester.enterText(
            find.byKey(const Key('notes')),
            'Guard secured and checked.',
          );
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pumpAndSettle();
          await tap('Submit for review');
          expect(office.submissions.length, 2);
          await tester.pageBack();
          await tester.pumpAndSettle();
          await until(() => find.text('Awaiting review').evaluate().isNotEmpty);
          await tap('Awaiting review');
          await tap('Approve this version');
          expect(office.receipts.length, 2);
          expect(jsonEncode(office.receipts.first), returned);
          expect(office.receipts.last['decision'], 'approved');
          await office.update({'notes': 'Later draft edit.'});
          expect(
            (office.receipts.last['values'] as Json)['notes'],
            'Guard secured and checked.',
          );
          await tester.pageBack();
          await tester.pumpAndSettle();
          await until(
            () => find
                .text('Returned — Please confirm the guard was secured.')
                .evaluate()
                .isNotEmpty,
          );
          await tap('Returned — Please confirm the guard was secured.');
          expect(find.text('Initial inspection note.'), findsOneWidget);
          await tester.ensureVisible(
            find.text('Returned: Please confirm the guard was secured.'),
          );
          await capture(tester, key, 'original-return-history');
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          await office.close();
          await root.delete(recursive: true);
        }
      },
    );
  }
}
