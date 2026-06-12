import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/telemetry/telemetry_screen_support.dart';
import 'package:vortice_app/models/telemetry_alert.dart';

void main() {
  group('formatTelemetryTime', () {
    test('formats local time as HH:mm:ss', () {
      final dt = DateTime(2026, 6, 12, 14, 5, 9);
      expect(formatTelemetryTime(dt), '14:05:09');
    });
  });

  group('formatTelemetryDate', () {
    test('formats day/month/year', () {
      final dt = DateTime(2026, 3, 5);
      expect(formatTelemetryDate(dt), '5/3/2026');
    });
  });

  group('formatReadingDateTime', () {
    test('formats day/month and time without year', () {
      final dt = DateTime(2026, 6, 12, 9, 7);
      expect(formatReadingDateTime(dt), '12/6 09:07');
    });

    test('zero-pads minutes', () {
      final dt = DateTime(2026, 1, 2, 8, 3);
      expect(formatReadingDateTime(dt), '2/1 08:03');
    });
  });

  group('formatAlertDateTime', () {
    test('formats full date and time', () {
      final dt = DateTime(2026, 12, 25, 23, 4);
      expect(formatAlertDateTime(dt), '25/12/2026 23:04');
    });
  });

  group('formatServiceReportShortDate', () {
    test('formats month abbreviation and day', () {
      final dt = DateTime(2026, 6, 12);
      expect(formatServiceReportShortDate(dt), 'Jun 12');
    });
  });

  group('coolantTelemetryColor', () {
    test('returns secondary when temp is null', () {
      expect(coolantTelemetryColor(null), AppColors.textSecondary);
    });

    test('returns success at or below 85', () {
      expect(coolantTelemetryColor(85), AppColors.success);
      expect(coolantTelemetryColor(80), AppColors.success);
    });

    test('returns warning above 85 up to 95', () {
      expect(coolantTelemetryColor(86), AppColors.warning);
      expect(coolantTelemetryColor(95), AppColors.warning);
    });

    test('returns error above 95', () {
      expect(coolantTelemetryColor(96), AppColors.error);
    });
  });

  group('batteryTelemetryColor', () {
    test('returns secondary when voltage is null', () {
      expect(batteryTelemetryColor(null), AppColors.textSecondary);
    });

    test('returns error below 12.0', () {
      expect(batteryTelemetryColor(11.9), AppColors.error);
    });

    test('returns warning from 12.0 up to 12.4', () {
      expect(batteryTelemetryColor(12.0), AppColors.warning);
      expect(batteryTelemetryColor(12.3), AppColors.warning);
    });

    test('returns success at or above 12.4', () {
      expect(batteryTelemetryColor(12.4), AppColors.success);
      expect(batteryTelemetryColor(13.0), AppColors.success);
    });
  });

  group('alertSeverityColor', () {
    test('maps severities to theme colors', () {
      expect(alertSeverityColor(AlertSeverity.critical), AppColors.error);
      expect(alertSeverityColor(AlertSeverity.warning), AppColors.warning);
      expect(alertSeverityColor(AlertSeverity.info), AppColors.primary);
    });
  });

  group('alertTypeIcon', () {
    test('maps alert types to icons', () {
      expect(alertTypeIcon(TelemetryAlertType.dtc), Icons.error_outline);
      expect(alertTypeIcon(TelemetryAlertType.threshold), Icons.speed);
      expect(alertTypeIcon(TelemetryAlertType.warning), Icons.warning_amber);
      expect(alertTypeIcon(TelemetryAlertType.critical), Icons.dangerous);
      expect(alertTypeIcon(TelemetryAlertType.info), Icons.info_outline);
    });
  });

  group('maintenanceHoursRemainingLabel', () {
    test('returns Overdue when zero or negative', () {
      expect(maintenanceHoursRemainingLabel(0), 'Overdue');
      expect(maintenanceHoursRemainingLabel(-5), 'Overdue');
    });

    test('returns rounded hours remaining', () {
      expect(maintenanceHoursRemainingLabel(42.7), '43 hrs');
    });
  });

  group('maintenanceHoursRemainingColor', () {
    test('returns error when overdue', () {
      expect(maintenanceHoursRemainingColor(0), AppColors.error);
    });

    test('returns secondary when hours remain', () {
      expect(maintenanceHoursRemainingColor(10), AppColors.textSecondary);
    });
  });
}
