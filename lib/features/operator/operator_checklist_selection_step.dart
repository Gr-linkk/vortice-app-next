import 'package:flutter/material.dart';
import 'package:vortice_app/core/equipment_art_catalog.dart';
import 'package:vortice_app/core/list_group_heading.dart';
import 'package:vortice_app/core/list_label_order.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/features/checklists/asset_checklist_template_filter.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/core/localized_text.dart';
import 'package:vortice_app/features/assets/asset_type_field.dart';
import 'package:vortice_app/models/checklist_template.dart';

List<ChecklistTemplate> operatorTemplatesForAsset(
  Map<String, dynamic> asset,
  List<ChecklistTemplate> templates,
) =>
    templates
        .where(
          (t) => checklistTemplateMatches(
            t,
            kind: 'operator_daily',
            assetId: asset['id'] as String?,
            assetTypeId: asset['asset_type_id'] as String?,
            clientId: asset['client_id'] as String?,
          ),
        )
        .toList()
      ..sort((a, b) => compareListLabels(a.name, b.name));

class OperatorChecklistSelectionStep extends StatefulWidget {
  final AsyncValue<List<Map<String, dynamic>>> assetsAsync;
  final AsyncValue<List<ChecklistTemplate>> templatesAsync;
  final Map<String, dynamic>? selectedAsset;
  final ChecklistTemplate? selectedTemplate;
  final ValueChanged<Map<String, dynamic>> onAssetSelected;
  final ValueChanged<ChecklistTemplate> onTemplateSelected;

  const OperatorChecklistSelectionStep({
    super.key,
    required this.assetsAsync,
    required this.templatesAsync,
    required this.selectedAsset,
    required this.selectedTemplate,
    required this.onAssetSelected,
    required this.onTemplateSelected,
  });

  @override
  State<OperatorChecklistSelectionStep> createState() => _SelectionState();
}

class _SelectionState extends State<OperatorChecklistSelectionStep> {
  String _search = '';
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final es = Localizations.localeOf(context).languageCode == 'es';
    final fr = isFrench(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(l10n.selectAsset, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        widget.assetsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Text(
            es
                ? 'No se pudieron cargar los equipos. Vuelve a abrir esta pantalla.'
                : 'Equipment could not be loaded. Reopen this screen to try again.',
          ),
          data: (assets) {
            if (assets.isEmpty) {
              return Text(
                es
                    ? 'No tienes equipos disponibles. Pide acceso al responsable.'
                    : 'No equipment is available to you. Ask your manager for access.',
              );
            }
            String equipmentLabel(Map<String, dynamic> asset) {
              final art = equipmentArtFor(
                assetTypeId: asset['asset_type_id'] as String?,
              );
              return fr
                  ? (frenchEquipmentLabels[art] ?? art.label)
                  : es
                  ? art.spanishLabel
                  : art.label;
            }

            final visible = assets
                .where(
                  (a) =>
                      '${a['name']} ${a['make'] ?? ''} ${a['model'] ?? ''} ${equipmentLabel(a)}'
                          .toLowerCase()
                          .contains(_search.trim().toLowerCase()),
                )
                .toList();

            final groups = <String, List<Map<String, dynamic>>>{};
            for (final asset in visible) {
              groups.putIfAbsent(equipmentLabel(asset), () => []).add(asset);
            }
            final names = groups.keys.toList()
              ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
            for (final group in groups.values) {
              group.sort(
                (a, b) => compareListLabels('${a['name']}', '${b['name']}'),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (assets.length > 6) ...[
                  TextField(
                    decoration: InputDecoration(
                      labelText: localizedText(
                        context,
                        'Search equipment',
                        'Buscar equipos',
                        'Rechercher des équipements',
                      ),
                      prefixIcon: const Icon(Icons.search),
                    ),
                    onChanged: (value) => setState(() => _search = value),
                  ),
                  const SizedBox(height: 8),
                ],
                if (visible.isEmpty)
                  Text(
                    es
                        ? 'No hay equipos que coincidan.'
                        : 'No equipment matches your search.',
                  ),
                for (final name in names) ...[
                  if (groups.length > 1)
                    ListGroupHeading(label: name, count: groups[name]!.length),
                  for (final asset in groups[name]!)
                    Card(
                      child: ListTile(
                        selected: widget.selectedAsset?['id'] == asset['id'],
                        title: Text('${asset['name']}'),
                        subtitle:
                            [asset['make'], asset['model']]
                                .whereType<String>()
                                .where((s) => s.isNotEmpty)
                                .isEmpty
                            ? null
                            : Text(
                                [
                                  asset['make'],
                                  asset['model'],
                                ].whereType<String>().join(' '),
                              ),
                        trailing: Icon(
                          widget.selectedAsset?['id'] == asset['id']
                              ? Icons.check_circle
                              : Icons.chevron_right,
                        ),
                        onTap: () => widget.onAssetSelected(asset),
                      ),
                    ),
                ],
              ],
            );
          },
        ),
        if (widget.selectedAsset != null) ...[
          const SizedBox(height: 20),
          Text(
            l10n.selectTemplate,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          widget.templatesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => Text(
              es
                  ? 'No se pudieron cargar las listas.'
                  : 'Checklists could not be loaded.',
            ),
            data: (templates) {
              final matching = operatorTemplatesForAsset(
                widget.selectedAsset!,
                templates,
              );
              if (matching.isEmpty) {
                return Text(
                  es
                      ? 'No hay una lista previa publicada para este equipo. Pide al responsable que publique una.'
                      : 'No published pre-operation checklist matches this equipment. Ask your manager to publish one.',
                );
              }
              return Column(
                children: [
                  for (final specific in [true, false]) ...[
                    if (matching.any(
                      (t) => (t.scopeAssetId != null) == specific,
                    ))
                      ListGroupHeading(
                        label: specific
                            ? localizedText(
                                context,
                                'For this equipment',
                                'Para este equipo',
                                'Pour cet équipement',
                              )
                            : localizedText(
                                context,
                                'General checks',
                                'Revisiones generales',
                                'Inspections générales',
                              ),
                        count: matching
                            .where((t) => (t.scopeAssetId != null) == specific)
                            .length,
                      ),
                    for (final template in matching.where(
                      (t) => (t.scopeAssetId != null) == specific,
                    ))
                      Card(
                        child: ListTile(
                          title: Text(template.name),
                          subtitle: Text('v${template.version}'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => widget.onTemplateSelected(template),
                        ),
                      ),
                  ],
                ],
              );
            },
          ),
        ],
      ],
    );
  }
}
