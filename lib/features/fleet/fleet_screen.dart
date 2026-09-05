import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/fleet/fleet_models.dart';
import 'package:vortice_app/features/fleet/fleet_providers.dart';
import 'package:vortice_app/features/fleet/fleet_widgets.dart';

class FleetScreen extends ConsumerStatefulWidget {
  const FleetScreen({super.key, this.assetId, this.initialTab = 0});
  final String? assetId;
  final int initialTab;
  @override
  ConsumerState<FleetScreen> createState() => _FleetScreenState();
}

class _FleetScreenState extends ConsumerState<FleetScreen> {
  String _query = '';
  bool _closed = false;
  bool _mine = false;
  OperatingState? _state;

  @override
  Widget build(BuildContext context) {
    final es = fleetSpanish(context);
    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: Text(es ? 'Estado de la flota' : 'Fleet readiness'),
          actions: [
            IconButton(
              tooltip: es ? 'Actualizar' : 'Refresh',
              onPressed: () => refreshFleet(ref),
              icon: const Icon(Icons.refresh),
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: es ? 'Fallas y reparaciones' : 'Faults & repairs'),
              Tab(text: es ? 'Disponibilidad' : 'Availability'),
            ],
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                onChanged: (value) =>
                    setState(() => _query = value.trim().toLowerCase()),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: es
                      ? 'Buscar equipo o falla'
                      : 'Search equipment or faults',
                ),
              ),
            ),
            if (widget.assetId != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        es ? 'Filtrado por equipo' : 'Filtered to one asset',
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                    TextButton(
                      onPressed: () => context.go('/fleet'),
                      child: Text(es ? 'Ver toda la flota' : 'Show all'),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: TabBarView(children: [_faults(es), _availability(es)]),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            await context.push(
              Uri(
                path: '/fleet/report',
                queryParameters: {
                  if (widget.assetId != null) 'assetId': widget.assetId!,
                },
              ).toString(),
            );
            if (mounted) refreshFleet(ref);
          },
          icon: const Icon(Icons.add),
          label: Text(es ? 'Reportar falla' : 'Report fault'),
        ),
      ),
    );
  }

  Widget _faults(bool es) {
    final userId = ref.watch(profileProvider).valueOrNull?.id;
    final result = ref.watch(fleetFaultsProvider(widget.assetId));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              children: [
                FilterChip(
                  label: Text(es ? 'Cerradas' : 'Closed'),
                  selected: _closed,
                  onSelected: (value) => setState(() => _closed = value),
                ),
                FilterChip(
                  label: Text(es ? 'Asignadas a mí' : 'Assigned to me'),
                  selected: _mine,
                  onSelected: (value) => setState(() => _mine = value),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: result.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => FleetError(
              error: error,
              onRetry: () =>
                  ref.invalidate(fleetFaultsProvider(widget.assetId)),
            ),
            data: (rows) {
              final filtered = rows
                  .where(
                    (fault) =>
                        (!fault.status.isActive) == _closed &&
                        (!_mine || fault.assignedTo == userId) &&
                        '${fault.assetName} ${fault.description} ${fault.assigneeName ?? ''}'
                            .toLowerCase()
                            .contains(_query),
                  )
                  .toList();
              return RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(fleetFaultsProvider(widget.assetId));
                  await ref.read(fleetFaultsProvider(widget.assetId).future);
                },
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 104),
                  children: [
                    if (filtered.isEmpty)
                      FleetEmpty(
                        title: es
                            ? 'No hay fallas en esta vista'
                            : 'No faults in this view',
                        message: es
                            ? 'Cambia los filtros o reporta una falla cuando algo necesite atención.'
                            : 'Change the filters or report a fault when something needs attention.',
                      ),
                    ...filtered.map(
                      (fault) => FaultListCard(
                        fault: fault,
                        onTap: () async {
                          await context.push('/fleet/faults/${fault.id}');
                          if (mounted) refreshFleet(ref);
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _availability(bool es) {
    final result = ref.watch(fleetAssetsProvider);
    return result.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => FleetError(
        error: error,
        onRetry: () => ref.invalidate(fleetAssetsProvider),
      ),
      data: (all) {
        final assets = all
            .where((a) => widget.assetId == null || a.id == widget.assetId)
            .toList();
        final filtered = assets
            .where(
              (a) =>
                  (_state == null || a.state == _state) &&
                  '${a.name} ${a.location ?? ''}'.toLowerCase().contains(
                    _query,
                  ),
            )
            .toList();
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(fleetAssetsProvider);
            await ref.read(fleetAssetsProvider.future);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 104),
            children: [
              FleetSummary(assets: assets),
              const SizedBox(height: 12),
              DropdownButtonFormField<OperatingState>(
                initialValue: _state,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: es ? 'Filtrar estado' : 'Filter availability',
                ),
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: Text(es ? 'Todos los estados' : 'All states'),
                  ),
                  ...OperatingState.values.map(
                    (state) => DropdownMenuItem(
                      value: state,
                      child: Text(state.label(es)),
                    ),
                  ),
                ],
                onChanged: (state) => setState(() => _state = state),
              ),
              const SizedBox(height: 12),
              if (filtered.isEmpty)
                FleetEmpty(
                  title: es
                      ? 'No hay equipos en esta vista'
                      : 'No assets in this view',
                  message: es
                      ? 'Prueba otro filtro o pide a tu administrador que asigne tu flota.'
                      : 'Try another filter or ask your administrator to assign your fleet.',
                ),
              ...filtered.map(
                (asset) => FleetAssetCard(
                  asset: asset,
                  onTap: () async {
                    await context.push('/fleet/assets/${asset.id}');
                    if (mounted) refreshFleet(ref);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class FleetSummary extends StatelessWidget {
  const FleetSummary({super.key, required this.assets});
  final List<FleetAsset> assets;
  @override
  Widget build(BuildContext context) {
    final es = fleetSpanish(context);
    final unavailable = assets.where((a) => a.state.isDowntime).length;
    final faults = assets.fold<int>(0, (n, a) => n + a.openFaults);
    return Row(
      children: [
        Expanded(
          child: _Metric(
            value: '$unavailable',
            label: es ? 'No disponibles' : 'Unavailable',
            color: AppColors.warning,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _Metric(
            value: '$faults',
            label: es ? 'Fallas activas' : 'Active faults',
            color: AppColors.primaryLight,
          ),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.value,
    required this.label,
    required this.color,
  });
  final String value, label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.cardBorder),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(color: color),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: AppColors.textSecondary)),
      ],
    ),
  );
}

class FaultListCard extends StatelessWidget {
  const FaultListCard({super.key, required this.fault, required this.onTap});
  final FleetFault fault;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final es = fleetSpanish(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      fault.assetName,
                      style: const TextStyle(
                        color: AppColors.primaryLight,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                fault.description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FaultStatusBadge(status: fault.status),
                  if (fault.urgent)
                    FleetBadge(
                      label: es ? 'Urgente' : 'Urgent',
                      color: AppColors.error,
                      icon: Icons.priority_high,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                fault.assigneeName ??
                    (es ? 'Sin responsable asignado' : 'No mechanic assigned'),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                fleetDate(context, fault.updatedAt ?? fault.createdAt),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FleetAssetCard extends StatelessWidget {
  const FleetAssetCard({super.key, required this.asset, required this.onTap});
  final FleetAsset asset;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final es = fleetSpanish(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      asset.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
              if (asset.location?.isNotEmpty == true) ...[
                const SizedBox(height: 4),
                Text(
                  asset.location!,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
              const SizedBox(height: 12),
              OperatingStateBadge(state: asset.state),
              if (asset.reason != null) ...[
                const SizedBox(height: 10),
                Text(
                  asset.reason!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (asset.openFaults > 0) ...[
                const SizedBox(height: 10),
                Text(
                  es
                      ? '${asset.openFaults} fallas activas'
                      : '${asset.openFaults} active faults',
                  style: TextStyle(
                    color: asset.urgentFaults > 0
                        ? AppColors.warning
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
