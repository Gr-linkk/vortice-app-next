import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/core/invoice_service.dart';

void main() {
  group('InvoiceService', () {
    test(
      'rejects negative and nonfinite edits before any backend write',
      () async {
        for (final value in [
          -1.0,
          double.nan,
          double.infinity,
          double.negativeInfinity,
        ]) {
          await expectLater(
            InvoiceService.updateInvoice('unused', labourHours: value),
            throwsArgumentError,
          );
          await expectLater(
            InvoiceService.updateInvoice('unused', partsTotal: value),
            throwsArgumentError,
          );
        }
      },
    );
    test('formats invoice numbers with date, time, and milliseconds', () {
      final number = InvoiceService.formatInvoiceNumber(
        DateTime(2026, 6, 13, 19, 56, 30, 42),
      );

      expect(number, 'INV-20260613-195630-042');
    });

    test('generates different invoice numbers within the same second', () {
      final first = InvoiceService.formatInvoiceNumber(
        DateTime(2026, 6, 13, 19, 56, 30, 42),
      );
      final second = InvoiceService.formatInvoiceNumber(
        DateTime(2026, 6, 13, 19, 56, 30, 43),
      );

      expect(first, isNot(second));
    });
  });
}
