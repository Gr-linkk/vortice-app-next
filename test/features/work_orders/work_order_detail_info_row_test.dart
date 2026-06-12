import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/work_orders/work_order_detail_info_row.dart';

void main() {
  testWidgets('WorkOrderDetailInfoRow renders label and value', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: WorkOrderDetailInfoRow(
            icon: Icons.build_outlined,
            label: 'Asset',
            value: 'Dredge Alpha',
          ),
        ),
      ),
    );

    expect(find.text('Asset: '), findsOneWidget);
    expect(find.text('Dredge Alpha'), findsOneWidget);
    expect(find.byIcon(Icons.build_outlined), findsOneWidget);
  });
}
