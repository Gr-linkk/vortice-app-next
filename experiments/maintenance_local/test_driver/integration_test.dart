import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      final dir = Directory(
        Platform.environment['VORTICE_LAB_EVIDENCE'] ??
            '../../outputs/next011/rendered',
      );
      await dir.create(recursive: true);
      await File('${dir.path}/$name.png').writeAsBytes(bytes);
      return true;
    },
  );
}
