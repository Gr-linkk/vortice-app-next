import 'package:flutter/material.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/checklists/checklist_support.dart';

class ChecklistRunHeader extends StatelessWidget {
  final String assetLabel;
  final String checklistLabel;
  final String completedByLabel;
  final DateTime completedAt;
  final TextEditingController hoursController;
  final TextEditingController notesController;
  final VoidCallback onPickCompletedAt;
  final ValueChanged<double?> onHoursChanged;
  final ValueChanged<String?> onNotesChanged;

  const ChecklistRunHeader({
    super.key,
    required this.assetLabel,
    required this.checklistLabel,
    required this.completedByLabel,
    required this.completedAt,
    required this.hoursController,
    required this.notesController,
    required this.onPickCompletedAt,
    required this.onHoursChanged,
    required this.onNotesChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Run details', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          ChecklistHeaderText(label: 'Asset', value: assetLabel),
          ChecklistHeaderText(label: 'Checklist', value: checklistLabel),
          ChecklistHeaderText(label: 'Completed by', value: completedByLabel),
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Date/time'),
            subtitle: Text(formatChecklistDateTime(completedAt)),
            trailing: const Icon(Icons.edit_calendar, size: 18),
            onTap: onPickCompletedAt,
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: hoursController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Current hours (optional)',
                    isDense: true,
                  ),
                  onChanged: (value) =>
                      onHoursChanged(double.tryParse(value.trim())),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: notesController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'General notes (optional)',
              isDense: true,
            ),
            onChanged: (value) => onNotesChanged(
              value.trim().isEmpty ? null : value.trim(),
            ),
          ),
        ],
      ),
    );
  }
}

class ChecklistHeaderText extends StatelessWidget {
  final String label;
  final String value;

  const ChecklistHeaderText({
    super.key,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child:
          Text('$label: $value', style: Theme.of(context).textTheme.bodySmall),
    );
  }
}
