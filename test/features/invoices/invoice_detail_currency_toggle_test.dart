import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/invoices/invoice_detail_currency_toggle.dart';

void main() {
  testWidgets('InvoiceDetailCurrencyToggle calls onChanged for USD and MXN',
      (tester) async {
    bool? lastValue;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InvoiceDetailCurrencyToggle(
            showMxn: false,
            onChanged: (value) => lastValue = value,
          ),
        ),
      ),
    );

    expect(find.textContaining('USD'), findsOneWidget);
    expect(find.textContaining('MXN'), findsOneWidget);

    await tester.tap(find.textContaining('MXN'));
    await tester.pumpAndSettle();
    expect(lastValue, isTrue);

    await tester.tap(find.textContaining('USD'));
    await tester.pumpAndSettle();
    expect(lastValue, isFalse);
  });
}
