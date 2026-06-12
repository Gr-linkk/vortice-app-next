import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/telemetry/telemetry_provider.dart';
import 'package:vortice_app/features/telemetry/telemetry_screen_support.dart';
import 'package:vortice_app/models/telemetry_alert.dart';

class VesselTelemetryFaultCodesSection extends ConsumerWidget {
  final String assetId;

  const VesselTelemetryFaultCodesSection({super.key, required this.assetId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alertsAsync = ref.watch(alertsForAssetProvider(assetId));

    return alertsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (alerts) {
        if (alerts.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
              child: Text('Fault Codes',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            ...alerts.map(
              (a) => VesselTelemetryFaultCodeTile(alert: a, assetId: assetId),
            ),
          ],
        );
      },
    );
  }
}

class VesselTelemetryFaultCodeTile extends ConsumerWidget {
  final TelemetryAlert alert;
  final String assetId;

  const VesselTelemetryFaultCodeTile({
    super.key,
    required this.alert,
    required this.assetId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final severityColor = alertSeverityColor(alert.severity);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: severityColor.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber, color: severityColor, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (alert.spn != null)
                    Text(
                      'SPN ${alert.spn}  FMI ${alert.fmi ?? '?'}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                          fontSize: 13),
                    )
                  else
                    Text(
                      alert.alertType.name.toUpperCase(),
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                          fontSize: 13),
                    ),
                  if (alert.message != null)
                    Text(
                      alert.message!,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                ],
              ),
            ),
            if (!alert.acknowledged)
              TextButton(
                onPressed: () async {
                  final profile = ref.read(profileProvider).valueOrNull;
                  if (profile == null) return;
                  await ref
                      .read(telemetryControllerProvider.notifier)
                      .acknowledgeAlert(alert.id, profile.id);
                  ref.invalidate(alertsForAssetProvider(assetId));
                },
                child: const Text('Acknowledge'),
              ),
          ],
        ),
      ),
    );
  }
}
