import 'package:flutter/material.dart';
import 'package:vortice_app/core/list_group_heading.dart';
import 'package:vortice_app/core/equipment_art_catalog.dart';
import 'package:vortice_app/core/equipment_illustration.dart';
import 'package:vortice_app/features/assets/asset_type_provider.dart';
import 'package:vortice_app/l10n/app_localizations.dart';

/// Search the same catalog in Add and Edit; selection always returns its ID.
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
    return FormField<String>(
      key: ValueKey(selectedId),
      initialValue: selectedId,
      validator: (value) => value == null ? l10n.fieldRequired : null,
      builder: (field) {
        final selected = types
            .where((type) => type.id == field.value)
            .firstOrNull;
        final label = selected == null
            ? field.value == null
                  ? (spanish
                        ? 'Elegir tipo de equipo'
                        : 'Choose equipment type')
                  : (spanish
                        ? 'Tipo de equipo actual'
                        : 'Current equipment type')
            : assetTypeLabel(selected, spanish);
        return Semantics(
          button: true,
          label: '${l10n.assetType}: $label',
          child: InkWell(
            key: const ValueKey('asset-type-picker'),
            borderRadius: BorderRadius.circular(12),
            onTap: () async {
              final choice = await showDialog<AssetType>(
                context: context,
                builder: (_) => Dialog.fullscreen(
                  child: _AssetTypePicker(
                    types: types,
                    selectedId: field.value,
                  ),
                ),
              );
              if (choice == null || !field.mounted) return;
              field.didChange(choice.id);
              onChanged(choice.id);
            },
            child: InputDecorator(
              isEmpty: false,
              decoration: InputDecoration(
                labelText: l10n.assetType,
                errorText: field.errorText,
              ),
              child: Row(
                children: [
                  if (selected != null) ...[
                    ExcludeSemantics(
                      child: EquipmentIllustration(
                        assetTypeId: selected.id,
                        typeName: selected.name,
                        size: 48,
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(child: Text(label)),
                  const SizedBox(width: 8),
                  const Icon(Icons.search),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

String assetTypeLabel(AssetType type, bool spanish) {
  final art = equipmentArtFor(assetTypeId: type.id, typeName: type.name);
  return spanish && art != EquipmentArt.other ? art.spanishLabel : type.name;
}

String _categoryLabel(String category, bool spanish) => !spanish
    ? category
    : switch (category) {
        'Marine Vessels' => 'Embarcaciones',
        'Commercial Fishing' => 'Pesca comercial',
        'Dredging Equipment' => 'Equipos de dragado',
        'Heavy Equipment' => 'Maquinaria pesada',
        'Power Generation' => 'Generación eléctrica',
        'Industrial Equipment' => 'Equipos industriales',
        'Lifting Equipment' => 'Equipos de elevación',
        'Road Vehicles' => 'Vehículos de carretera',
        'Agriculture & Grounds' => 'Agricultura y áreas verdes',
        'Other' => 'Otros',
        _ => category,
      };

class _AssetTypePicker extends StatefulWidget {
  const _AssetTypePicker({required this.types, required this.selectedId});
  final List<AssetType> types;
  final String? selectedId;
  @override
  State<_AssetTypePicker> createState() => _AssetTypePickerState();
}

class _AssetTypePickerState extends State<_AssetTypePicker> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final spanish = Localizations.localeOf(context).languageCode == 'es';
    final matches = widget.types.where((type) {
      final category = type.category.trim().isEmpty
          ? 'Other'
          : type.category.trim();
      final text =
          '${type.name} ${assetTypeLabel(type, true)} $category ${_categoryLabel(category, true)}'
              .toLowerCase();
      return _query
          .trim()
          .toLowerCase()
          .split(RegExp(r'\s+'))
          .every(text.contains);
    }).toList();
    final groups = <String, List<AssetType>>{};
    for (final type in matches) {
      final category = type.category.trim().isEmpty
          ? 'Other'
          : type.category.trim();
      groups.putIfAbsent(category, () => []).add(type);
    }
    final categories = groups.keys.toList()
      ..sort((a, b) {
        if (a == 'Other') return b == 'Other' ? 0 : 1;
        if (b == 'Other') return -1;
        return _categoryLabel(
          a,
          spanish,
        ).toLowerCase().compareTo(_categoryLabel(b, spanish).toLowerCase());
      });
    final entries = <Object>[];
    for (final category in categories) {
      final types = groups[category]!
        ..sort(
          (a, b) => assetTypeLabel(
            a,
            spanish,
          ).toLowerCase().compareTo(assetTypeLabel(b, spanish).toLowerCase()),
        );
      entries.add(category);
      entries.addAll(types);
    }
    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: Text(AppLocalizations.of(context).assetType),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                key: const ValueKey('asset-type-search'),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  labelText: spanish ? 'Buscar tipos' : 'Search types',
                  prefixIcon: const Icon(Icons.search),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Expanded(
              child: matches.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          spanish
                              ? 'No hay tipos coincidentes. Prueba otro nombre o categoría.'
                              : 'No matching types. Try another name or category.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.builder(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        if (entry is String) {
                          return ListGroupHeading(
                            key: ValueKey('asset-category-$entry'),
                            label: _categoryLabel(entry, spanish),
                            count: groups[entry]!.length,
                          );
                        }
                        final type = entry as AssetType;
                        return ListTile(
                          key: ValueKey('asset-type-${type.id}'),
                          selected: widget.selectedId == type.id,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          leading: ExcludeSemantics(
                            child: EquipmentIllustration(
                              assetTypeId: type.id,
                              typeName: type.name,
                              size: 48,
                            ),
                          ),
                          title: Text(assetTypeLabel(type, spanish)),
                          trailing: widget.selectedId == type.id
                              ? const Icon(Icons.check)
                              : null,
                          onTap: () => Navigator.of(context).pop(type),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
