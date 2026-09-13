import 'package:flutter/material.dart';
import 'package:vortice_app/core/app_dropdown_field.dart';
import '../work_focus.dart';

/// One on-demand filter surface; the calendar owns the committed view state.
class WorkCalendarFilters extends StatefulWidget {
  const WorkCalendarFilters({
    super.key,
    required this.initial,
    required this.assets,
    required this.people,
    required this.components,
    required this.es,
    required this.showFocus,
  });
  final Map<String, String?> initial, assets, people;
  final Set<String> components;
  final bool es, showFocus;
  @override
  State<WorkCalendarFilters> createState() => _WorkCalendarFiltersState();
}

class _WorkCalendarFiltersState extends State<WorkCalendarFilters> {
  late final values = Map<String, String?>.from(widget.initial);
  late final query = TextEditingController(text: values['query']);
  String t(String en, String es) => widget.es ? es : en;
  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  Widget choice(String key, String label, Map<String, String?> options) =>
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: AppDropdownField<String>(
          key: ValueKey('$key-${values[key]}'),
          initialValue: options.containsKey(values[key]) ? values[key] : '',
          decoration: InputDecoration(labelText: label),
          items: [
            for (final entry in options.entries)
              DropdownMenuItem(
                value: entry.key,
                child: Text(entry.value ?? entry.key),
              ),
          ],
          onChanged: (value) =>
              setState(() => values[key] = value == '' ? null : value),
        ),
      );
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      12,
      20,
      20 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            t('Search & filters', 'Buscar y filtrar'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (widget.showFocus)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: WorkFocusSelector(),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: query,
            decoration: InputDecoration(
              labelText: t(
                'Search work or equipment',
                'Buscar trabajo o equipo',
              ),
              prefixIcon: const Icon(Icons.search),
            ),
          ),
          choice('filter', t('Show work', 'Mostrar trabajo'), {
            'all': t('All statuses', 'Todos los estados'),
            'open': t('Open', 'Abiertos'),
            'mine': t('Assigned to me', 'Asignados a mí'),
            'unassigned': t('Unassigned', 'Sin asignar'),
            'review': t('Needs review', 'Necesita revisión'),
            'returned': t('Returned', 'Devuelto'),
            'completed': t('Completed', 'Completados'),
            'overdue': t('Work overdue', 'Trabajo vencido'),
            'parts': t('Waiting for parts', 'Esperando piezas'),
            'people': t('Waiting for people', 'Esperando personal'),
            'blocked': t('Other blocked work', 'Otros bloqueos'),
          }),
          if (widget.assets.length > 1)
            choice('asset', t('Equipment', 'Equipo'), {
              '': t('All equipment', 'Todos los equipos'),
              ...widget.assets,
            }),
          if (widget.people.isNotEmpty)
            choice('person', t('Assigned person', 'Responsable'), {
              '': t('Anyone', 'Todos'),
              ...widget.people,
            }),
          if (widget.components.isNotEmpty)
            choice('component', t('Component', 'Componente'), {
              '': t('All components', 'Todos los componentes'),
              for (final name in widget.components) name: name,
            }),
          choice('type', t('Work type', 'Tipo de trabajo'), {
            '': t('All types', 'Todos los tipos'),
            'repair': t('Repair', 'Reparación'),
            'preventative': t(
              'Preventive maintenance',
              'Mantenimiento preventivo',
            ),
            'inspection': t('Inspection', 'Inspección'),
            'general': t('General work', 'Trabajo general'),
          }),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              values['query'] = query.text.trim().toLowerCase();
              Navigator.pop(context, values);
            },
            child: Text(t('Show work orders', 'Mostrar órdenes de trabajo')),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(context, <String, String?>{'filter': 'all'}),
            child: Text(
              t('Clear search & filters', 'Limpiar búsqueda y filtros'),
            ),
          ),
        ],
      ),
    ),
  );
}
