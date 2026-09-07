import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/invoices/invoice_detail_support.dart';
import 'package:vortice_app/models/invoice.dart';
import 'package:vortice_app/models/profile.dart';

void main() {
  test('uses the supplied dark palette', () {
    expect(
      invoiceStatusColor(AppPalette.dark, InvoiceStatus.paid),
      AppPalette.dark.success,
    );
  });
  group('invoiceStatusColor', () {
    test('maps each invoice status to the expected theme color', () {
      expect(
        invoiceStatusColor(AppPalette.light, InvoiceStatus.paid),
        AppPalette.light.success,
      );
      expect(
        invoiceStatusColor(AppPalette.light, InvoiceStatus.sent),
        AppPalette.light.warning,
      );
      expect(
        invoiceStatusColor(AppPalette.light, InvoiceStatus.draft),
        AppPalette.light.textSecondary,
      );
      expect(
        invoiceStatusColor(AppPalette.light, InvoiceStatus.voided),
        AppPalette.light.error,
      );
    });
  });

  group('isInvoiceEditingLocked', () {
    test('locks sent and paid invoices', () {
      expect(isInvoiceEditingLocked(InvoiceStatus.sent), isTrue);
      expect(isInvoiceEditingLocked(InvoiceStatus.paid), isTrue);
    });

    test('only drafts can be edited', () {
      expect(isInvoiceEditingLocked(InvoiceStatus.draft), isFalse);
      expect(isInvoiceEditingLocked(InvoiceStatus.voided), isTrue);
    });
  });

  group('canMarkInvoicePaidFromList', () {
    test('requires issue before owners can mark paid', () {
      expect(
        canMarkInvoicePaidFromList(
          role: UserRole.owner,
          status: InvoiceStatus.draft,
        ),
        isFalse,
      );
      expect(
        canMarkInvoicePaidFromList(
          role: UserRole.owner,
          status: InvoiceStatus.sent,
        ),
        isTrue,
      );
    });

    test('hides paid action for non-owner roles', () {
      for (final role in [
        UserRole.employee,
        UserRole.client,
        UserRole.clientAdmin,
        UserRole.clientMechanic,
        UserRole.clientOperator,
        UserRole.operator,
      ]) {
        expect(
          canMarkInvoicePaidFromList(role: role, status: InvoiceStatus.sent),
          isFalse,
          reason: '$role should not see owner invoice payment actions',
        );
      }
    });

    test('hides paid action for already-final statuses', () {
      expect(
        canMarkInvoicePaidFromList(
          role: UserRole.owner,
          status: InvoiceStatus.paid,
        ),
        isFalse,
      );
      expect(
        canMarkInvoicePaidFromList(
          role: UserRole.owner,
          status: InvoiceStatus.voided,
        ),
        isFalse,
      );
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
      expect(convertInvoiceAmount(null, showMxn: false, exchangeRate: 20), 0);
    });

    test('returns USD unchanged when not showing MXN', () {
      expect(convertInvoiceAmount(10, showMxn: false, exchangeRate: 20), 10);
    });

    test('multiplies by exchange rate when showing MXN', () {
      expect(convertInvoiceAmount(10, showMxn: true, exchangeRate: 20.5), 205);
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
      expect(formatInvoiceDate(DateTime(2026, 6, 12)), '12/6/2026');
    });
  });
}
