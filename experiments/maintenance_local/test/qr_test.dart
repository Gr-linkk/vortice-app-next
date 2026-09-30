import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:maintenance_local/qr_scanner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'A captured invitation image decodes locally without a hosted scanner',
    () async {
      const text =
          '{"v":1,"url":"https://192.168.1.2:47831","invitation":"synthetic-single-use"}';
      final painter = QrPainter(
        data: text,
        version: QrVersions.auto,
        gapless: true,
        eyeStyle: const QrEyeStyle(color: Colors.black),
        dataModuleStyle: const QrDataModuleStyle(color: Colors.black),
      );
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 320, 320),
        Paint()..color = Colors.white,
      );
      canvas.translate(20, 20);
      painter.paint(canvas, const Size(280, 280));
      final image = await recorder.endRecording().toImage(320, 320);
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.png,
      ))!.buffer.asUint8List();
      image.dispose();
      expect(await decodeInvitationImage(bytes), text);
      final fixture = File('../../outputs/next011/fixtures/invitation.png');
      await fixture.parent.create(recursive: true);
      await fixture.writeAsBytes(bytes);
    },
  );
}
