import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'organization_work_execution_test.dart'
    show ExecutionFixture, app, reveal;

void main() {
  testWidgets('invalid CAD rate keeps entered customer charges on screen', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final fixture = ExecutionFixture();
    (fixture.data['work_order'] as Map)['status'] = 'closed';
    fixture.data['can_bill'] = true;
    await tester.pumpWidget(app(fixture));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Generate invoice'));
    await tester.tap(find.text('Generate invoice'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 9));
    await tester.pumpAndSettle();
    final labour = find.widgetWithText(TextField, 'Labour rate (USD/hour)');
    final cad = find.widgetWithText(TextField, 'CAD per USD');
    expect(cad, findsOneWidget);
    await tester.enterText(labour, '100');
    await tester.enterText(
      find.widgetWithText(TextField, 'MXN per USD'),
      '17.5',
    );
    await tester.enterText(cad, '0');
    await tester.ensureVisible(find.text('Generate invoice draft'));
    await tester.tap(find.text('Generate invoice draft'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a positive exchange rate.'), findsOneWidget);
    expect(tester.widget<TextField>(labour).controller!.text, '100');
    expect(tester.widget<TextField>(cad).controller!.text, '0');
    expect(tester.takeException(), isNull);
  });
}
