import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:zxing2/qrcode.dart';

/// Decodes a captured invitation locally; there is no hosted scanner or ML SDK.
Future<String?> decodeInvitationImage(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(
    bytes,
    targetWidth: 1280,
    allowUpscaling: false,
  );
  final frame = await codec.getNextFrame();
  codec.dispose();
  final image = frame.image;
  try {
    final rgba = (await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();
    final pixels = Int32List(image.width * image.height);
    for (var i = 0; i < pixels.length; i++) {
      pixels[i] =
          (rgba[i * 4] << 16) | (rgba[i * 4 + 1] << 8) | rgba[i * 4 + 2];
    }
    final source = RGBLuminanceSource(image.width, image.height, pixels);
    try {
      final result = QRCodeReader().decode(
        BinaryBitmap(HybridBinarizer(source)),
      );
      return result.text.contains('"invitation"') ? result.text : null;
    } catch (_) {
      return null;
    }
  } finally {
    image.dispose();
  }
}

class InvitationScanner extends StatefulWidget {
  const InvitationScanner({super.key});
  @override
  State<InvitationScanner> createState() => _InvitationScannerState();
}

class _InvitationScannerState extends State<InvitationScanner> {
  bool busy = false;
  String? message;
  Future<void> capture(ImageSource source) async {
    setState(() => busy = true);
    try {
      final file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1280,
        imageQuality: 95,
      );
      if (file == null) return;
      final code = await decodeInvitationImage(await file.readAsBytes());
      if (!mounted) return;
      if (code == null) {
        setState(
          () => message =
              'No invitation code found. Take a closer, clear photo of the full code, or paste the invitation from the previous screen.',
        );
      } else {
        Navigator.pop(context, code);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => message =
              'The invitation photo could not be read. Try again or paste the invitation from the previous screen.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scan computer invitation')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Choose a saved image of the complete computer invitation, or photograph it if your camera works. The code is read on this phone. You can also go back and paste the invitation text. Then compare the confirmation code on both devices.',
            ),
            const SizedBox(height: 20),
            if (message != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Text(message!),
              ),
            FilledButton.icon(
              onPressed: busy ? null : () => capture(ImageSource.gallery),
              icon: const Icon(Icons.image_outlined),
              label: const Text('Choose invitation image'),
            ),
            OutlinedButton(
              onPressed: busy ? null : () => capture(ImageSource.camera),
              child: const Text('Photograph invitation'),
            ),
          ],
        ),
      ),
    ),
  );
}
