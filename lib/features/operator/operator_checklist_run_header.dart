import 'package:flutter/material.dart';
import 'package:vortice_app/core/meter_units.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/core/localized_text.dart';
import 'package:vortice_app/features/checklists/checklist_support.dart';

class OperatorChecklistRunHeader extends StatelessWidget {
  final String meterUnit;
  final String assetLabel;
  final String checklistLabel;
  final String completedByLabel;
  final DateTime completedAt;
  final TextEditingController hoursController;
  final TextEditingController notesController;
  final VoidCallback onPickCompletedAt;
  final ValueChanged<double?> onHoursChanged;
  final ValueChanged<String?> onNotesChanged;

  const OperatorChecklistRunHeader({
    super.key,
    required this.assetLabel,
    this.meterUnit = 'hours',
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
    return Material(
      color: context.appColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              localizedText(
                context,
                'Run details',
                'Detalles de la ejecución',
                'Détails de l’inspection',
              ),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Text(
              localizedText(
                context,
                'Equipment: $assetLabel',
                'Equipo: $assetLabel',
                'Équipement : $assetLabel',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              localizedText(
                context,
                'Checklist: $checklistLabel',
                'Lista de verificación: $checklistLabel',
                'Liste de contrôle : $checklistLabel',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              localizedText(
                context,
                'Completed by: $completedByLabel',
                'Completada por: $completedByLabel',
                'Effectuée par : $completedByLabel',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                localizedText(
                  context,
                  'Date and time',
                  'Fecha y hora',
                  'Date et heure',
                ),
              ),
              subtitle: Text(formatChecklistDateTime(completedAt)),
              trailing: const Icon(Icons.edit_calendar, size: 18),
              onTap: onPickCompletedAt,
            ),
            TextField(
              controller: hoursController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText:
                    '${meterName(meterUnit, Localizations.localeOf(context).languageCode == 'es', french: Localizations.localeOf(context).languageCode == 'fr')} (${localizedText(context, 'optional', 'opcional', 'facultatif')})',
                suffixText: meterSymbol(meterUnit),
                isDense: true,
              ),
              onChanged: (value) =>
                  onHoursChanged(double.tryParse(value.trim())),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: notesController,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: localizedText(
                  context,
                  'General notes (optional)',
                  'Notas generales (opcional)',
                  'Notes générales (facultatif)',
                ),
                isDense: true,
              ),
              onChanged: (value) =>
                  onNotesChanged(value.trim().isEmpty ? null : value.trim()),
            ),
          ],
        ),
      ),
    );
  }
}
