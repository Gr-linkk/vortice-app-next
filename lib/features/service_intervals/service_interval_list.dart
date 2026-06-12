import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/service_intervals/service_interval_card.dart';
import 'package:vortice_app/features/service_intervals/service_interval_provider.dart';
import 'package:vortice_app/models/asset.dart';

class ServiceIntervalList extends ConsumerWidget {
  final String assetId;
  final Asset? asset;
  final bool readOnly;
  final void Function(ServiceIntervalSummary summary)? onEdit;

  const ServiceIntervalList({
    super.key,
    required this.assetId,
    required this.asset,
    required this.readOnly,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final intervalsAsync = ref.watch(serviceIntervalSummariesProvider(assetId));

    return intervalsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(
        child: Text(err.toString(),
            style: const TextStyle(color: AppColors.error)),
      ),
      data: (intervals) {
        final visible = readOnly
            ? intervals.where((summary) => summary.interval.enabled).toList()
            : intervals;
        if (visible.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.schedule,
                    size: 48, color: AppColors.textSecondary),
                const SizedBox(height: 12),
                Text(
                  readOnly
                      ? 'No published maintenance plan yet.'
                      : 'No service intervals configured.\nTap + to add one.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          itemCount: visible.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) => ServiceIntervalCard(
            summary: visible[i],
            assetId: assetId,
            asset: asset,
            readOnly: readOnly,
            onEdit: onEdit,
          ),
        );
      },
    );
  }
}
