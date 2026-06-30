import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/invoices/invoice_parts_line_items_support.dart';
import 'package:vortice_app/models/part.dart';

void main() {
  group('buildInvoicePartLineItems', () {
    test('computes line total with markup', () {
      final lines = buildInvoicePartLineItems([
        const Part(
          id: 'part-1',
          workOrderId: 'wo-1',
          description: 'Hydraulic hose',
          partNumber: 'HH-100',
          quantity: 2,
          unitCost: 50,
          markupPct: 15,
        ),
      ]);

      expect(lines, hasLength(1));
      expect(lines.first.lineTotalUsd, 115);
      expect(formatInvoicePartLineDetail(lines.first), '2 × \$50.00 + 15% markup');
      expect(
        formatInvoicePartLineLabel(lines.first),
        'Hydraulic hose (HH-100)',
      );
    });

    test('sumInvoicePartLineTotals aggregates all lines', () {
      final lines = buildInvoicePartLineItems([
        const Part(
          id: 'part-1',
          workOrderId: 'wo-1',
          description: 'Filter',
          quantity: 1,
          unitCost: 100,
          markupPct: 10,
        ),
        const Part(
          id: 'part-2',
          workOrderId: 'wo-1',
          description: 'Seal kit',
          quantity: 2,
          unitCost: 25,
          markupPct: 20,
        ),
      ]);

      expect(sumInvoicePartLineTotals(lines), 170);
    });
  });
}
