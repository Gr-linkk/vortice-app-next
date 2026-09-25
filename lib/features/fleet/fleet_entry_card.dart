import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/fleet/fleet_providers.dart';
import 'package:vortice_app/features/fleet/fleet_widgets.dart';

class FleetEntryCard extends ConsumerWidget {
  const FleetEntryCard({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(fleetAssetsProvider);
    final assets = result.valueOrNull;
    final faults = assets?.fold<int>(0, (n, a) => n + a.openFaults);
    final down = assets?.where((a) => a.state.isDowntime).length;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
        leading: Icon(
          Icons.fact_check_outlined,
          color: context.appColors.primaryLight,
          size: 22,
        ),
        title: Text(
          fleetText(
            context,
            'Faults & availability',
            'Fallas y disponibilidad',
            'Défaillances et disponibilité',
          ),
        ),
        subtitle: Text(
          faults == null
              ? fleetText(
                  context,
                  'Open fleet readiness',
                  'Abrir estado de la flota',
                  'Ouvrir l’état du parc',
                )
              : fleetText(
                  context,
                  '$faults active faults · $down unavailable',
                  '$faults fallas activas · $down no disponibles',
                  '$faults défaillances actives · $down indisponibles',
                ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          await context.push('/fleet');
          if (context.mounted) ref.invalidate(fleetAssetsProvider);
        },
      ),
    );
  }
}

class AssetReadinessCard extends ConsumerWidget {
  const AssetReadinessCard({super.key, required this.assetId});
  final String assetId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(fleetAssetsProvider);
    final asset = result.valueOrNull?.where((a) => a.id == assetId).firstOrNull;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: () async {
          await context.push('/fleet/assets/$assetId');
          if (context.mounted) ref.invalidate(fleetAssetsProvider);
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.fact_check_outlined,
                    color: context.appColors.primaryLight,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      fleetText(
                        context,
                        'Availability & faults',
                        'Disponibilidad y fallas',
                        'Disponibilité et défaillances',
                      ),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              const SizedBox(height: 12),
              if (asset != null)
                OperatingStateBadge(state: asset.state)
              else
                Text(
                  fleetText(
                    context,
                    'Open availability status',
                    'Abrir estado de disponibilidad',
                    'Ouvrir l’état de disponibilité',
                  ),
                  style: TextStyle(color: context.appColors.textSecondary),
                ),
              if (asset != null && asset.openFaults > 0) ...[
                const SizedBox(height: 8),
                Text(
                  fleetText(
                    context,
                    '${asset.openFaults} active faults',
                    '${asset.openFaults} fallas activas',
                    '${asset.openFaults} défaillances actives',
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
