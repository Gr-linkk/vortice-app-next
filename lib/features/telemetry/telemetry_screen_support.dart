import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/models/telemetry_alert.dart';

String formatTelemetryTime(DateTime dt) {
  return DateFormat('HH:mm:ss').format(dt.toLocal());
}

String formatTelemetryDate(DateTime date) {
  return '${date.day}/${date.month}/${date.year}';
}

String formatReadingDateTime(DateTime dt) {
  return '${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

String formatAlertDateTime(DateTime dt) {
  return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

String formatServiceReportShortDate(DateTime dt) {
  return DateFormat('MMM d').format(dt);
}

Color coolantTelemetryColor(AppPalette colors, double? temp) {
  if (temp == null) return colors.textSecondary;
  if (temp > 95) return colors.error;
  if (temp > 85) return colors.warning;
  return colors.success;
}

Color batteryTelemetryColor(AppPalette colors, double? v) {
  if (v == null) return colors.textSecondary;
  if (v < 12.0) return colors.error;
  if (v < 12.4) return colors.warning;
  return colors.success;
}

Color alertSeverityColor(AppPalette colors, AlertSeverity severity) {
  return switch (severity) {
    AlertSeverity.critical => colors.error,
    AlertSeverity.warning => colors.warning,
    AlertSeverity.info => colors.primary,
  };
}

IconData alertTypeIcon(TelemetryAlertType type) {
  return switch (type) {
    TelemetryAlertType.dtc => Icons.error_outline,
    TelemetryAlertType.threshold => Icons.speed,
    TelemetryAlertType.warning => Icons.warning_amber,
    TelemetryAlertType.critical => Icons.dangerous,
    TelemetryAlertType.info => Icons.info_outline,
  };
}

String maintenanceHoursRemainingLabel(double hoursRemaining) {
  if (hoursRemaining <= 0) return 'Overdue';
  return '${hoursRemaining.toStringAsFixed(0)} hrs';
}

Color maintenanceHoursRemainingColor(AppPalette colors, double hoursRemaining) {
  return hoursRemaining <= 0 ? colors.error : colors.textSecondary;
}
