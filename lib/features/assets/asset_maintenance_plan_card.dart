import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/service_intervals/service_interval_provider.dart';
import 'package:vortice_app/models/asset_service_interval.dart';

class AssetMaintenancePlanCard extends ConsumerWidget {
  final String assetId;
  final String routePrefix;
  final bool readOnly;

  const AssetMaintenancePlanCard({
    super.key,
    required this.assetId,
    required this.routePrefix,
    required this.readOnly,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final intervalsAsync = ref.watch(serviceIntervalsProvider(assetId));
    final intervals = intervalsAsync.valueOrNull ?? <AssetServiceInterval>[];
    final visibleCount = readOnly
        ? intervals.where((interval) => interval.enabled).length
        : intervals.length;
    final withParts = intervals
        .where((interval) =>
            (!readOnly || interval.enabled) &&
            interval.checklistTemplateId != null)
        .length;
    final route = readOnly
        ? '$routePrefix/assets/$assetId/maintenance-plan'
        : '$routePrefix/assets/$assetId/service-intervals';

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => context.push(route),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: const Border.fromBorderSide(
              BorderSide(color: AppColors.cardBorder)),
        ),
        child: Row(
          children: [
            const Icon(Icons.event_note_outlined, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(readOnly ? 'Parts & Maintenance' : 'Maintenance Plan',
                      style: Theme.of(context).textTheme.titleSmall),
                  Text(
                    intervalsAsync.isLoading
                        ? 'Loading intervals...'
                        : '$visibleCount interval${visibleCount == 1 ? '' : 's'} • $withParts kit${withParts == 1 ? '' : 's'}',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
