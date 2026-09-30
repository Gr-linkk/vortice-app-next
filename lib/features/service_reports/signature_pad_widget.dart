import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:vortice_app/core/localized_text.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/l10n/app_localizations.dart';

/// Small, in-app ink capture. No vendor runtime or licensing service is needed.
class SignaturePadWidget extends StatefulWidget {
  const SignaturePadWidget({super.key, required this.onSave});

  /// Saves a black-on-white PNG, independent of the application's colour theme.
  final Future<void> Function(Uint8List pngBytes) onSave;

  @override
  State<SignaturePadWidget> createState() => _SignaturePadWidgetState();
}

class _SignaturePadWidgetState extends State<SignaturePadWidget> {
  final _strokes = <List<Offset>>[];
  Size _size = Size.zero;
  bool _saving = false, _drawing = false;

  Offset _point(Offset position) => Offset(
    (position.dx / _size.width).clamp(0, 1),
    (position.dy / _size.height).clamp(0, 1),
  );

  Future<void> _save() async {
    if (_strokes.isEmpty || _saving || _drawing) return;
    setState(() => _saving = true);
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)..scale(2);
      canvas.drawRect(Offset.zero & _size, Paint()..color = Colors.white);
      _SignaturePainter(_strokes, Colors.black).paint(canvas, _size);
      final picture = recorder.endRecording();
      final ui.Image image;
      try {
        image = await picture.toImage(
          (_size.width * 2).ceil(),
          (_size.height * 2).ceil(),
        );
      } finally {
        picture.dispose();
      }
      final ByteData? bytes;
      try {
        bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      } finally {
        image.dispose();
      }
      if (bytes == null) throw StateError('Could not capture the signature.');
      await widget.onSave(bytes.buffer.asUint8List());
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(context, error))));
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
        Semantics(
          label: l10n.technicianSignature,
          hint: localizedText(
            context,
            'Draw your signature here, then save.',
            'Dibuja tu firma aquí y guárdala.',
            'Signez ici, puis enregistrez.',
          ),
          child: Container(
            height: 200,
            decoration: BoxDecoration(
              color: context.appColors.surfaceVariant,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: context.appColors.divider),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _size = constraints.biggest;
                  return GestureDetector(
                    key: const ValueKey('signature-ink'),
                    behavior: HitTestBehavior.opaque,
                    dragStartBehavior: DragStartBehavior.down,
                    onPanStart: _saving
                        ? null
                        : (details) => setState(() {
                            _drawing = true;
                            _strokes.add([_point(details.localPosition)]);
                          }),
                    onPanUpdate: _saving
                        ? null
                        : (details) => setState(() {
                            _strokes.last.add(_point(details.localPosition));
                          }),
                    onPanEnd: _saving
                        ? null
                        : (_) => setState(() => _drawing = false),
                    onPanCancel: _saving
                        ? null
                        : () => setState(() {
                            if (_drawing) _strokes.removeLast();
                            _drawing = false;
                          }),
                    child: CustomPaint(
                      painter: _SignaturePainter(
                        _strokes,
                        context.appColors.textPrimary,
                      ),
                      size: Size.infinite,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 12,
          runSpacing: 8,
          children: [
            TextButton.icon(
              onPressed: _strokes.isEmpty || _saving || _drawing
                  ? null
                  : () => setState(_strokes.clear),
              icon: const Icon(Icons.clear, size: 16),
              label: Text(l10n.clearSignature),
            ),
            ElevatedButton.icon(
              onPressed: _strokes.isEmpty || _saving || _drawing ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check, size: 16),
              label: Text(l10n.saveSignature),
            ),
          ],
        ),
      ],
    );
  }
}

class _SignaturePainter extends CustomPainter {
  const _SignaturePainter(this.strokes, this.color);
  final List<List<Offset>> strokes;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final ink = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;
      final points = stroke
          .map((p) => Offset(p.dx * size.width, p.dy * size.height))
          .toList();
      if (points.length == 1) {
        canvas.drawPoints(ui.PointMode.points, points, ink);
      } else {
        final path = Path()..moveTo(points.first.dx, points.first.dy);
        for (final point in points.skip(1)) {
          path.lineTo(point.dx, point.dy);
        }
        canvas.drawPath(path, ink);
      }
    }
  }

  // The small active ink buffer is mutated in place on each pointer update.
  @override
  bool shouldRepaint(_SignaturePainter oldDelegate) => true;
}
