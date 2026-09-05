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
    final es = fleetSpanish(context);
    final result = ref.watch(fleetAssetsProvider);
    final assets = result.valueOrNull;
    final faults = assets?.fold<int>(0, (n, a) => n + a.openFaults);
    final down = assets?.where((a) => a.state.isDowntime).length;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 10,
        ),
        leading: const Icon(
          Icons.fact_check_outlined,
          color: AppColors.primaryLight,
          size: 30,
        ),
        title: Text(es ? 'Fallas y disponibilidad' : 'Faults & availability'),
        subtitle: Text(
          faults == null
              ? (es ? 'Abrir estado de la flota' : 'Open fleet readiness')
              : (es
                    ? '$faults fallas activas · $down no disponibles'
                    : '$faults active faults · $down unavailable'),
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
    final es = fleetSpanish(context);
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
                  const Icon(
                    Icons.fact_check_outlined,
                    color: AppColors.primaryLight,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      es ? 'Disponibilidad y fallas' : 'Availability & faults',
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
                  es
                      ? 'Abrir estado de disponibilidad'
                      : 'Open availability status',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              if (asset != null && asset.openFaults > 0) ...[
                const SizedBox(height: 8),
                Text(
                  es
                      ? '${asset.openFaults} fallas activas'
                      : '${asset.openFaults} active faults',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
