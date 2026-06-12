import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/service_reports/service_report_draft_manager.dart';

void main() {
  group('ServiceReportDraftKeys', () {
    test('uses work-order-specific keys when provided', () {
      expect(
        ServiceReportDraftKeys.draftKey('wo-1'),
        'service_report_draft_wo-1',
      );
      expect(
        ServiceReportDraftKeys.draftMediaKey('wo-1'),
        'service_report_draft_wo-1_media',
      );
    });

    test('falls back to generic draft keys', () {
      expect(ServiceReportDraftKeys.draftKey(null), 'service_report_draft');
      expect(
        ServiceReportDraftKeys.draftMediaKey(''),
        'service_report_draft_media',
      );
    });
  });
}
