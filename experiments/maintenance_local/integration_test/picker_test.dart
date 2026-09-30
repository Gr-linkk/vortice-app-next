import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:maintenance_local/qr_scanner.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Native Android photo selection returns an invitation decoded entirely on device',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: Text(
                'Choose Vortice-Lab-Invitation.png in the photo picker.',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final picked = await ImagePicker()
          .pickImage(source: ImageSource.gallery, requestFullMetadata: false)
          .timeout(const Duration(minutes: 3));
      expect(picked, isNotNull);
      final text = await decodeInvitationImage(await picked!.readAsBytes());
      expect(text, contains('synthetic-single-use'));
      final base = await getApplicationSupportDirectory();
      await File('${base.path}/picker-result.json').writeAsString(
        jsonEncode({
          'passed': true,
          'nativePhotoPicker': true,
          'offlineQrDecode': true,
        }),
        flush: true,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
