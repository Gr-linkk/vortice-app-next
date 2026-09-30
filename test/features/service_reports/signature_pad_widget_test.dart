import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/service_reports/service_report_action_bar.dart';
import 'package:vortice_app/features/service_reports/service_report_signature_sheet.dart';
import 'package:vortice_app/features/service_reports/signature_pad_widget.dart';
import 'package:vortice_app/l10n/app_localizations.dart';

import '../fleet/fleet_test_support.dart' show captureFleet;

Widget app({
  required Future<void> Function(Uint8List) save,
  double scale = 1,
  bool dark = false,
  String language = 'en',
}) => RepaintBoundary(
  key: const Key('fleet-capture'),
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
    locale: Locale(language),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: Builder(
      builder: (context) => Scaffold(
        appBar: AppBar(title: const Text('Service report')),
        body: const Center(child: Text('Pressure seal replaced and checked.')),
        bottomNavigationBar: ServiceReportActionBar(
          signatureSaved: false,
          isLoading: false,
          canSubmit: true,
          onOpenSignature: () =>
              showServiceReportSignatureSheet(context: context, onSave: save),
          onSubmit: () {},
        ),
      ),
    ),
  ),
);

Future<void> draw(WidgetTester tester, {double y = 50}) async {
  final origin = tester.getTopLeft(find.byKey(const ValueKey('signature-ink')));
  final gesture = await tester.startGesture(origin + Offset(30, y));
  await gesture.moveBy(const Offset(45, 15));
  await gesture.moveBy(const Offset(35, -25));
  await gesture.moveBy(const Offset(40, 20));
  await gesture.up();
  await tester.pump();
}

void main() {
  setUpAll(() async {
    if (kIsWeb) return;
    await (FontLoader('Roboto')
          ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf')))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  for (final variant in [(1.0, false, 'en'), (2.0, true, 'fr')]) {
    testWidgets(
      'signature workflow at ${variant.$1}x, ${variant.$3}, dark ${variant.$2}',
      (tester) async {
        tester.view.physicalSize = const Size(412, 915);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        late final Completer<Uint8List> saved;
        await tester.pumpWidget(
          app(
            scale: variant.$1,
            dark: variant.$2,
            language: variant.$3,
            save: (bytes) async => saved.complete(bytes),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.draw_outlined));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<ElevatedButton>(
                find.widgetWithIcon(ElevatedButton, Icons.check),
              )
              .onPressed,
          isNull,
        );
        await draw(tester);
        await tester.tap(find.byIcon(Icons.clear));
        await tester.pump();
        expect(
          tester
              .widget<ElevatedButton>(
                find.widgetWithIcon(ElevatedButton, Icons.check),
              )
              .onPressed,
          isNull,
        );
        await draw(tester, y: 120);
        expect(
          tester
              .widget<ElevatedButton>(
                find.widgetWithIcon(ElevatedButton, Icons.check),
              )
              .onPressed,
          isNotNull,
        );
        if (!kIsWeb) {
          await captureFleet(tester, 'signature-${variant.$1}-${variant.$3}');
        }
        final inkSize = tester.getSize(
          find.byKey(const ValueKey('signature-ink')),
        );
        await tester.runAsync(() async {
          saved = Completer<Uint8List>();
          await tester.tap(find.byIcon(Icons.check));
          final png = await saved.future.timeout(const Duration(seconds: 10));
          expect(png.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
          final codec = await ui.instantiateImageCodec(png);
          final frame = await codec.getNextFrame();
          final image = frame.image;
          expect(image.width, greaterThan(600));
          expect(image.height, (inkSize.height * 2).ceil());
          final pixels = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!.buffer.asUint8List();
          var ink = 0;
          var oldInk = 0;
          for (var y = 0; y < image.height; y++) {
            for (var x = 0; x < image.width; x++) {
              final p = (y * image.width + x) * 4;
              expect(pixels[p + 3], 255);
              if (pixels[p] < 100) {
                ink++;
                if (y < 180) oldInk++;
              }
            }
          }
          expect(
            ink,
            greaterThan(100),
            reason: 'The PNG must contain visible ink.',
          );
          expect(
            oldInk,
            0,
            reason: 'Clear must remove the old stroke from exported bytes.',
          );
          expect(pixels.take(4), [255, 255, 255, 255]);
          image.dispose();
          codec.dispose();
        });
        await tester.pumpAndSettle();
        expect(find.byType(SignaturePadWidget), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('save failure keeps the signature and allows retry', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      app(
        save: (_) async {
          calls++;
          if (calls == 1) throw StateError('Disk unavailable');
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.draw_outlined));
    await tester.pumpAndSettle();
    await draw(tester);
    for (var attempt = 0; attempt < 2; attempt++) {
      await tester.runAsync(() async {
        await tester.tap(find.byIcon(Icons.check));
        // Wait for PNG encoding and the UI callback; no test clock is advanced.
        for (var i = 0; calls <= attempt && i < 100; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();
      expect(calls, attempt + 1);
      if (attempt == 0) {
        expect(find.byType(SignaturePadWidget), findsOneWidget);
        expect(
          tester
              .widget<ElevatedButton>(
                find.widgetWithIcon(ElevatedButton, Icons.check),
              )
              .onPressed,
          isNotNull,
        );
        // Clear the transient failure message so the retry button is reachable.
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
      }
    }
    expect(find.byType(SignaturePadWidget), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
