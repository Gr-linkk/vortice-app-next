import 'package:vortice_app/core/app_dropdown_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/models/checklist_template.dart';

class OperatorChecklistSelectionStep extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.selectAsset,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          assetsAsync.when(
            loading: () => const CircularProgressIndicator(),
            error: (e, _) => Text(
              e.toString(),
              style: const TextStyle(color: AppColors.error),
            ),
            data: (assets) {
              final grouped = <String, List<Map<String, dynamic>>>{};
              for (final a in assets) {
                final client =
                    (a['profiles'] as Map<String, dynamic>?)?['full_name']
                        as String? ??
                    'Unknown';
                grouped.putIfAbsent(client, () => []).add(a);
              }
              final clients = grouped.keys.toList()..sort();

              final allItems = <DropdownMenuItem<String>>[
                for (final client in clients)
                  for (final a in grouped[client]!)
                    DropdownMenuItem<String>(
                      value: a['id'] as String,
                      child: Text('${a['name']}'),
                    ),
              ];

              return AppDropdownField<String>(
                initialValue: selectedAsset?['id'] as String?,
                decoration: const InputDecoration(),
                dropdownColor: AppColors.surfaceVariant,
                items: allItems,
                hint: Text(
                  l10n.selectAsset,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                onChanged: (id) {
                  if (id == null) return;
                  final asset = assets.firstWhere((a) => a['id'] == id);
                  onAssetSelected(asset);
                },
              );
            },
          ),
          const SizedBox(height: 24),
          Text(
            l10n.selectTemplate,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          templatesAsync.when(
            loading: () => const CircularProgressIndicator(),
            error: (e, _) => Text(
              e.toString(),
              style: const TextStyle(color: AppColors.error),
            ),
            data: (templates) {
              final operatorTemplates = templates
                  .where((t) => t.checklistType == 'operator_daily')
                  .toList();
              return AppDropdownField<String>(
                initialValue: selectedTemplate?.id,
                decoration: const InputDecoration(),
                dropdownColor: AppColors.surfaceVariant,
                items:
                    (operatorTemplates.isEmpty ? templates : operatorTemplates)
                        .map(
                          (t) => DropdownMenuItem(
                            value: t.id,
                            child: Text(t.name),
                          ),
                        )
                        .toList(),
                hint: Text(
                  l10n.selectTemplate,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                onChanged: (id) {
                  if (id == null) return;
                  final tmpl = templates.firstWhere((t) => t.id == id);
                  onTemplateSelected(tmpl);
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
