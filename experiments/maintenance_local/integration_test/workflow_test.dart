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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Rendered ordinary phone work, large text, saved restart and 30-day disconnection',
    (tester) async {
      await RustLib.init();
      final captureKey = GlobalKey();
      Future<void> capture(String name) async {
        await tester.pumpAndSettle();
        final boundary =
            captureKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final data = (await image.toByteData(
          format: ui.ImageByteFormat.png,
        ))!.buffer.asUint8List();
        image.dispose();
        final output = Directory(
          '${(await getApplicationSupportDirectory()).path}/workflow-acceptance/screenshots',
        );
        await output.create(recursive: true);
        await File('${output.path}/$name.png').writeAsBytes(data, flush: true);
      }

      final appRoot = await getApplicationSupportDirectory();
      final root = Directory('${appRoot.path}/workflow-acceptance');
      if (await root.exists()) await root.delete(recursive: true);
      final office = await LabStore.open(
        Directory('${root.path}/office-fixture'),
        office: true,
      );
      await office.createWorkspace();
      var phone = await LabStore.open(
        Directory('${root.path}/phone'),
        office: false,
      );
      await phone.importOfficeBundle(await office.publicBundle());
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 640, 400),
        Paint()..color = const Color(0xffe4ece6),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(80, 120, 480, 160),
          const Radius.circular(20),
        ),
        Paint()..color = const Color(0xff103d3c),
      );
      final painter = TextPainter(
        text: const TextSpan(
          text: 'SYNTHETIC INSPECTION\nDEMO GENERATOR',
          style: TextStyle(color: Colors.white, fontSize: 28),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 450);
      painter.paint(canvas, const Offset(100, 165));
      final image = await recorder.endRecording().toImage(640, 400);
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.png,
      ))!.buffer.asUint8List();
      image.dispose();
      await phone.attach(bytes);
      await tester.pumpWidget(
        RepaintBoundary(
          key: captureKey,
          child: LabApp(store: phone),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Demo generator'), findsOneWidget);
      await tester.ensureVisible(find.text('Continue inspection'));
      await tester.tap(find.text('Continue inspection'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Pass').first);
      await tester.tap(find.text('Pass').first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Needs attention').last);
      await tester.tap(find.text('Needs attention').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('meter')));
      await tester.enterText(find.byKey(const Key('meter')), '125.5');
      await tester.ensureVisible(find.byKey(const Key('notes')));
      await tester.enterText(
        find.byKey(const Key('notes')),
        'Synthetic check: secure the loose guard.',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save work'));
      await tester.tap(find.text('Save work'));
      await tester.pumpAndSettle();
      expect(valuesOf(await phone.fields())['meter'], 125.5);
      await tester.ensureVisible(find.text('Submit for review'));
      await tester.tap(find.text('Submit for review'));
      await tester.pumpAndSettle();
      expect(phone.submissions.length, 1);
      expect(find.text('Saved on this phone—waiting to send.'), findsOneWidget);
      final id = phone.submissions.single['id'];
      final photo = valuesOf(await phone.fields())['photo'] as String;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await phone.close();
      phone = await LabStore.open(
        Directory('${root.path}/phone'),
        office: false,
        now: () => DateTime.now().add(const Duration(days: 30)),
      );
      expect(phone.submissions.single['id'], id);
      expect(await phone.evidence.complete(photo), isTrue);
      await tester.pumpWidget(
        RepaintBoundary(
          key: captureKey,
          child: LabApp(store: phone),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Continue inspection'));
      await tester.tap(find.text('Continue inspection'));
      await tester.pumpAndSettle();
      expect(find.text('125.5'), findsOneWidget);
      await capture('inspection-normal');
      await tester.pumpWidget(
        RepaintBoundary(
          key: captureKey,
          child: LabApp(store: phone, textScale: 2),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture('inspection-large-text');
      await tester.ensureVisible(find.text('Submit for review'));
      await tester.tap(find.text('Submit for review'));
      await tester.pumpAndSettle();
      expect(phone.submissions.length, 1);
      expect(tester.takeException(), isNull);
      await File('${root.path}/result.json').writeAsString(
        jsonEncode({
          'device': Platform.operatingSystem,
          'submission': id,
          'photo': photo,
          'meter': 125.5,
          'simulatedOfflineDays': 30,
          'largeText': 2,
          'passed': true,
        }),
        flush: true,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await phone.close();
      await office.close();
    },
  );
}
