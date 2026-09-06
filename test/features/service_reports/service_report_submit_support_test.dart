import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/service_reports/service_report_submit_support.dart';

void main() {
  group('validateServiceReportWorkOrderSelection', () {
    test('requires a selected work order', () {
      expect(
        validateServiceReportWorkOrderSelection(null),
        serviceReportMissingWorkOrderMessage,
      );
      expect(validateServiceReportWorkOrderSelection(''), isNotNull);
      expect(validateServiceReportWorkOrderSelection('wo-1'), isNull);
    });
  });

  group('resolveServiceReportSubmitOutcome', () {
    test('returns null when report id is missing', () {
      expect(
        resolveServiceReportSubmitOutcome(
          reportId: null,
          photosUploaded: true,
          hadPhotos: false,
        ),
        isNull,
      );
    });

    test('resets and pops when photos uploaded successfully', () {
      final outcome = resolveServiceReportSubmitOutcome(
        reportId: 'report-1',
        photosUploaded: true,
        hadPhotos: true,
      );

      expect(outcome?.shouldResetForm, isTrue);
      expect(outcome?.shouldPop, isTrue);
      expect(outcome?.showPhotosPendingWarning, isFalse);
    });

    test('keeps draft open when photo upload fails', () {
      final outcome = resolveServiceReportSubmitOutcome(
        reportId: 'report-1',
        photosUploaded: false,
        hadPhotos: true,
      );

      expect(outcome?.pendingReportId, 'report-1');
      expect(outcome?.shouldResetForm, isFalse);
      expect(outcome?.shouldPop, isFalse);
      expect(outcome?.showPhotosPendingWarning, isTrue);
    });

    test('local-only save never claims successful remote submission', () {
      final outcome = resolveServiceReportSubmitOutcome(
        reportId: 'pending-report',
        photosUploaded: true,
        hadPhotos: false,
        reportSynced: false,
      );
      expect(outcome?.showReportPendingWarning, isTrue);
      expect(outcome?.showPhotosPendingWarning, isFalse);
    });
  });
}
