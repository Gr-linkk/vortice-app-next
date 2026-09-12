import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/core/equipment_art_catalog.dart';
import 'package:vortice_app/core/equipment_illustration.dart';
import 'package:vortice_app/core/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final catalog =
      (jsonDecode(File('seed/asset-types.json').readAsStringSync()) as List)
          .cast<Map<String, dynamic>>();

  test('every standard catalog type has its own stable ID and artwork', () {
    expect(catalog, hasLength(40));
    expect(catalog.map((row) => row['id']).toSet(), hasLength(catalog.length));
    final drawings = <EquipmentArt>{};
    for (final row in catalog) {
      final art = equipmentArtFor(assetTypeId: row['id'] as String);
      expect(
        equipmentArtFor(typeName: row['name'] as String),
        art,
        reason: '${row['name']} must resolve by ID and name consistently',
      );
      if (row['name'] != 'Custom / Other') {
        expect(art, isNot(EquipmentArt.other), reason: '${row['name']}');
      }
      drawings.add(art);
    }
    expect(drawings, hasLength(catalog.length));
  });

  test('new drawings are bundled, extractable and complete', () async {
    for (final art in EquipmentArt.values.where((art) => art.file != null)) {
      final bytes = await rootBundle.load(art.imagePath);
      final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
      final image = (await codec.getNextFrame()).image;
      expect(image.width, EquipmentArt.sourceSize, reason: art.name);
      expect(image.height, EquipmentArt.sourceSize, reason: art.name);
      final pixels = (await image.toByteData())!;
      var ink = 0;
      var edgeInk = 0;
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          final offset = (y * image.width + x) * 4;
          final alpha =
              (pixels.getUint8(offset + 2) - pixels.getUint8(offset)) * 6 - 12;
          if (alpha > 32) ink++;
          if (alpha > 80 &&
              (x < 2 ||
                  y < 2 ||
                  x >= image.width - 2 ||
                  y >= image.height - 2)) {
            edgeInk++;
          }
        }
      }
      expect(
        ink,
        greaterThan(image.width * image.height * .005),
        reason: 'Visible drawing for ${art.name}',
      );
      expect(
        ink,
        lessThan(image.width * image.height * .5),
        reason: 'Open ground and interiors for ${art.name}',
      );
      expect(edgeInk, 0, reason: 'Unclipped complete drawing for ${art.name}');
      image.dispose();
      codec.dispose();
    }
  });

  if (const bool.fromEnvironment('SAVE_EQUIPMENT_PROOFS')) {
    setUpAll(() async {
      final font = FontLoader('Roboto');
      for (final file in ['Roboto-Regular.ttf', 'Roboto-Bold.ttf']) {
        font.addFont(rootBundle.load('assets/fonts/$file'));
      }
      await font.load();
    });
    for (final dark in [false, true]) {
      for (var page = 0; page < (catalog.length / 8).ceil(); page++) {
        testWidgets('catalog ${dark ? 'dark' : 'light'} page $page', (
          tester,
        ) async {
          tester.view.physicalSize = const Size(720, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final key = GlobalKey();
          final rows = catalog.skip(page * 8).take(8).toList();
          await tester.pumpWidget(
            MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
              home: RepaintBoundary(
                key: key,
                child: Scaffold(
                  appBar: AppBar(
                    title: Text('Equipment · ${dark ? 'Dark' : 'Light'}'),
                  ),
                  body: GridView.count(
                    padding: const EdgeInsets.all(12),
                    crossAxisCount: 2,
                    childAspectRatio: 1.55,
                    children: [
                      for (final row in rows)
                        Card(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              EquipmentIllustration(
                                assetTypeId: row['id'] as String,
                                size: 158,
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                child: Text(
                                  row['name'] as String,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.runAsync(() async {
            for (final row in rows) {
              final art = equipmentArtFor(assetTypeId: row['id'] as String);
              await precacheImage(
                AssetImage(art.imagePath),
                key.currentContext!,
              );
            }
          });
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.runAsync(() async {
            final boundary =
                key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage();
            final bytes = (await image.toByteData(
              format: ui.ImageByteFormat.png,
            ))!;
            final file = File(
              'outputs/NOW018/catalog-${dark ? 'dark' : 'light'}-$page.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes.buffer.asUint8List());
            image.dispose();
          });
        });
      }
    }
  }
}
