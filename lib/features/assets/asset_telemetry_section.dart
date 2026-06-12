import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/clients/client_capability_gate.dart';
import 'package:vortice_app/features/telemetry/telemetry_provider.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/models/asset.dart';
import 'package:vortice_app/models/client_capability.dart';

import 'asset_device_status_strip.dart';

class AssetTelemetrySection extends StatelessWidget {
  final Asset asset;

  const AssetTelemetrySection({super.key, required this.asset});

  @override
  Widget build(BuildContext context) {
    return ClientCapabilityGate(
      clientId: asset.clientId,
      capability: ClientCapability.telemetry,
      loadingBuilder: (_) => const Center(child: CircularProgressIndicator()),
      blockedBuilder: (_) => const ClientCapabilityDisabledPanel(
        capability: ClientCapability.telemetry,
      ),
      allowedBuilder: (_) => Column(
        children: [
          AssetDeviceStatusStrip(assetId: asset.id),
          const SizedBox(height: 16),
          AssetTelemCard(assetId: asset.id),
        ],
      ),
    );
  }
}

class AssetTelemCard extends ConsumerWidget {
  final String assetId;

  const AssetTelemCard({super.key, required this.assetId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final readingAsync = ref.watch(latestTelemetryForAssetProvider(assetId));
    final alertsAsync = ref.watch(alertsForAssetProvider(assetId));
    final alertCount = alertsAsync.valueOrNull?.length ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: const Border.fromBorderSide(
            BorderSide(color: AppColors.cardBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.speed, color: AppColors.primary, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.liveTelemetry,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (alertCount > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: AppColors.warning.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.warning_amber,
                          color: AppColors.warning, size: 12),
                      const SizedBox(width: 4),
                      Text(
                        '$alertCount',
                        style: const TextStyle(
                            color: AppColors.warning,
                            fontSize: 11,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                color: AppColors.textSecondary,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () =>
                    ref.invalidate(latestTelemetryForAssetProvider(assetId)),
                tooltip: 'Refresh',
              ),
            ],
          ),
          const SizedBox(height: 12),
          readingAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, __) => Text(l10n.noTelemetry,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
            data: (reading) {
              if (reading == null) {
                return Text(l10n.noTelemetry,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12));
              }
              final ts = reading.ts.toLocal();
              final timeStr =
                  '${ts.year}-${ts.month.toString().padLeft(2, '0')}-'
                  '${ts.day.toString().padLeft(2, '0')} '
                  '${ts.hour.toString().padLeft(2, '0')}:'
                  '${ts.minute.toString().padLeft(2, '0')}';

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${l10n.lastReading}: $timeStr',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 11),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 20,
                    runSpacing: 10,
                    children: [
                      if (reading.rpm != null)
                        AssetTeleStat(l10n.rpm, reading.rpm!.toStringAsFixed(0)),
                      if (reading.coolantTemp != null)
                        AssetTeleStat(l10n.coolantTemp,
                            '${reading.coolantTemp!.toStringAsFixed(1)}°C'),
                      if (reading.oilPressure != null)
                        AssetTeleStat(l10n.oilPressure,
                            '${reading.oilPressure!.toStringAsFixed(1)} PSI'),
                      if (reading.batteryV != null)
                        AssetTeleStat(l10n.batteryVoltage,
                            '${reading.batteryV!.toStringAsFixed(2)}V'),
                      if (reading.throttlePct != null)
                        AssetTeleStat(l10n.throttle,
                            '${reading.throttlePct!.toStringAsFixed(0)}%'),
                      if (reading.fuelRate != null)
                        AssetTeleStat(l10n.fuelRate,
                            '${reading.fuelRate!.toStringAsFixed(2)} L/h'),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () =>
                  context.push('/telemetry/assets/$assetId/history'),
              icon: const Icon(Icons.history, size: 14),
              label: Text(l10n.telemetryHistory,
                  style: const TextStyle(fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }
}

class AssetTeleStat extends StatelessWidget {
  final String label;
  final String value;

  const AssetTeleStat(this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style:
                const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
        Text(value,
            style: const TextStyle(
                color: AppColors.primary,
                fontSize: 14,
                fontWeight: FontWeight.bold)),
      ],
    );
  }
}
