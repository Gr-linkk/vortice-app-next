import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/invoices/invoice_detail_support.dart';
import 'package:vortice_app/models/invoice.dart';

void main() {
  group('invoiceStatusColor', () {
    test('maps each invoice status to the expected theme color', () {
      expect(invoiceStatusColor(InvoiceStatus.paid), AppColors.success);
      expect(invoiceStatusColor(InvoiceStatus.sent), AppColors.warning);
      expect(invoiceStatusColor(InvoiceStatus.draft), AppColors.textSecondary);
      expect(invoiceStatusColor(InvoiceStatus.voided), AppColors.error);
    });
  });

  group('isInvoiceEditingLocked', () {
    test('locks sent and paid invoices', () {
      expect(isInvoiceEditingLocked(InvoiceStatus.sent), isTrue);
      expect(isInvoiceEditingLocked(InvoiceStatus.paid), isTrue);
    });

    test('allows draft and voided invoices', () {
      expect(isInvoiceEditingLocked(InvoiceStatus.draft), isFalse);
      expect(isInvoiceEditingLocked(InvoiceStatus.voided), isFalse);
    });
  });

  group('formatInvoiceCurrency', () {
    test('formats USD and MXN with defaults for null', () {
      expect(formatInvoiceCurrency(null), '\$0.00 USD');
      expect(formatInvoiceCurrency(null, mxn: true), '\$0.00 MXN');
    });

    test('formats values with two decimal places', () {
      expect(formatInvoiceCurrency(12.5), '\$12.50 USD');
      expect(formatInvoiceCurrency(99.999, mxn: true), '\$100.00 MXN');
    });
  });

  group('convertInvoiceAmount', () {
    test('returns zero for null USD', () {
      expect(
        convertInvoiceAmount(null, showMxn: false, exchangeRate: 20),
        0,
      );
    });

    test('returns USD unchanged when not showing MXN', () {
      expect(
        convertInvoiceAmount(10, showMxn: false, exchangeRate: 20),
        10,
      );
    });

    test('multiplies by exchange rate when showing MXN', () {
      expect(
        convertInvoiceAmount(10, showMxn: true, exchangeRate: 20.5),
        205,
      );
    });
  });

  group('computeLabourTotal', () {
    test('multiplies hours and rate with null-safe defaults', () {
      expect(computeLabourTotal(2, 60), 120);
      expect(computeLabourTotal(null, 60), 0);
      expect(computeLabourTotal(2, null), 0);
    });
  });

  group('computeConsumablesTotal', () {
    test('calculates 5% of labour total', () {
      expect(computeConsumablesTotal(10, 60), 30);
      expect(formatConsumablesTotal(10, 60), '30.00');
    });
  });

  group('formatInvoiceDate', () {
    test('returns placeholder for null date', () {
      expect(formatInvoiceDate(null), '-');
    });

    test('formats day/month/year', () {
      expect(
        formatInvoiceDate(DateTime(2026, 6, 12)),
        '12/6/2026',
      );
    });
  });
}
