import 'package:vortice_app/core/meter_units.dart';
import 'package:flutter/material.dart';
import 'package:vortice_app/core/app_dropdown_field.dart';
import 'maintenance_recurrence.dart';

class MaintenanceRecurrenceFields extends StatelessWidget {
  const MaintenanceRecurrenceFields({
    super.key,
    required this.text,
    required this.values,
    required this.initial,
    required this.plans,
    required this.es,
    required this.frozen,
    required this.onChanged,
  });
  final Map<String, TextEditingController> text;
  final Map<String, dynamic> values, initial;
  final List<Map<String, dynamic>> plans;
  final bool es, frozen;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final fixed = values['recurrence_mode'] == 'fixed';
    final hours = int.tryParse(text['interval_hours']!.text) ?? 0;
    final months = int.tryParse(text['interval_months']!.text);
    final calendar = values['recurrence_basis'] != 'hours';
    Widget field(
      String name,
      String en,
      String spanish, {
      bool date = false,
      bool locked = false,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        key: ValueKey(name),
        controller: text[name],
        enabled: !frozen && !locked,
        decoration: InputDecoration(
          labelText: es ? spanish : en,
          hintText: date ? 'YYYY-MM-DD' : null,
          suffixIcon: date
              ? IconButton(
                  tooltip: es ? 'Elegir fecha' : 'Choose date',
                  icon: const Icon(Icons.calendar_today_outlined),
                  onPressed: frozen || locked
                      ? null
                      : () async {
                          final chosen = await showDatePicker(
                            context: context,
                            initialDate:
                                MaintenanceRecurrence.parseDate(
                                  text[name]!.text,
                                ) ??
                                DateTime.now(),
                            firstDate: DateTime(1900),
                            lastDate: DateTime(2200),
                          );
                          if (chosen != null) {
                            text[name]!.text = MaintenanceRecurrence.dateText(
                              chosen,
                            );
                            onChanged();
                          }
                        },
                )
              : null,
        ),
        keyboardType: date ? TextInputType.datetime : TextInputType.text,
        onChanged: (_) => onChanged(),
        validator: (value) {
          final v = (value ?? '').trim();
          if (name == 'change_reason') {
            return v.length < 3
                ? (es ? 'Explica el ajuste' : 'Explain the adjustment')
                : null;
          }
          if (date) {
            return MaintenanceRecurrence.parseDate(v) == null
                ? (es ? 'Usa YYYY-MM-DD' : 'Use YYYY-MM-DD')
                : null;
          }
          final n = double.tryParse(v);
          if (n == null ||
              !n.isFinite ||
              n < 0 ||
              n >= 1000000000 ||
              (name == 'generation_lead_days' &&
                  (n > 365 || n != n.roundToDouble())) ||
              (name == 'interval_months' &&
                  (n < 1 || n > 120 || n != n.roundToDouble()))) {
            return es ? 'Ingresa un valor válido' : 'Enter a valid value';
          }
          return null;
        },
      ),
    );
    final baseline = double.tryParse(text['last_service_hours']!.text);
    final anchor = double.tryParse(text['anchor_hours']!.text);
    final lastDate = MaintenanceRecurrence.parseDate(
      text['last_service_date']!.text.trim(),
    );
    final anchorDate = MaintenanceRecurrence.parseDate(
      text['anchor_date']!.text.trim(),
    );
    final valid =
        baseline != null &&
        baseline.isFinite &&
        baseline >= 0 &&
        hours >= 0 &&
        (hours > 0 || months != null) &&
        (months == null || months >= 1 && months <= 120) &&
        (!fixed ||
            hours == 0 ||
            anchor != null && anchor.isFinite && anchor >= 0) &&
        (months == null || (fixed ? anchorDate != null : lastDate != null));
    final rule = valid
        ? MaintenanceRecurrence(
            hours: hours,
            baseline: baseline,
            months: months,
            fixed: fixed,
            anchorHours: anchor,
            anchorDate: anchorDate,
            lastDate: lastDate,
          )
        : null;
    final selected = (values['covers_plan_ids'] as List? ?? []).cast<String>();
    final candidates = plans
        .where(
          (p) =>
              selected.contains(p['id']) ||
              (p['id'] != initial['id'] &&
                  p['engine_id'] == values['engine_id'] &&
                  p['is_active'] == true &&
                  (p['covers_plan_ids'] as List? ?? []).isEmpty),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (calendar)
          field(
            'interval_months',
            'Service every (months)',
            'Servicio cada (meses)',
          ),
        AppDropdownField<String>(
          initialValue: fixed ? 'fixed' : 'completion',
          isExpanded: true,
          decoration: InputDecoration(
            labelText: es ? 'Repetición' : 'Repeat schedule',
          ),
          items: [
            DropdownMenuItem(
              value: 'completion',
              child: Text(
                es ? 'Desde el servicio realizado' : 'From actual completion',
              ),
            ),
            DropdownMenuItem(
              value: 'fixed',
              child: Text(
                es
                    ? 'Hitos fijos / transición'
                    : 'Fixed milestones / transition',
              ),
            ),
          ],
          onChanged: frozen
              ? null
              : (v) {
                  values['recurrence_mode'] = v;
                  onChanged();
                },
        ),
        const SizedBox(height: 16),
        if (fixed) ...[
          Text(
            es
                ? 'Elige el primer objetivo; después se repite el intervalo. Mover una cita no cambia estos objetivos.'
                : 'Choose the first target; the interval repeats from there. Moving an appointment does not change these targets.',
          ),
          const SizedBox(height: 12),
          if (hours > 0)
            field(
              'anchor_hours',
              'First meter milestone (${meterSymbol(values['meter_unit'] as String?)})',
              'Primer objetivo (${meterSymbol(values['meter_unit'] as String?)})',
            ),
          if (calendar)
            field(
              'anchor_date',
              'First date milestone',
              'Primera fecha objetivo',
              date: true,
            ),
        ] else if (calendar)
          field(
            'last_service_date',
            'Last service date',
            'Fecha del último servicio',
            date: true,
            locked: initial['last_service_date'] != null,
          ),
        if (candidates.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(
              es
                  ? 'Servicios incluidos (${selected.length})'
                  : 'Included services (${selected.length})',
            ),
            subtitle: Text(
              es
                  ? 'Sus listas también deben completarse.'
                  : 'Their checklist tasks must also be completed.',
            ),
            children: [
              for (final p in candidates)
                CheckboxListTile(
                  title: Text(
                    p['interval_label']?.toString() ?? p['id'].toString(),
                  ),
                  value: selected.contains(p['id']),
                  onChanged: frozen
                      ? null
                      : (checked) {
                          values['covers_plan_ids'] = [
                            ...selected.where((id) => id != p['id']),
                            if (checked == true) p['id'],
                          ];
                          onChanged();
                        },
                ),
            ],
          ),
        field(
          'generation_lead_days',
          'Generate work ahead (days)',
          'Generar trabajo antes (días)',
        ),
        if (initial['id'] != null)
          field('change_reason', 'Reason for adjustment', 'Motivo del ajuste'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  es ? 'Próximos objetivos' : 'Upcoming targets',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (rule == null)
                  Text(
                    es
                        ? 'Completa los intervalos y objetivos para ver la secuencia.'
                        : 'Enter valid intervals and targets to preview the sequence.',
                  )
                else
                  ..._preview(rule),
                const SizedBox(height: 8),
                Text(
                  es
                      ? 'Con medidor y meses, vence lo que ocurra primero. La aprobación del servicio avanza el plan.'
                      : 'With a meter and months, whichever comes first is due. Approved service advances the plan.',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  List<Widget> _preview(MaintenanceRecurrence rule) {
    final sameHourAnchor =
        initial['recurrence_mode'] == 'fixed' &&
        initial['anchor_hours'] == rule.anchorHours;
    final sameDateAnchor =
        initial['recurrence_mode'] == 'fixed' &&
        initial['anchor_date'] == text['anchor_date']!.text;
    var h = rule.hours == 0
        ? null
        : rule.fixed
        ? (sameHourAnchor
              ? (initial['interval_hours'] == rule.hours
                    ? (initial['next_due_hours'] as num?)?.toDouble()
                    : rule.nextHours(rule.baseline))
              : rule.anchorHours)
        : rule.nextHours(rule.baseline);
    var d = rule.months == null
        ? null
        : rule.fixed
        ? (sameDateAnchor
              ? (initial['interval_months'] == rule.months
                    ? DateTime.tryParse(
                        initial['next_due_date']?.toString() ?? '',
                      )
                    : rule.nextDate(
                        rule.lastDate ??
                            rule.anchorDate!.subtract(const Duration(days: 1)),
                      ))
              : rule.anchorDate)
        : rule.nextDate(rule.lastDate!);
    final widgets = <Widget>[];
    for (var i = 0; i < 4; i++) {
      widgets.add(
        Text(
          '${i + 1}. ${[if (h != null) formatMeter(h, values['meter_unit'] as String?), if (d != null) MaintenanceRecurrence.dateText(d)].join(es ? ' o ' : ' or ')}',
        ),
      );
      if (h != null) h = rule.nextHours(h);
      if (d != null) d = rule.nextDate(d);
    }
    widgets.add(
      Text(
        es
            ? 'Proyección si cada servicio se realiza en su objetivo.'
            : 'Projection assumes each service occurs at its target.',
      ),
    );
    return widgets;
  }
}
