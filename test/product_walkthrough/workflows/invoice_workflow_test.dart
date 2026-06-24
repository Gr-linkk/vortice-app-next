import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/invoices/invoice_detail_support.dart';
import 'package:vortice_app/features/invoices/invoice_parts_line_items_policy.dart';

import '../workflow_test_support.dart';

/// Backlog: A007, A008
void main() {
  workflowTddGroup('invoice', 'Invoice workflow (A007, A008)', () {
    group('A007 itemized parts on invoice detail and export', () {
      test('invoice detail exposes itemized parts lines', () {
        expect(InvoicePartsLineItemsPolicy.detailShowsItemizedPartsLines(), isTrue);
      });

      test('invoice export exposes itemized parts lines', () {
        expect(InvoicePartsLineItemsPolicy.exportShowsItemizedPartsLines(), isTrue);
      });
    });

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
