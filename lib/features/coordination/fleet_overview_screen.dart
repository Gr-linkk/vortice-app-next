import 'package:vortice_app/features/assets/asset_workspace.dart';
import 'package:vortice_app/features/maintenance/planning/planning_repository.dart';
import 'package:vortice_app/features/fleet/fleet_providers.dart';
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
    final workspace = ref.watch(assetWorkspaceProvider);
    final work = ref.watch(maintenancePlanningProvider(null));
    final faults = ref.watch(fleetFaultsProvider(null));
    final actor = ref.watch(profileProvider).valueOrNull?.id;
    void refresh() {
      ref.invalidate(assetWorkspaceProvider);
      ref.invalidate(maintenancePlanningProvider);
      ref.invalidate(fleetFaultsProvider);
    }

    if (workspace.isLoading || work.isLoading || faults.isLoading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: LinearProgressIndicator(),
      );
    }
    final error = workspace.error ?? work.error ?? faults.error;
    if (error != null) return FleetError(error: error, onRetry: refresh);
    final now = DateTime.now();
    final rows = <({String title, String route, int count})>[];
    void assets(String key) {
      final count = filterWorkspaceAssets(
        workspace.valueOrNull ?? {},
        key,
      ).length;
      if (count > 0) {
        rows.add((
          title: es
              ? assetWorkspaceFilters[key]!.$2
              : assetWorkspaceFilters[key]!.$1,
          route: assetWorkspaceDestination(key),
          count: count,
        ));
      }
    }

    void jobs(String key, String en, String spanish) {
      final count =
          work.valueOrNull?.jobs
              .where((job) => job.matchesFilter(key, actor, now))
              .length ??
          0;
      if (count > 0) {
        rows.add((
          title: es ? spanish : en,
          route: '/maintenance/planning?filter=$key',
          count: count,
        ));
      }
    }

    assets('unavailable');
    final urgent =
        faults.valueOrNull
            ?.where((fault) => fault.urgent && fault.status.isActive)
            .length ??
        0;
    if (urgent > 0) {
      rows.add((
        title: es ? 'Fallas urgentes' : 'Urgent faults',
        route: '/fleet?filter=urgent',
        count: urgent,
      ));
    }
    jobs('overdue', 'Overdue work', 'Trabajo vencido');
    assets('inspection_expired');
    jobs('review', 'Awaiting review', 'Pendiente de revisión');
    jobs('parts', 'Waiting for parts', 'Esperando piezas');
    jobs('people', 'Waiting for people', 'Esperando personas');
    jobs('blocked', 'Other blocked work', 'Otros trabajos bloqueados');
    assets('inspection_pending');
    assets('overdue_service');
    assets('plan_setup');
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              es ? 'Necesita atención' : 'Needs attention',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  es ? 'Sin pendientes urgentes.' : 'No urgent items waiting.',
                ),
              ),
            for (final row in rows.take(3))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(row.title),
                leading: Text(
                  '${row.count}',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await context.push(row.route);
                  if (context.mounted) refresh();
                },
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
                                  for (final key
                                      in (attentionCategories.keys.toList()
                                        ..sort(
                                          (a, b) => ((counts[b] as num?) ?? 0)
                                              .compareTo(
                                                (counts[a] as num?) ?? 0,
                                              ),
                                        )))
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
      padding: const EdgeInsets.only(top: 6),
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
