import 'package:flutter/material.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/telemetry/telemetry_screen_support.dart';
import 'package:vortice_app/models/telemetry_alert.dart';

class TelemetryHistoryAlertCard extends StatelessWidget {
  final TelemetryAlert alert;

  const TelemetryHistoryAlertCard({super.key, required this.alert});

  @override
  Widget build(BuildContext context) {
    final severityColor = alertSeverityColor(alert.severity);
    final icon = alertTypeIcon(alert.alertType);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: severityColor.withValues(alpha: 0.15),
          child: Icon(icon, color: severityColor, size: 20),
        ),
        title: Row(
          children: [
            if (alert.spn != null)
              Text('SPN ${alert.spn}',
                  style: Theme.of(context).textTheme.titleSmall)
            else if (alert.parameter != null)
              Text(alert.parameter!,
                  style: Theme.of(context).textTheme.titleSmall)
            else
              Text(alert.alertType.name.toUpperCase(),
                  style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
            if (!alert.acknowledged)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'NEW',
                  style: TextStyle(
                    color: AppColors.error,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (alert.message != null)
              Text(alert.message!, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            Text(
              formatAlertDateTime(alert.createdAt ?? DateTime.now()),
              style:
                  const TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
          ],
        ),
        isThreeLine: alert.message != null,
      ),
    );
  }
}
