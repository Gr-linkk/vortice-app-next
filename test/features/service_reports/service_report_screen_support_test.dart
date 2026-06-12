import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/service_reports/service_report_screen_support.dart';

void main() {
  group('buildServiceReportPayload', () {
    test('omits empty text fields and includes signature metadata', () {
      final payload = buildServiceReportPayload(
        selectedWorkOrderId: 'wo-1',
        complaint: 'Pump noise',
        cause: '  ',
        correction: 'Replaced seal',
        collateral: '',
        comments: 'Customer notified',
        signatureUrl: 'https://example.com/sig.png',
      );

      expect(payload['work_order_id'], 'wo-1');
      expect(payload['complaint'], 'Pump noise');
      expect(payload['cause'], isNull);
      expect(payload['correction'], 'Replaced seal');
      expect(payload['collateral'], isNull);
      expect(payload['comments'], 'Customer notified');
      expect(payload['tech_signature_url'], 'https://example.com/sig.png');
      expect(payload['signed_at'], isA<String>());
    });

    test('clears blank work order id', () {
      final payload = buildServiceReportPayload(
        selectedWorkOrderId: '',
        complaint: '',
        cause: '',
        correction: '',
        collateral: '',
        comments: '',
      );

      expect(payload['work_order_id'], isNull);
      expect(payload.containsKey('tech_signature_url'), isFalse);
    });

    test('trims whitespace from populated text fields', () {
      final payload = buildServiceReportPayload(
        selectedWorkOrderId: 'wo-2',
        complaint: '  noise  ',
        cause: 'wear',
        correction: '  replaced bearing ',
        collateral: ' none ',
        comments: 'done',
      );

      expect(payload['complaint'], 'noise');
      expect(payload['correction'], 'replaced bearing');
      expect(payload['collateral'], 'none');
    });
  });

  group('service report user-facing messages', () {
    test('exposes non-empty reconnect guidance for submit failures', () {
      expect(serviceReportSubmitFailedMessage, isNotEmpty);
      expect(serviceReportSignatureFailedMessage, isNotEmpty);
      expect(serviceReportPhotosPendingMessage, isNotEmpty);
      expect(serviceReportSubmitFailedMessage, contains('submitted'));
      expect(serviceReportPhotosPendingMessage, contains('photos'));
    });
  });
}
