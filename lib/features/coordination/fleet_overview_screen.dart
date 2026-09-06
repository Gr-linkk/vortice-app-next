import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/app_dropdown_field.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/fleet/fleet_widgets.dart';
import 'package:vortice_app/models/profile.dart';
import 'coordination_repository.dart';
import 'coordination_labels.dart';

String attentionDestination(Map<String, dynamic> row, UserRole? role) {
  final asset = row['asset_id'];
  return switch (row['kind']) {
    'fault' => '/fleet/faults/${row['id']}',
    'plan' => '/maintenance/assets/$asset',
    'job' when row['managed'] == true => '/maintenance/jobs/${row['id']}',
    'job' when role == UserRole.owner => '/owner/work-orders/${row['id']}',
    'job' => '/discussion/job/${row['id']}',
    _ when row['category'] == 'plan_setup' => '/maintenance/assets/$asset',
    _ => '/fleet/assets/$asset',
  };
}

class FleetPriorityCard extends ConsumerWidget {
  const FleetPriorityCard({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final es = fleetSpanish(context);
    final query = (
      today: localCalendarDate(),
      category: null as String?,
      offset: 0,
    );
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              es ? 'Prioridades de la flota' : 'Fleet priorities',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            ref
                .watch(fleetAttentionProvider(query))
                .when(
                  loading: () => const LinearProgressIndicator(),
                  error: (error, _) => FleetError(
                    error: error,
                    onRetry: () => ref.invalidate(fleetAttentionProvider),
                  ),
                  data: (page) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${es ? 'Actualizado' : 'Updated'} ${fleetDate(context, DateTime.tryParse(page['generated_at'] as String? ?? ''))}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (coordinationRows(page['items']).isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            es
                                ? 'No hay decisiones pendientes.'
                                : 'No decisions are waiting.',
                          ),
                        ),
                      for (final row in coordinationRows(page['items']).take(3))
                        AttentionTile(row: row),
                    ],
                  ),
                ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => context.push('/fleet/overview'),
              icon: const Icon(Icons.dashboard_outlined),
              label: Text(
                es
                    ? 'Ver indicadores y registros'
                    : 'View indicators and records',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FleetOverviewScreen extends ConsumerStatefulWidget {
  const FleetOverviewScreen({super.key});
  @override
  ConsumerState<FleetOverviewScreen> createState() =>
      _FleetOverviewScreenState();
}

class _FleetOverviewScreenState extends ConsumerState<FleetOverviewScreen> {
  final _recordsKey = GlobalKey();
  String? _category;
  int _offset = 0;
  String _today = localCalendarDate();
  Future<void> _selectIndicator(String category) async {
    setState(() {
      _category = category;
      _offset = 0;
    });
    try {
      await ref.read(
        fleetAttentionProvider((
          today: _today,
          category: category,
          offset: 0,
        )).future,
      );
    } catch (_) {
      return;
    }
    await WidgetsBinding.instance.endOfFrame;
    final recordContext = _recordsKey.currentContext;
    if (recordContext != null && recordContext.mounted) {
      await Scrollable.ensureVisible(
        recordContext,
        duration: const Duration(milliseconds: 250),
      );
    }
  }

  void _refresh() => setState(() {
    _today = localCalendarDate();
    _offset = 0;
    ref.invalidate(fleetAttentionProvider);
  });
  @override
  Widget build(BuildContext context) {
    final es = fleetSpanish(context);
    final query = (today: _today, category: _category, offset: _offset);
    return Scaffold(
      appBar: AppBar(
        title: Text(es ? 'Decisiones de la flota' : 'Fleet decisions'),
        actions: [
          IconButton(
            tooltip: es ? 'Actualizar' : 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            _refresh();
            try {
              await ref.read(
                fleetAttentionProvider((
                  today: _today,
                  category: _category,
                  offset: 0,
                )).future,
              );
            } catch (_) {
              /* The page displays the retry state. */
            }
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              Text(
                es
                    ? 'Elige un indicador para ver exactamente qué necesita atención.'
                    : 'Choose an indicator to see exactly what needs attention.',
              ),
              const SizedBox(height: 16),
              ref
                  .watch(fleetAttentionProvider(query))
                  .when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, _) =>
                        FleetError(error: error, onRetry: _refresh),
                    data: (page) {
                      final counts = Map<String, dynamic>.from(
                        page['counts'] as Map? ?? {},
                      );
                      final rows = coordinationRows(page['items']);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '${es ? 'Actualizado' : 'Updated'} ${fleetDate(context, DateTime.tryParse(page['generated_at'] as String? ?? ''))}',
                          ),
                          const SizedBox(height: 16),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final single =
                                  constraints.maxWidth < 350 ||
                                  MediaQuery.textScalerOf(context).scale(14) >
                                      19;
                              return Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: [
                                  for (final key in attentionCategories.keys)
                                    SizedBox(
                                      width: single
                                          ? constraints.maxWidth
                                          : (constraints.maxWidth - 12) / 2,
                                      child: Card(
                                        margin: EdgeInsets.zero,
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          onTap: () => _selectIndicator(key),
                                          child: Padding(
                                            padding: const EdgeInsets.all(16),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  '${counts[key] ?? 0}',
                                                  style: Theme.of(
                                                    context,
                                                  ).textTheme.headlineMedium,
                                                ),
                                                Text(
                                                  coordinationLabel(
                                                    attentionCategories,
                                                    key,
                                                    es,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 24),
                          AppDropdownField<String>(
                            key: ValueKey(_category),
                            initialValue: _category ?? 'all',
                            decoration: InputDecoration(
                              labelText: es
                                  ? 'Mostrar registros'
                                  : 'Show records',
                            ),
                            items: [
                              DropdownMenuItem(
                                value: 'all',
                                child: Text(
                                  es
                                      ? 'Todas las prioridades'
                                      : 'All priorities',
                                ),
                              ),
                              for (final key in attentionCategories.keys)
                                DropdownMenuItem(
                                  value: key,
                                  child: Text(
                                    coordinationLabel(
                                      attentionCategories,
                                      key,
                                      es,
                                    ),
                                  ),
                                ),
                            ],
                            onChanged: (value) => setState(() {
                              _category = value == 'all' ? null : value;
                              _offset = 0;
                            }),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '${page['total'] ?? 0} ${es ? 'registros' : 'records'}',
                            key: _recordsKey,
                          ),
                          if (_category == 'approaching_service')
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                es
                                    ? 'Según las horas registradas; no es un pronóstico.'
                                    : 'Based on recorded operating hours; this is not a forecast.',
                              ),
                            ),
                          if (rows.isEmpty)
                            FleetEmpty(
                              title: es ? 'Sin pendientes' : 'Nothing waiting',
                              message: es
                                  ? 'No hay registros en esta categoría.'
                                  : 'There are no records in this category.',
                            ),
                          for (final row in rows) AttentionTile(row: row),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 16,
                            runSpacing: 12,
                            children: [
                              if (_offset > 0)
                                OutlinedButton(
                                  onPressed: () =>
                                      setState(() => _offset -= 50),
                                  child: Text(es ? 'Anterior' : 'Previous'),
                                ),
                              if (page['has_more'] == true)
                                FilledButton(
                                  onPressed: () =>
                                      setState(() => _offset += 50),
                                  child: Text(es ? 'Siguiente' : 'Next'),
                                ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class AttentionTile extends ConsumerWidget {
  const AttentionTile({super.key, required this.row});
  final Map<String, dynamic> row;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final es = fleetSpanish(context);
    final category = row['category'] as String;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.all(16),
          alignment: Alignment.centerLeft,
        ),
        onPressed: () async {
          await context.push(
            attentionDestination(
              row,
              ref.read(profileProvider).valueOrNull?.role,
            ),
          );
          if (context.mounted) ref.invalidate(fleetAttentionProvider);
        },
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    coordinationLabel(attentionCategories, category, es),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${row['asset_name']} · ${row['title']}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  if ((row['reason'] as String? ?? '').isNotEmpty &&
                      [
                        'unavailable',
                        'waiting_parts',
                        'waiting_people',
                        'blocked_other',
                      ].contains(category))
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(row['reason'] as String),
                    ),
                  if (row['due_date'] != null)
                    Text('${es ? 'Fecha límite' : 'Due'}: ${row['due_date']}'),
                  if (row['remaining_hours'] != null)
                    Text(
                      '${row['remaining_hours']} h ${es ? 'hasta el servicio' : 'until service'}',
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}
