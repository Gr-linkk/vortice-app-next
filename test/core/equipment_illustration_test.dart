import 'dart:ui' as ui;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/core/equipment_art_catalog.dart';
import 'package:vortice_app/core/equipment_illustration.dart';
import 'package:vortice_app/core/theme.dart';

class _UnavailableArt extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      throw StateError('Unavailable art');
}

void main() {
  if (const bool.fromEnvironment('SAVE_EQUIPMENT_PROOFS')) {
    setUpAll(() async {
      const root = String.fromEnvironment('EQUIPMENT_PROOF_FONTS');
      if (root.isEmpty) return;
      final font = FontLoader('Roboto');
      for (final file in [
        'Roboto-Regular.ttf',
        'Roboto-Medium.ttf',
        'Roboto-Bold.ttf',
      ]) {
        font.addFont(
          Future.value(
            ByteData.sublistView(await File('$root/$file').readAsBytes()),
          ),
        );
      }
      await font.load();
    });
    for (final dark in [false, true]) {
      testWidgets('save equipment ${dark ? 'dark' : 'light'} proof', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(620, 1050));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final key = GlobalKey();
        final theme = dark ? AppTheme.darkTheme : AppTheme.lightTheme;
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: RepaintBoundary(
              key: key,
              child: Scaffold(
                appBar: AppBar(
                  title: Text('Equipment · ${dark ? 'Dark' : 'Light'}'),
                ),
                body: ListView(
                  children: [
                    for (final type in [
                      'Diesel genset',
                      'Pump',
                      'Motor Yacht',
                      'Sailing Yacht',
                    ])
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              EquipmentIllustration(typeName: type, size: 180),
                              const SizedBox(width: 20),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      type,
                                      style: theme.textTheme.titleLarge,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Equipment category illustration',
                                      style: theme.textTheme.bodySmall,
                                    ),
                                    const SizedBox(height: 18),
                                    EquipmentIllustration(
                                      typeName: type,
                                      size: 56,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.runAsync(
          () => precacheImage(
            const AssetImage(EquipmentArt.assetPath),
            key.currentContext!,
          ),
        );
        await tester.pumpAndSettle();
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1.5);
          final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
          final file = File(
            'outputs/ui-field-notes/equipment-${dark ? 'dark' : 'light'}.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(png.buffer.asUint8List());
          image.dispose();
        });
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final dark in [false, true]) {
    for (final type in [
      'Diesel genset',
      'RIB / Inflatable Boat',
      'Mobile Crane',
      'Tower Crane',
      'Davit',
    ]) {
      testWidgets(
        '$type linework renders without a paper box in ${dark ? 'dark' : 'light'}',
        (tester) async {
          final key = GlobalKey();
          final theme = dark ? AppTheme.darkTheme : AppTheme.lightTheme;
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: Scaffold(
                body: Center(
                  child: RepaintBoundary(
                    key: key,
                    child: ColoredBox(
                      color: theme.scaffoldBackgroundColor,
                      child: EquipmentIllustration(typeName: type, size: 240),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.runAsync(
            () => precacheImage(
              AssetImage(equipmentArtFor(typeName: type).imagePath),
              key.currentContext!,
            ),
          );
          await tester.pumpAndSettle();
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = (await tester.runAsync(() => boundary.toImage()))!;
          final pixels = (await tester.runAsync(() => image.toByteData()))!;
          final background = theme.scaffoldBackgroundColor;
          var ink = 0;
          for (var y = 0; y < image.height; y++) {
            for (var x = 0; x < image.width; x++) {
              final offset = (y * image.width + x) * 4;
              final matchesGround =
                  (pixels.getUint8(offset) - background.r * 255).abs() < 2 &&
                  (pixels.getUint8(offset + 1) - background.g * 255).abs() <
                      2 &&
                  (pixels.getUint8(offset + 2) - background.b * 255).abs() < 2;
              if (!matchesGround) ink++;
              if (x < 5 ||
                  x >= image.width - 5 ||
                  y < 5 ||
                  y >= image.height - 5) {
                expect(
                  matchesGround,
                  isTrue,
                  reason: 'No background box at $x,$y',
                );
              }
            }
          }
          expect(ink, greaterThan(500));
          expect(ink, lessThan(image.width * image.height * .6));
          image.dispose();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  test('all seeded types resolve without suffix collisions', () {
    final expected = [...EquipmentArt.values.take(12), EquipmentArt.other];
    for (var i = 1; i <= 13; i++) {
      final id =
          '00000000-0000-0000-0000-${i.toRadixString(16).padLeft(12, '0')}';
      expect(equipmentArtFor(assetTypeId: id), expected[i - 1]);
    }
    expect(
      equipmentArtFor(assetTypeId: 'f71f9098-b8fc-4730-bbbc-8a00c880000c'),
      EquipmentArt.other,
    );
    expect(equipmentArtFor(assetTypeId: '00c'), EquipmentArt.other);
  });

  test('custom IDs use catalog names, with safe unknown fallback', () {
    expect(
      equipmentArtFor(assetTypeId: 'custom', typeName: '  DIESEL   GENSET '),
      EquipmentArt.generator,
    );
    expect(equipmentArtFor(typeName: 'Ballast pump'), EquipmentArt.pump);
    expect(
      equipmentArtFor(typeName: 'Generator room inspection'),
      EquipmentArt.other,
    );
    expect(equipmentArtFor(typeName: 'unrecognized'), EquipmentArt.other);
    expect(equipmentArtFor(), EquipmentArt.other);
  });

  testWidgets('missing art remains bounded and provides category semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: DefaultAssetBundle(
          bundle: _UnavailableArt(),
          child: const Scaffold(
            body: EquipmentIllustration(typeName: 'Motor Yacht', size: 92),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.precision_manufacturing_outlined), findsOneWidget);
    expect(
      find.bySemanticsLabel('Category illustration: Motor yacht'),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byType(EquipmentIllustration)),
      const Size(92, 92),
    );
    semantics.dispose();
  });

  test(
    'bundled sheet has complete extractable subjects in all 16 crops',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final bytes = await rootBundle.load(EquipmentArt.assetPath);
      final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      final image = frame.image;
      expect(image.width, image.height);
      expect(image.width, EquipmentArt.sourceSize.toInt());
      final pixels = (await image.toByteData())!;
      for (final art in EquipmentArt.values.where((art) => art.file == null)) {
        final crop = art.sourceRect;
        var transparent = 0;
        var ink = 0;
        var edgeInk = 0;
        for (var y = 0; y < crop.height; y++) {
          for (var x = 0; x < crop.width; x++) {
            final px = crop.left.toInt() + x;
            final py = crop.top.toInt() + y;
            final offset = (py * image.width + px) * 4;
            final red = pixels.getUint8(offset);
            final blue = pixels.getUint8(offset + 2);
            // Same chroma extraction as the widget: neutral paper vanishes.
            final alpha = (blue - red) * 6 - 12;
            if (alpha <= 0) transparent++;
            if (alpha > 32) ink++;
            if (alpha > 80 &&
                (x < 2 ||
                    y < 2 ||
                    x >= crop.width - 2 ||
                    y >= crop.height - 2)) {
              edgeInk++;
            }
          }
        }
        expect(
          transparent,
          greaterThan(crop.width * crop.height * .1),
          reason: 'Transparent ground for ${art.name}',
        );
        expect(
          ink,
          greaterThan(crop.width * crop.height * .001),
          reason: 'Artwork for ${art.name}',
        );
        expect(edgeInk, 0, reason: 'Complete unclipped subject ${art.name}');
      }
      image.dispose();
      codec.dispose();
    },
  );
}
