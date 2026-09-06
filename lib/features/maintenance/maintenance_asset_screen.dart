import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'maintenance_models.dart';
import 'maintenance_repository.dart';
import 'maintenance_setup_screen.dart';

class MaintenanceAssetsScreen extends ConsumerWidget {
  const MaintenanceAssetsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final es = isSpanish(context),
        manager = isMaintenanceManager(
          ref.watch(profileProvider).valueOrNull?.role,
        );
    return Scaffold(
      appBar: AppBar(title: Text(es ? 'Equipos y planes' : 'Assets & plans')),
      floatingActionButton: manager
          ? FloatingActionButton.extended(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute<bool>(
                    builder: (_) => const MaintenanceSetupScreen(kind: 'asset'),
                  ),
                );
                ref.invalidate(maintenanceWorkspaceProvider);
              },
              icon: const Icon(Icons.add),
              label: Text(es ? 'Añadir equipo' : 'Add asset'),
            )
          : null,
      body: ref
          .watch(maintenanceWorkspaceProvider)
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(maintenanceError(e, es)),
                  TextButton(
                    onPressed: () =>
                        ref.invalidate(maintenanceWorkspaceProvider),
                    child: Text(es ? 'Reintentar' : 'Try again'),
                  ),
                ],
              ),
            ),
            data: (workspace) => RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(maintenanceWorkspaceProvider);
                await ref.read(maintenanceWorkspaceProvider.future);
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                children: [
                  if (maintenanceRows(workspace['assets']).isEmpty)
                    Text(
                      es
                          ? 'Añade tu primer equipo para configurar componentes y planes.'
                          : 'Add your first asset to set up components and plans.',
                    ),
                  for (final asset in maintenanceRows(workspace['assets']))
                    Card(
                      child: ListTile(
                        title: Text(asset['name'] as String),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () =>
                            context.push('/maintenance/assets/${asset['id']}'),
                      ),
                    ),
                ],
              ),
            ),
          ),
    );
  }
}

