import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'maintenance_models.dart';
import 'maintenance_repository.dart';

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
        appBar: AppBar(title: Text(es ? 'Trabajo' : 'Work')),
        body: Center(
          child: Text(
            es
                ? 'Tu perfil no tiene acceso a este trabajo.'
                : 'Your role does not have access to this work.',
          ),
        ),
      );
    }
    final result = ref.watch(maintenanceJobsProvider(widget.assetId));
    return Scaffold(
      appBar: AppBar(
        title: Text(
          isMaintenanceManager(profile?.role)
              ? (es ? 'Mantenimiento' : 'Maintenance work')
              : (es ? 'Mi trabajo' : 'My Work'),
        ),
        actions: [
          IconButton(
            tooltip: es ? 'Equipos y planes' : 'Assets & plans',
            onPressed: () => context.push('/maintenance/assets'),
            icon: const Icon(Icons.precision_manufacturing_outlined),
          ),
          IconButton(
            tooltip: es ? 'Actualizar' : 'Refresh',
            onPressed: () =>
                ref.invalidate(maintenanceJobsProvider(widget.assetId)),
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
              label: Text(es ? 'Crear trabajo' : 'New job'),
            ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              decoration: InputDecoration(
                labelText: es
                    ? 'Buscar trabajo o equipo'
                    : 'Search job or asset',
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
                        onPressed: () => ref.invalidate(
                          maintenanceJobsProvider(widget.assetId),
                        ),
                        child: Text(es ? 'Reintentar' : 'Try again'),
                      ),
                    ],
                  ),
                ),
              ),
              data: (jobs) {
                final visible = jobs
                    .where(
                      (j) =>
                          (_filter == 'mine'
                              ? j.data['assigned_to'] == profile?.id &&
                                    j.status != 'closed'
                              : _filter == 'open'
                              ? j.status != 'closed'
                              : j.status == _filter) &&
                          '${j.title} ${j.assetName}'.toLowerCase().contains(
                            _search,
                          ),
                    )
                    .toList();
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(maintenanceJobsProvider(widget.assetId));
                    await ref.read(
                      maintenanceJobsProvider(widget.assetId).future,
                    );
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
                                ? 'No hay trabajos con este filtro.'
                                : 'No jobs match this view.',
                          ),
                        ),
                      for (final job in visible)
                        Card(
                          child: ListTile(
                            title: Text(job.title),
                            subtitle: Text(
                              '${job.assetName}\n${maintenanceStatus(job.status, es)} · ${maintenancePriority(job.priority, es)}${job.dueDate == null ? '' : ' · ${maintenanceDate(job.dueDate, es)}'}',
                            ),
                            isThreeLine: true,
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () =>
                                context.push('/maintenance/jobs/${job.id}'),
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
