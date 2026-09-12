import 'package:flutter/material.dart';
import 'package:vortice_app/core/app_dropdown_field.dart';
import 'package:vortice_app/features/maintenance/maintenance_recurrence.dart';

/// Shared creation/edit fields. Controllers use the RPC keys unchanged.
class InspectionScheduleFields extends StatelessWidget {
  const InspectionScheduleFields({
    super.key,
    required this.text,
    required this.values,
    required this.templates,
    required this.es,
    required this.onChanged,
    this.frozen = false,
  });
  final Map<String, TextEditingController> text;
  final Map<String, dynamic> values;
  final List<Map<String, dynamic>> templates;
  final bool es, frozen;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    Widget field(
      String key,
      String label, {
      bool date = false,
      bool notes = false,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: text[key],
        enabled: !frozen,
        minLines: notes ? 2 : 1,
        maxLines: notes ? 5 : 1,
        keyboardType: date
            ? TextInputType.datetime
            : notes
            ? TextInputType.multiline
            : TextInputType.number,
        decoration: InputDecoration(
          labelText: label,
          hintText: date ? 'YYYY-MM-DD' : null,
        ),
        onChanged: (_) => onChanged(),
        validator: (value) {
          final trimmed = (value ?? '').trim();
          if (notes) return null;
          if (date) {
            return MaintenanceRecurrence.parseDate(trimmed) == null
                ? (es ? 'Usa YYYY-MM-DD' : 'Use YYYY-MM-DD')
                : null;
          }
          final n = int.tryParse(trimmed);
          final minimum = key == 'interval_months' ? 1 : 0;
          final maximum = key == 'interval_months' ? 120 : 365;
          return n == null || n < minimum || n > maximum
              ? (es
                    ? 'Ingresa un valor entre $minimum y $maximum'
                    : 'Enter a value from $minimum to $maximum')
              : null;
        },
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        field(
          'first_due_date',
          es ? 'Primera fecha límite' : 'First due date',
          date: true,
        ),
        field(
          'interval_months',
          es
              ? 'Validez habitual (meses)'
              : 'Usual certificate validity (months)',
        ),
        field(
          'generation_lead_days',
          es ? 'Generar trabajo antes (días)' : 'Generate work ahead (days)',
        ),
        field(
          'procedure_notes',
          es ? 'Procedimiento requerido' : 'Required procedure',
          notes: true,
        ),
        AppDropdownField<String>(
          initialValue: values['checklist_template_id'] as String? ?? '',
          isExpanded: true,
          decoration: InputDecoration(
            labelText: es
                ? 'Lista publicada (opcional)'
                : 'Published checklist (optional)',
          ),
          items: [
            DropdownMenuItem(
              value: '',
              child: Text(es ? 'Sin lista adjunta' : 'No attached checklist'),
            ),
            for (final template in templates)
              DropdownMenuItem(
                value: template['id'] as String,
                child: Text(template['name'] as String? ?? ''),
              ),
          ],
          onChanged: frozen
              ? null
              : (value) {
                  values['checklist_template_id'] = value == '' ? null : value;
                  onChanged();
                },
        ),
        const SizedBox(height: 12),
        Text(
          es
              ? 'La orden se crea automáticamente. La fecha de vencimiento real se confirma en el informe de servicio.'
              : 'Work is created automatically. The actual certificate expiry is confirmed in the service report.',
        ),
      ],
    );
  }
}
