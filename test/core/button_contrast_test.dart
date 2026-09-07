import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/core/theme.dart';

double contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return (x > y ? x + .05 : y + .05) / (x > y ? y + .05 : x + .05);
}

void main() {
  for (final dark in [false, true]) {
    for (final kind in [
      'filled',
      'elevated',
      'success',
      'error',
      'outlined',
      'text',
    ]) {
      testWidgets('$kind button label contrast in dark=$dark', (tester) async {
        final theme = dark ? AppTheme.darkTheme : AppTheme.lightTheme;
        final palette = theme.extension<AppPalette>()!;
        const label = Text('Save asset');
        final Widget button = switch (kind) {
          'filled' => FilledButton(onPressed: () {}, child: label),
          'outlined' => OutlinedButton(onPressed: () {}, child: label),
          'text' => TextButton(onPressed: () {}, child: label),
          _ => ElevatedButton(
            onPressed: () {},
            style: ElevatedButton.styleFrom(
              backgroundColor: kind == 'success'
                  ? palette.success
                  : kind == 'error'
                  ? palette.error
                  : null,
            ),
            child: label,
          ),
        };
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(body: button),
          ),
        );
        void check() {
          final text = tester.renderObject<RenderParagraph>(
            find.text('Save asset'),
          );
          final material = tester.widget<Material>(
            find
                .descendant(
                  of: find.byWidget(button),
                  matching: find.byType(Material),
                )
                .first,
          );
          final background = Color.alphaBlend(
            material.color ?? Colors.transparent,
            palette.background,
          );
          expect(
            contrast(text.text.style!.color!, background),
            greaterThanOrEqualTo(4.5),
          );
        }

        check();
        final gesture = await tester.startGesture(
          tester.getCenter(find.text('Save asset')),
        );
        await tester.pump(const Duration(milliseconds: 150));
        check();
        await gesture.up();
        await tester.pumpAndSettle();
        check();
      });
    }
    for (final overrideBackground in [false, true]) {
      testWidgets(
        'FAB label and icon remain readable: dark=$dark override=$overrideBackground',
        (tester) async {
          final theme = dark ? AppTheme.darkTheme : AppTheme.lightTheme;
          final palette = theme.extension<AppPalette>()!;
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: Scaffold(
                floatingActionButton: FloatingActionButton.extended(
                  onPressed: () {},
                  backgroundColor: overrideBackground ? palette.primary : null,
                  icon: const Icon(Icons.add),
                  label: const Text('Add asset'),
                ),
              ),
            ),
          );
          void check() {
            final text = tester.renderObject<RenderParagraph>(
              find.text('Add asset'),
            );
            final material = tester.widget<Material>(
              find
                  .descendant(
                    of: find.byType(FloatingActionButton),
                    matching: find.byType(Material),
                  )
                  .first,
            );
            expect(
              contrast(text.text.style!.color!, material.color!),
              greaterThanOrEqualTo(4.5),
            );
            final icon = tester.element(find.byIcon(Icons.add));
            expect(
              contrast(IconTheme.of(icon).color!, material.color!),
              greaterThanOrEqualTo(3),
            );
          }

          check();
          final gesture = await tester.startGesture(
            tester.getCenter(find.text('Add asset')),
          );
          await tester.pump(const Duration(milliseconds: 150));
          check();
          await gesture.up();
          await tester.pumpAndSettle();
          check();
        },
      );
    }
  }
}
