import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/service_reports/service_report_draft_codec.dart';

void main() {
  group('ServiceReportDraftCodec', () {
    test('keeps text draft payload separate from media payload', () {
      final text = ServiceReportDraftCodec.textPayload(
        workOrderId: 'wo-1',
        pendingReportId: 'report-1',
        complaint: 'Complaint',
        cause: 'Cause',
        correction: 'Correction',
        collateral: '',
        comments: '',
      );
      final media = ServiceReportDraftCodec.mediaPayload(
        Uint8List.fromList([1, 2, 3]),
        [
          Uint8List.fromList([4, 5, 6])
        ],
      );

      expect(text, isNot(contains('signatureBytes')));
      expect(text, isNot(contains('photos')));
      expect(media['signatureBytes'], base64Encode([1, 2, 3]));
      expect(media['photos'], [
        base64Encode([4, 5, 6])
      ]);
    });

    test('detects empty and populated draft sections independently', () {
      expect(
        ServiceReportDraftCodec.hasTextDraft(
          workOrderId: null,
          pendingReportId: null,
          complaint: '',
          cause: '',
          correction: '',
          collateral: '',
          comments: '',
        ),
        isFalse,
      );
      expect(
        ServiceReportDraftCodec.hasTextDraft(
          workOrderId: null,
          pendingReportId: null,
          complaint: '',
          cause: '',
          correction: 'Replaced impeller',
          collateral: '',
          comments: '',
        ),
        isTrue,
      );
      expect(ServiceReportDraftCodec.hasMediaDraft(null, const []), isFalse);
      expect(
        ServiceReportDraftCodec.hasMediaDraft(
          null,
          [
            Uint8List.fromList([1])
          ],
        ),
        isTrue,
      );
    });
  });
}
