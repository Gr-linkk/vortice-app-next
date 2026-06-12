import 'package:flutter/material.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/checklists/checklist_support.dart';
import 'package:vortice_app/models/checklist_template.dart';

class ChecklistTemplateSelector extends StatelessWidget {
  final List<ChecklistTemplate> templates;
  final ChecklistTemplate? preselected;
  final String emptyMessage;
  final ValueChanged<ChecklistTemplate> onSelect;

  const ChecklistTemplateSelector({
    super.key,
    required this.templates,
    this.preselected,
    required this.emptyMessage,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final serviceTemplates = templates
        .where((template) => template.intervalHours != null)
        .toList()
      ..sort(compareTemplatesByServiceHours);
    final otherTemplates =
        templates.where((template) => template.intervalHours == null).toList();

    final grouped = <String, List<ChecklistTemplate>>{};
    for (final template in otherTemplates) {
      grouped.putIfAbsent(template.category, () => []).add(template);
    }
    for (final group in grouped.values) {
      group.sort(compareTemplatesByServiceHours);
    }

    final orderedKeys = [
      'pre_ops',
      'general',
      'dredge',
      ...grouped.keys
          .where((key) => !['pre_ops', 'general', 'dredge'].contains(key)),
    ];

    final categoryLabel = {
      'pre_ops': 'Pre-Operations',
      'general': 'General',
      'dredge': 'Dredge',
    };

    if (templates.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            emptyMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        if (serviceTemplates.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              'Service Hours',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                  ),
            ),
          ),
          ...serviceTemplates.map((t) => ChecklistTemplateTile(
                template: t,
                selected: preselected?.id == t.id,
                onTap: () => onSelect(t),
              )),
        ],
        for (final key in orderedKeys)
          if (grouped.containsKey(key)) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                categoryLabel[key] ?? key.toUpperCase(),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                    ),
              ),
            ),
            ...grouped[key]!.map((t) => ChecklistTemplateTile(
                  template: t,
                  selected: preselected?.id == t.id,
                  onTap: () => onSelect(t),
                )),
          ],
      ],
    );
  }
}

class ChecklistTemplateTile extends StatelessWidget {
  final ChecklistTemplate template;
  final bool selected;
  final VoidCallback onTap;

  const ChecklistTemplateTile({
    super.key,
    required this.template,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final intervalHours = template.intervalHours;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      color: selected
          ? AppColors.primary.withValues(alpha: 0.08)
          : AppColors.surface,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.surfaceVariant,
          child: intervalHours == null
              ? Icon(
                  Icons.checklist,
                  color: selected ? AppColors.primary : AppColors.textSecondary,
                  size: 20,
                )
              : Text(
                  '${intervalHours}h',
                  style: TextStyle(
                    color: selected ? AppColors.primary : AppColors.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
        title: Text(
          template.name,
          style: TextStyle(fontWeight: selected ? FontWeight.bold : null),
        ),
        subtitle: template.description != null
            ? Text(
                template.description!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            : null,
        trailing: selected
            ? const Icon(Icons.check, color: AppColors.primary, size: 20)
            : const Icon(Icons.chevron_right, color: AppColors.textSecondary),
        onTap: onTap,
      ),
    );
  }
}
