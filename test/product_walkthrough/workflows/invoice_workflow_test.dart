import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/invoices/invoice_detail_support.dart';

/// Backlog: A007, A008
void main() {
  group('Invoice workflow (A007, A008)', () {
    group('A008 currency conversion regression', () {
      test('USD labour converts to MXN with documented exchange rate', () {
        const hours = 2.0;
        const rateUsd = 100.0;
        const exchangeRate = 17.5;
        final labourUsd = computeLabourTotal(hours, rateUsd);
        final labourMxn = convertInvoiceAmount(
          labourUsd,
          showMxn: true,
          exchangeRate: exchangeRate,
        );

        expect(labourUsd, 200);
        expect(labourMxn, 3500);
      });
    });
  });
}
