import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/core/invoice_service.dart';

void main() {
  test('parses both currencies from one USD response at stored precision', () {
    final rates = ExchangeRateResult.fromResponse({
      'base': 'USD',
      'rates': {'CAD': 1.3751234, 'MXN': 17.51234},
    });
    expect(rates.rate, 17.5123);
    expect(rates.cadRate, 1.375123);
    expect(rates.isFallback, isFalse);
  });
  test('rejects wrong-base, missing and invalid exchange rates', () {
    for (final data in [
      {
        'base': 'CAD',
        'rates': {'CAD': 1, 'MXN': 17},
      },
      {
        'base': 'USD',
        'rates': {'MXN': 17},
      },
      for (final bad in [0, -1, double.nan, double.infinity])
        {
          'base': 'USD',
          'rates': {'CAD': bad, 'MXN': 17},
        },
    ]) {
      expect(() => ExchangeRateResult.fromResponse(data), throwsA(anything));
    }
  });
  test(
    'fetch uses both rates and never invents CAD after a provider failure',
    () async {
      final client = MockClient(
        (request) async => http.Response(
          '{"base":"USD","rates":{"MXN":17.5,"CAD":1.375}}',
          200,
        ),
      );
      final result = await InvoiceService.fetchExchangeRateResult(
        client: client,
      );
      expect(result.cadRate, 1.375);
      expect(result.rate, 17.5);
      final failed = await InvoiceService.fetchExchangeRateResult(
        client: MockClient((_) async => http.Response('{}', 503)),
      );
      expect(failed.isFallback, isTrue);
      expect(failed.cadRate, isNull);
    },
  );
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
