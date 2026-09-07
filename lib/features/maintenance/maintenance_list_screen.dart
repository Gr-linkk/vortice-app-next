import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'maintenance_models.dart';
import 'maintenance_repository.dart';
import 'work_list_provider.dart';
import 'package:vortice_app/features/work_orders/work_order_provider.dart';

class MaintenanceListScreen extends ConsumerStatefulWidget {
  const MaintenanceListScreen({super.key, this.assetId});
  final String? assetId;
  @override
  ConsumerState<MaintenanceListScreen> createState() =>
      _MaintenanceListScreenState();
}

class _MaintenanceListScreenState extends ConsumerState<MaintenanceListScreen> {
  String _filter = 'open', _search = '';
  @override
  Widget build(BuildContext context) {
    final es = isSpanish(context);
    final profile = ref.watch(profileProvider).valueOrNull;
    if (!canUseMaintenance(profile?.role)) {
      return Scaffold(
        appBar: AppBar(title: Text(es ? 'Órdenes de trabajo' : 'Work orders')),
        body: Center(
          child: Text(
            es
                ? 'Tu perfil no tiene acceso a este trabajo.'
                : 'Your role does not have access to this work.',
          ),
        ),
      );
    }
    final result = ref.watch(workListProvider(widget.assetId));
    void refresh() {
      ref.invalidate(maintenanceJobsProvider(widget.assetId));
      ref.invalidate(workOrdersProvider);
      ref.invalidate(workListProvider(widget.assetId));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(es ? 'Órdenes de trabajo' : 'Work orders'),
        actions: [
          IconButton(
            tooltip: es ? 'Equipos y planes' : 'Assets & plans',
            onPressed: () => context.push('/maintenance/assets'),
            icon: const Icon(Icons.precision_manufacturing_outlined),
          ),
          IconButton(
            tooltip: es ? 'Actualizar' : 'Refresh',
            onPressed: refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: !isMaintenanceManager(profile?.role)
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push(
                Uri(
                  path: '/maintenance/new',
                  queryParameters: {
                    if (widget.assetId != null) 'assetId': widget.assetId!,
                  },
                ).toString(),
              ),
              icon: const Icon(Icons.add),
              label: Text(es ? 'Nueva orden' : 'New work order'),
            ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              decoration: InputDecoration(
                labelText: es
                    ? 'Buscar orden o equipo'
                    : 'Search work order or asset',
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (value) =>
                  setState(() => _search = value.toLowerCase().trim()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              children: [
                for (final option in [
                  ('open', es ? 'Abiertos' : 'Open'),
                  ('mine', es ? 'Asignados a mí' : 'Assigned to me'),
                  ('pending_review', es ? 'Por revisar' : 'Needs review'),
                  ('closed', es ? 'Historial' : 'History'),
                ])
                  ChoiceChip(
                    label: Text(option.$2),
                    selected: _filter == option.$1,
                    onSelected: (_) => setState(() => _filter = option.$1),
                  ),
              ],
            ),
          ),
          Expanded(
            child: result.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(maintenanceError(error, es)),
                      TextButton(
                        onPressed: refresh,
                        child: Text(es ? 'Reintentar' : 'Try again'),
                      ),
                    ],
                  ),
                ),
              ),
              data: (jobs) {
                final visible = jobs
                    .where((entry) => entry.matches(_filter, _search))
                    .toList();
                return RefreshIndicator(
                  onRefresh: () async {
                    refresh();
                    await ref.read(workListProvider(widget.assetId).future);
                  },
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    children: [
                      if (visible.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            es
                                ? 'No hay órdenes con este filtro.'
                                : 'No work orders match this view.',
                          ),
                        ),
                      for (final job in visible)
                        Card(
                          child: ListTile(
                            title: Text(job.title),
                            subtitle: Text(
                              '${job.assetName}\n${job.service ? (es ? 'Orden de servicio' : 'Service order') : (es ? 'Orden interna' : 'Internal work order')}${job.workType == null ? '' : ' · ${job.workType!.label(es)}'} · ${job.status == 'invoiced' ? (es ? 'Facturado' : 'Invoiced') : maintenanceStatus(job.status, es)}${job.priority == null ? '' : ' · ${maintenancePriority(job.priority!, es)}'}${job.dueDate == null ? '' : ' · ${maintenanceDate(job.dueDate, es)}'}',
                            ),
                            isThreeLine: true,
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.push(job.route),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
