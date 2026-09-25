import 'package:flutter/material.dart';
import 'package:vortice_app/core/list_group_heading.dart';
import 'package:vortice_app/core/equipment_art_catalog.dart';
import 'package:vortice_app/core/equipment_illustration.dart';
import 'package:vortice_app/features/assets/asset_type_provider.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/core/localized_text.dart';

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
    final french = isFrench(context);
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
                  ? localizedText(
                      context,
                      'Choose equipment type',
                      'Elegir tipo de equipo',
                      'Choisir le type d’équipement',
                    )
                  : localizedText(
                      context,
                      'Current equipment type',
                      'Tipo de equipo actual',
                      'Type d’équipement actuel',
                    )
            : assetTypeLabel(selected, spanish, french: french);
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

String assetTypeLabel(AssetType type, bool spanish, {bool french = false}) {
  final art = equipmentArtFor(assetTypeId: type.id, typeName: type.name);
  if (french && art != EquipmentArt.other) return frenchEquipmentLabels[art]!;
  return spanish && art != EquipmentArt.other ? art.spanishLabel : type.name;
}

const frenchEquipmentLabels = <EquipmentArt, String>{
  EquipmentArt.motorYacht: 'Yacht à moteur',
  EquipmentArt.sailingYacht: 'Voilier',
  EquipmentArt.catamaran: 'Catamaran',
  EquipmentArt.sportFisher: 'Bateau de pêche sportive',
  EquipmentArt.workBoat: 'Bateau de travail',
  EquipmentArt.centerConsole: 'Bateau à console centrale',
  EquipmentArt.hydraulicDredge: 'Drague hydraulique',
  EquipmentArt.cutterDredge: 'Drague aspiratrice à tête désagrégatrice',
  EquipmentArt.excavator: 'Excavatrice',
  EquipmentArt.wheelLoader: 'Chargeuse sur roues',
  EquipmentArt.bulldozer: 'Bulldozer',
  EquipmentArt.generator: 'Génératrice diesel',
  EquipmentArt.pump: 'Pompe',
  EquipmentArt.crane: 'Grue',
  EquipmentArt.engine: 'Moteur',
  EquipmentArt.rib: 'Bateau pneumatique ou semi-rigide',
  EquipmentArt.aluminumSkiff: 'Chaloupe en aluminium',
  EquipmentArt.cabinCruiser: 'Bateau de plaisance à cabine',
  EquipmentArt.trawler: 'Chalutier commercial',
  EquipmentArt.purseSeiner: 'Senneur',
  EquipmentArt.tugboat: 'Remorqueur',
  EquipmentArt.backhoeLoader: 'Rétrocaveuse',
  EquipmentArt.skidSteer: 'Chargeuse compacte',
  EquipmentArt.dumpTruck: 'Camion à benne basculante',
  EquipmentArt.motorGrader: 'Niveleuse',
  EquipmentArt.forklift: 'Chariot élévateur',
  EquipmentArt.telehandler: 'Chariot télescopique',
  EquipmentArt.roadRoller: 'Rouleau compresseur',
  EquipmentArt.mobileCrane: 'Grue mobile',
  EquipmentArt.towerCrane: 'Grue à tour',
  EquipmentArt.davit: 'Bossoir',
  EquipmentArt.lightVehicle: 'Véhicule léger',
  EquipmentArt.highwayTruck: 'Camion routier',
  EquipmentArt.miniExcavator: 'Mini-excavatrice',
  EquipmentArt.compactTrackLoader: 'Chargeuse compacte sur chenilles',
  EquipmentArt.agriculturalTractor: 'Tracteur agricole',
  EquipmentArt.zeroTurnMower: 'Tondeuse à rayon de braquage zéro',
  EquipmentArt.boomLift: 'Nacelle à bras',
  EquipmentArt.scissorLift: 'Nacelle à ciseaux',
};

String _categoryLabel(String category, bool spanish, {bool french = false}) {
  if (french) {
    return switch (category) {
      'Marine Vessels' => 'Navires et bateaux',
      'Commercial Fishing' => 'Pêche commerciale',
      'Dredging Equipment' => 'Équipement de dragage',
      'Heavy Equipment' => 'Machinerie lourde',
      'Power Generation' => 'Production d’énergie',
      'Industrial Equipment' => 'Équipement industriel',
      'Lifting Equipment' => 'Équipement de levage',
      'Road Vehicles' => 'Véhicules routiers',
      'Agriculture & Grounds' => 'Agriculture et espaces verts',
      'Other' => 'Autre',
      _ => category,
    };
  }
  return !spanish
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
}

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
    final french = isFrench(context);
    final matches = widget.types.where((type) {
      final category = type.category.trim().isEmpty
          ? 'Other'
          : type.category.trim();
      final text =
          '${type.name} ${assetTypeLabel(type, true)} ${assetTypeLabel(type, false, french: true)} $category ${_categoryLabel(category, true)} ${_categoryLabel(category, false, french: true)}'
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
          french: french,
        ).toLowerCase().compareTo(
          _categoryLabel(b, spanish, french: french).toLowerCase(),
        );
      });
    final entries = <Object>[];
    for (final category in categories) {
      final types = groups[category]!
        ..sort(
          (a, b) => assetTypeLabel(a, spanish, french: french)
              .toLowerCase()
              .compareTo(
                assetTypeLabel(b, spanish, french: french).toLowerCase(),
              ),
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
                  labelText: localizedText(
                    context,
                    'Search types',
                    'Buscar tipos',
                    'Rechercher un type',
                  ),
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
                          localizedText(
                            context,
                            'No matching types. Try another name or category.',
                            'No hay tipos coincidentes. Prueba otro nombre o categoría.',
                            'Aucun type trouvé. Essayez un autre nom ou une autre catégorie.',
                          ),
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
                            label: _categoryLabel(
                              entry,
                              spanish,
                              french: french,
                            ),
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
                          title: Text(
                            assetTypeLabel(type, spanish, french: french),
                          ),
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
