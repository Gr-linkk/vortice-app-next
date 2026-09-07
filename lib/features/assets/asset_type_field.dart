import 'package:flutter/material.dart';
import 'package:vortice_app/core/app_dropdown_field.dart';
import 'package:vortice_app/core/equipment_art_catalog.dart';
import 'package:vortice_app/core/equipment_illustration.dart';
import 'package:vortice_app/features/assets/asset_type_provider.dart';
import 'package:vortice_app/l10n/app_localizations.dart';

/// The add/edit forms share the same stable-ID selection and category artwork.
class AssetTypeField extends StatelessWidget {
  const AssetTypeField({
    super.key,
    required this.types,
    required this.selectedId,
    required this.onChanged,
  });

  final List<AssetType> types;
  final String? selectedId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final spanish = Localizations.localeOf(context).languageCode == 'es';
    return AppDropdownField<String>(
      initialValue: selectedId,
      decoration: InputDecoration(labelText: l10n.assetType),
      items: [
        for (final type in types)
          DropdownMenuItem(
            value: type.id,
            child: Row(
              children: [
                EquipmentIllustration(
                  assetTypeId: type.id,
                  typeName: type.name,
                  size: 48,
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(_label(type, spanish))),
              ],
            ),
          ),
      ],
      onChanged: onChanged,
      validator: (value) => value == null ? l10n.fieldRequired : null,
    );
  }

  String _label(AssetType type, bool spanish) {
    final art = equipmentArtFor(assetTypeId: type.id, typeName: type.name);
    // Keep owner-defined catalog names rather than relabeling unknown types.
    return spanish && art != EquipmentArt.other ? art.spanishLabel : type.name;
  }
}
