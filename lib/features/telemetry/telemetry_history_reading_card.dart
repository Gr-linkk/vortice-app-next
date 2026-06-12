import 'package:flutter/material.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/telemetry/telemetry_detail_row.dart';
import 'package:vortice_app/features/telemetry/telemetry_screen_support.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/models/telemetry_reading.dart';

class TelemetryHistoryReadingCard extends StatelessWidget {
  final TelemetryReading reading;

  const TelemetryHistoryReadingCard({super.key, required this.reading});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: const CircleAvatar(
          backgroundColor: AppColors.surfaceVariant,
          child: Icon(Icons.sensors, color: AppColors.primary, size: 18),
        ),
        title: Text(
          formatReadingDateTime(reading.ts),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        subtitle: reading.rpm != null
            ? Text(
                '${reading.rpm!.toStringAsFixed(0)} RPM',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12),
              )
            : null,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TelemetryDetailRow(
                    label: 'RPM', value: reading.rpm?.toStringAsFixed(0)),
                TelemetryDetailRow(
                    label: l10n.coolantTemp,
                    value: reading.coolantTemp != null
                        ? '${reading.coolantTemp!.toStringAsFixed(1)}°C'
                        : null),
                TelemetryDetailRow(
                    label: l10n.oilPressure,
                    value: reading.oilPressure != null
                        ? '${reading.oilPressure!.toStringAsFixed(1)} PSI'
                        : null),
                TelemetryDetailRow(
                    label: l10n.battery,
                    value: reading.batteryV != null
                        ? '${reading.batteryV!.toStringAsFixed(2)}V'
                        : null),
                TelemetryDetailRow(
                    label: l10n.boostPressure,
                    value: reading.boostPsi != null
                        ? '${reading.boostPsi!.toStringAsFixed(1)} PSI'
                        : null),
                TelemetryDetailRow(
                    label: l10n.throttle,
                    value: reading.throttlePct != null
                        ? '${reading.throttlePct!.toStringAsFixed(0)}%'
                        : null),
                TelemetryDetailRow(
                    label: l10n.fuelRate,
                    value: reading.fuelRate != null
                        ? '${reading.fuelRate!.toStringAsFixed(2)} L/hr'
                        : null),
                TelemetryDetailRow(
                    label: l10n.torque,
                    value: reading.torquePct != null
                        ? '${reading.torquePct!.toStringAsFixed(0)}%'
                        : null),
                TelemetryDetailRow(
                    label: l10n.engineHours,
                    value: reading.engineHours?.toStringAsFixed(1)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
