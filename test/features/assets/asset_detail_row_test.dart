import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/assets/asset_detail_row.dart';

void main() {
  testWidgets('AssetDetailRow renders label and value', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AssetDetailRow(
            label: 'Serial Number',
            value: 'SN-12345',
          ),
        ),
      ),
    );

    expect(find.text('Serial Number'), findsOneWidget);
    expect(find.text('SN-12345'), findsOneWidget);
  });

  testWidgets('AssetDetailRow hides when value is null', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AssetDetailRow(
            label: 'Year',
          ),
        ),
      ),
    );

    expect(find.text('Year'), findsNothing);
    expect(find.byType(SizedBox), findsWidgets);
  });
}
