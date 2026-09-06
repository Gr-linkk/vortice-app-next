import 'package:vortice_app/core/user_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/telemetry/telemetry_history_alert_card.dart';
import 'package:vortice_app/features/telemetry/telemetry_provider.dart';
import 'package:vortice_app/l10n/app_localizations.dart';

class TelemetryHistoryAlertsTab extends ConsumerWidget {
  final String? assetId;
  final String? engineId;

  const TelemetryHistoryAlertsTab({
    super.key,
    required this.assetId,
    required this.engineId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final alertsAsync = assetId != null
        ? ref.watch(allAlertsForAssetProvider(assetId!))
        : ref.watch(alertsForEngineProvider(engineId!));

    return alertsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(
        child: Text(friendlyError(context, err),
            style: const TextStyle(color: AppColors.error)),
      ),
      data: (alerts) {
        if (alerts.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle,
                    size: 48, color: AppColors.success),
                const SizedBox(height: 12),
                Text(
                  l10n.noAlerts,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            if (assetId != null) {
              ref.invalidate(allAlertsForAssetProvider(assetId!));
            } else {
              ref.invalidate(alertsForEngineProvider(engineId!));
            }
          },
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: alerts.length,
            itemBuilder: (_, i) =>
                TelemetryHistoryAlertCard(alert: alerts[i]),
          ),
        );
      },
    );
  }
}
