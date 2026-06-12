import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/assets/asset_detail_support.dart';
import 'package:vortice_app/features/assets/asset_workflow_summary.dart';

void main() {
  group('formatAssetChecklistSummaryValue', () {
    test('returns placeholder when checklist is null', () {
      expect(formatAssetChecklistSummaryValue(null), 'None saved yet');
    });

    test('formats checklist name and submission date', () {
      final summary = AssetChecklistSummary(
        name: 'Daily Ops',
        submittedAt: DateTime(2026, 6, 1, 14, 30),
      );

      expect(
        formatAssetChecklistSummaryValue(summary),
        'Daily Ops • Jun 1, 2026',
      );
    });
  });

  group('formatAssetPmDueSummaryValue', () {
    test('returns nothing due when count is zero', () {
      const summary = AssetPmDueSummary(
        visible: true,
        dueOrOverdueCount: 0,
        labels: [],
      );

      expect(formatAssetPmDueSummaryValue(summary), 'Nothing due');
    });

    test('formats single interval label', () {
      const summary = AssetPmDueSummary(
        visible: true,
        dueOrOverdueCount: 1,
        labels: ['250h Service'],
      );

      expect(
        formatAssetPmDueSummaryValue(summary),
        '1 interval • 250h Service',
      );
    });

    test('truncates labels and shows overflow count', () {
      const summary = AssetPmDueSummary(
        visible: true,
        dueOrOverdueCount: 4,
        labels: ['250h Service', '500h Service', '750h Service', '1000h Service'],
      );

      expect(
        formatAssetPmDueSummaryValue(summary),
        '4 intervals • 250h Service, 500h Service +2 more',
      );
    });
  });

  group('formatDeviceMinutesAgo', () {
    test('returns just now for recent timestamps', () {
      final now = DateTime.now();
      expect(formatDeviceMinutesAgo(now), 'just now');
    });

    test('returns minutes ago for older timestamps', () {
      final fiveMinutesAgo = DateTime.now().subtract(const Duration(minutes: 5));
      expect(formatDeviceMinutesAgo(fiveMinutesAgo), '5m ago');
    });
  });

  group('formatDeviceRelativeTime', () {
    test('returns minutes for recent timestamps', () {
      final thirtyMinutesAgo =
          DateTime.now().subtract(const Duration(minutes: 30));
      expect(formatDeviceRelativeTime(thirtyMinutesAgo), '30m ago');
    });

    test('returns hours for same-day timestamps', () {
      final threeHoursAgo = DateTime.now().subtract(const Duration(hours: 3));
      expect(formatDeviceRelativeTime(threeHoursAgo), '3h ago');
    });

    test('returns days for older timestamps', () {
      final twoDaysAgo = DateTime.now().subtract(const Duration(days: 2));
      expect(formatDeviceRelativeTime(twoDaysAgo), '2d ago');
    });
  });
}
