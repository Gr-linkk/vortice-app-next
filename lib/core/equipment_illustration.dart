import 'package:flutter/material.dart';
import 'package:vortice_app/core/equipment_art_catalog.dart';
import 'package:vortice_app/core/theme.dart';

/// Offline equipment artwork with a transparent ground in either theme.
class EquipmentIllustration extends StatelessWidget {
  const EquipmentIllustration({
    super.key,
    this.assetTypeId,
    this.typeName,
    this.size = 72,
  }) : assert(size > 0);

  final String? assetTypeId;
  final String? typeName;
  final double size;

  @override
  Widget build(BuildContext context) {
    final art = equipmentArtFor(assetTypeId: assetTypeId, typeName: typeName);
    final spanish = Localizations.localeOf(context).languageCode == 'es';
    final color = context.appColors.textPrimary;
    final crop = art.sourceRect;
    final scale = size * .92 / crop.longestSide;
    final sheetSize = EquipmentArt.sourceSize * scale;
    return Semantics(
      image: true,
      label: spanish
          ? 'Ilustración de categoría: ${art.spanishLabel}'
          : 'Category illustration: ${art.label}',
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: size,
          child: Center(
            child: SizedBox(
              width: crop.width * scale,
              height: crop.height * scale,
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  minWidth: sheetSize,
                  maxWidth: sheetSize,
                  minHeight: sheetSize,
                  maxHeight: sheetSize,
                  child: Transform.translate(
                    offset: Offset(-crop.left * scale, -crop.top * scale),
                    child: ColorFiltered(
                      // Extract teal ink from neutral paper. Unlike a white color
                      // key this also preserves antialiased fine lines and makes
                      // the ground completely transparent in the dark theme.
                      colorFilter: ColorFilter.matrix([
                        0,
                        0,
                        0,
                        0,
                        color.r * 255,
                        0,
                        0,
                        0,
                        0,
                        color.g * 255,
                        0,
                        0,
                        0,
                        0,
                        color.b * 255,
                        -6,
                        0,
                        6,
                        0,
                        -12,
                      ]),
                      child: Image.asset(
                        EquipmentArt.assetPath,
                        width: sheetSize,
                        height: sheetSize,
                        fit: BoxFit.fill,
                        filterQuality: FilterQuality.medium,
                        errorBuilder: (context, error, stackTrace) =>
                            Transform.translate(
                              offset: Offset(
                                crop.left * scale,
                                crop.top * scale,
                              ),
                              child: Align(
                                alignment: Alignment.topLeft,
                                child: SizedBox(
                                  width: crop.width * scale,
                                  height: crop.height * scale,
                                  child: Icon(
                                    Icons.precision_manufacturing_outlined,
                                    size: crop.shortestSide * scale * .65,
                                    color: const Color(0xFF164F58),
                                  ),
                                ),
                              ),
                            ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
