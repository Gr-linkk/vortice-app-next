import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/telemetry/telemetry_history_reading_card.dart';
import 'package:vortice_app/features/telemetry/telemetry_provider.dart';
import 'package:vortice_app/l10n/app_localizations.dart';

class TelemetryHistoryReadingsTab extends ConsumerWidget {
  final String? assetId;
  final String? engineId;
  final DateTimeRange dateRange;

  const TelemetryHistoryReadingsTab({
    super.key,
    required this.assetId,
    required this.engineId,
    required this.dateRange,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final readingsAsync = assetId != null
        ? ref.watch(
            telemetryHistoryForAssetProvider((
              assetId: assetId!,
              from: dateRange.start,
              to: dateRange.end,
            )),
          )
        : ref.watch(
            telemetryHistoryProvider((
              engineId: engineId!,
              from: dateRange.start,
              to: dateRange.end,
            )),
          );

    return readingsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(
        child: Text(err.toString(),
            style: const TextStyle(color: AppColors.error)),
      ),
      data: (readings) {
        if (readings.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.sensors_off,
                    size: 48, color: AppColors.textSecondary),
                const SizedBox(height: 12),
                Text(
                  l10n.noTelemetryData,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            if (assetId != null) {
              ref.invalidate(telemetryHistoryForAssetProvider((
                assetId: assetId!,
                from: dateRange.start,
                to: dateRange.end,
              )));
            } else {
              ref.invalidate(telemetryHistoryProvider((
                engineId: engineId!,
                from: dateRange.start,
                to: dateRange.end,
              )));
            }
          },
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: readings.length,
            itemBuilder: (_, i) =>
                TelemetryHistoryReadingCard(reading: readings[i]),
          ),
        );
      },
    );
  }
}