class MaintenanceAssetScreen extends ConsumerWidget {
  const MaintenanceAssetScreen({super.key, required this.assetId});
  final String assetId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final es = isSpanish(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(es ? 'Mantenimiento del equipo' : 'Asset maintenance'),
        actions: [
          IconButton(
            tooltip: es ? 'Actualizar' : 'Refresh',
            onPressed: () => ref.invalidate(maintenanceAssetProvider(assetId)),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ref
          .watch(maintenanceAssetProvider(assetId))
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(maintenanceError(e, es)),
                  TextButton(
                    onPressed: () =>
                        ref.invalidate(maintenanceAssetProvider(assetId)),
                    child: Text(es ? 'Reintentar' : 'Try again'),
                  ),
                ],
              ),
            ),
            data: (catalog) {
              if (catalog['asset'] == null) return const SizedBox.shrink();
              final asset = Map<String, dynamic>.from(catalog['asset'] as Map);
              final manager = catalog['can_manage'] == true,
                  planManager = catalog['can_plan'] == true;
              Future<void> edit(
                String kind, [
                Map<String, dynamic> initial = const {},
              ]) async {
                await Navigator.push(
                  context,
                  MaterialPageRoute<bool>(
                    builder: (_) => MaintenanceSetupScreen(
                      kind: kind,
                      assetId: assetId,
                      initial: initial,
                      catalog: catalog,
                    ),
                  ),
                );
                ref.invalidate(maintenanceAssetProvider(assetId));
              }

              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    asset['name'] as String,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  if (asset['location'] != null)
                    Text(asset['location'] as String),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (manager)
                        OutlinedButton(
                          onPressed: () => edit('asset', asset),
                          child: Text(es ? 'Editar equipo' : 'Edit asset'),
                        ),
                      if (canUseMaintenance(
                        ref.watch(profileProvider).valueOrNull?.role,
                      ))
                        FilledButton(
                          onPressed: () =>
                              context.push('/maintenance?assetId=$assetId'),
                          child: Text(es ? 'Ver trabajos' : 'View work'),
                        ),
                      if (manager && catalog['can_execute'] == true)
                        OutlinedButton(
                          onPressed: () =>
                              context.push('/maintenance/new?assetId=$assetId'),
                          child: Text(es ? 'Crear reparación' : 'New repair'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    es ? 'Componentes' : 'Components',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (maintenanceRows(catalog['components']).isEmpty)
                    Text(
                      es
                          ? 'Añade un motor, generador u otro componente para vincular sus servicios.'
                          : 'Add an engine, generator or other component to link its services.',
                    ),
                  for (final component in maintenanceRows(
                    catalog['components'],
                  ))
                    Card(
                      child: ListTile(
                        title: Text(component['label'] as String),
                        subtitle: Text('${component['current_hours'] ?? 0} h'),
                        trailing: manager
                            ? IconButton(
                                tooltip: es
                                    ? 'Editar componente'
                                    : 'Edit component',
                                onPressed: () => edit('component', component),
                                icon: const Icon(Icons.edit_outlined),
                              )
                            : null,
                      ),
                    ),
                  if (manager)
                    OutlinedButton.icon(
                      onPressed: () => edit('component'),
                      icon: const Icon(Icons.add),
                      label: Text(es ? 'Añadir componente' : 'Add component'),
                    ),
                  const SizedBox(height: 24),
                  Text(
                    es ? 'Planes de mantenimiento' : 'Maintenance plans',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (manager && !planManager)
                    Text(
                      es
                          ? 'La planificación no está habilitada para esta empresa.'
                          : 'Maintenance planning is not enabled for this company.',
                    ),
                  if (maintenanceRows(catalog['plans']).isEmpty)
                    Text(
                      es
                          ? 'No hay planes configurados.'
                          : 'No plans configured.',
                    ),
                  for (final plan in maintenanceRows(catalog['plans']))
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              plan['interval_label'] as String? ??
                                  '${plan['interval_hours']} h',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              '${plan['component_name'] ?? (es ? 'Selecciona un componente' : 'Choose a component')} · ${es ? 'Cada' : 'Every'} ${plan['interval_hours']} h',
                            ),
                            Text(
                              plan['next_due_hours'] == null
                                  ? (es
                                        ? 'Sin línea base'
                                        : 'No service baseline')
                                  : '${es ? 'Próximo servicio' : 'Next service'}: ${plan['next_due_hours']} h',
                            ),
                            if (plan['is_active'] != true)
                              Text(es ? 'Plan inactivo' : 'Inactive plan'),
                            if (plan['next_due_hours'] is num &&
                                plan['current_hours'] is num &&
                                (plan['current_hours'] as num) >=
                                    (plan['next_due_hours'] as num))
                              Text(
                                es ? 'Servicio pendiente' : 'Service due',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (planManager)
                                  TextButton(
                                    onPressed: () => edit('plan', plan),
                                    child: Text(
                                      es ? 'Editar plan' : 'Edit plan',
                                    ),
                                  ),
                                if (plan['open_job_id'] != null &&
                                    canUseMaintenance(
                                      ref
                                          .watch(profileProvider)
                                          .valueOrNull
                                          ?.role,
                                    ))
                                  TextButton(
                                    onPressed: () => context.push(
                                      '/maintenance/jobs/${plan['open_job_id']}',
                                    ),
                                    child: Text(
                                      es
                                          ? 'Ver trabajo abierto'
                                          : 'View open job',
                                    ),
                                  )
                                else if (planManager &&
                                    catalog['can_execute'] == true &&
                                    plan['engine_id'] != null &&
                                    plan['is_active'] == true)
                                  FilledButton(
                                    onPressed: () => context.push(
                                      '/maintenance/new?assetId=$assetId&planId=${plan['id']}',
                                    ),
                                    child: Text(
                                      es
                                          ? 'Programar servicio'
                                          : 'Schedule service',
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (planManager)
                    OutlinedButton.icon(
                      onPressed: maintenanceRows(catalog['components']).isEmpty
                          ? null
                          : () => edit('plan'),
                      icon: const Icon(Icons.add),
                      label: Text(es ? 'Añadir plan' : 'Add plan'),
                    ),
                  const SizedBox(height: 20),
                  Text(
                    es
                        ? 'El próximo servicio cambia solo al aprobar el trabajo vinculado a este plan.'
                        : 'The next service changes only when work linked to this plan is approved.',
                  ),
                ],
              );
            },
          ),
    );
  }
}
