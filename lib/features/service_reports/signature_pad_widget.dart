import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_signaturepad/signaturepad.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/core/theme.dart';

class SignaturePadWidget extends StatefulWidget {
  /// Called with the captured PNG bytes when the user taps "Save".
  final Future<void> Function(Uint8List pngBytes) onSave;

  const SignaturePadWidget({super.key, required this.onSave});

  @override
  State<SignaturePadWidget> createState() => _SignaturePadWidgetState();
}

class _SignaturePadWidgetState extends State<SignaturePadWidget> {
  final GlobalKey<SfSignaturePadState> _signaturePadKey =
      GlobalKey<SfSignaturePadState>();
  bool _saving = false;

  bool get _isEmpty => _signaturePadKey.currentState == null;

  void _clear() {
    _signaturePadKey.currentState?.clear();
  }

  Future<void> _save() async {
    if (_isEmpty) return;
    setState(() => _saving = true);
    try {
      final image = await _signaturePadKey.currentState!.toImage();
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) {
        await widget.onSave(byteData.buffer.asUint8List());
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 200,
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.divider),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SfSignaturePad(
              key: _signaturePadKey,
              backgroundColor: AppColors.surfaceVariant,
              strokeColor: AppColors.textPrimary,
              minimumStrokeWidth: 1.5,
              maximumStrokeWidth: 4.0,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            TextButton.icon(
              onPressed: _isEmpty ? null : _clear,
              icon: const Icon(Icons.clear, size: 16),
              label: Text(l10n.clearSignature),
            ),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: (_isEmpty || _saving) ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.check, size: 16),
              label: Text(l10n.saveSignature),
              style: ElevatedButton.styleFrom(
                minimumSize: Size.zero,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
