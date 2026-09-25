import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/core/localized_text.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'maintenance_models.dart';
import 'maintenance_repository.dart';
import 'work_list_provider.dart';
import 'work_focus.dart';
import 'create_work_entry.dart';
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
    final es = isSpanish(context), fr = isFrench(context);
    final profile = ref.watch(profileProvider).valueOrNull;
    if (!canUseMaintenance(profile?.role)) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            localizedText(
              context,
              'Work orders',
              'Órdenes de trabajo',
              'Bons de travail',
            ),
          ),
        ),
        body: Center(
          child: Text(
            es
                ? 'Tu perfil no tiene acceso a este trabajo.'
                : fr
                ? 'Votre rôle ne vous donne pas accès à ces travaux.'
                : 'Your role does not have access to this work.',
          ),
        ),
      );
    }
    final result = ref.watch(workListProvider(widget.assetId));
    final focus = widget.assetId == null
        ? ref.watch(workFocusProvider).valueOrNull ?? WorkFocus.all
        : WorkFocus.all;
    void refresh() {
      ref.invalidate(maintenanceJobsProvider(widget.assetId));
      ref.invalidate(workOrdersProvider);
      ref.invalidate(workListProvider(widget.assetId));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          localizedText(
            context,
            'Work orders',
            'Órdenes de trabajo',
            'Bons de travail',
          ),
        ),
        actions: [
          IconButton(
            tooltip: localizedText(
              context,
              'Equipment & plans',
              'Equipos y planes',
              'Équipements et plans',
            ),
            onPressed: () => context.push('/maintenance/assets'),
            icon: const Icon(Icons.precision_manufacturing_outlined),
          ),
          IconButton(
            tooltip: localizedText(
              context,
              'Refresh',
              'Actualizar',
              'Actualiser',
            ),
            onPressed: refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: !isMaintenanceManager(profile?.role)
          ? null
          : FloatingActionButton.extended(
              onPressed: () =>
                  openNewWorkOrder(context, ref, assetId: widget.assetId),
              icon: const Icon(Icons.add),
              label: Text(
                localizedText(
                  context,
                  'New work order',
                  'Nueva orden',
                  'Nouveau bon de travail',
                ),
              ),
            ),
      body: Column(
        children: [
          if (widget.assetId == null)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: WorkFocusSelector(),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              decoration: InputDecoration(
                labelText: fr
                    ? 'Rechercher un bon de travail ou un équipement'
                    : es
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
                  (
                    'open',
                    localizedText(context, 'Open', 'Abiertos', 'Ouverts'),
                  ),
                  (
                    'mine',
                    localizedText(
                      context,
                      'Assigned to me',
                      'Asignados a mí',
                      'Attribués à moi',
                    ),
                  ),
                  (
                    'pending_review',
                    localizedText(
                      context,
                      'Needs review',
                      'Por revisar',
                      'À réviser',
                    ),
                  ),
                  (
                    'closed',
                    localizedText(
                      context,
                      'History',
                      'Historial',
                      'Historique',
                    ),
                  ),
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
                    .where(
                      (entry) =>
                          focus.includes(entry.ownEquipment) &&
                          entry.matches(_filter, _search),
                    )
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
                            fr
                                ? 'Aucun bon de travail ne correspond à cette vue.'
                                : es
                                ? 'No hay órdenes con este filtro.'
                                : 'No work orders match this view.',
                          ),
                        ),
                      for (final job in visible)
                        Card(
                          child: ListTile(
                            title: Text(job.title),
                            subtitle: Text(
                              '${job.assetName}\n${(job.ownEquipment ? WorkFocus.own : WorkFocus.customer).label(es, french: fr)}${job.workType == null ? '' : ' · ${job.workType!.label(es, fr: fr)}'} · ${job.lifecycleLabel(es, french: fr)}${job.status == 'invoiced' ? (fr
                                        ? ' · Facturé'
                                        : es
                                        ? ' · Facturado'
                                        : ' · Invoiced') : ''}${job.priority == null ? '' : ' · ${maintenancePriority(job.priority!, es, french: isFrench(context))}'}${job.dueDate == null ? '' : ' · ${maintenanceDate(job.dueDate, es, french: isFrench(context))}'}',
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
