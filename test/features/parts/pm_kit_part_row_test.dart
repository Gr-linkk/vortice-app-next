import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/parts/pm_kit_part_row.dart';

void main() {
  testWidgets('PmKitPartRow renders description, part number, and qty',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PmKitPartRow(
            part: const {
              'id': 'part-1',
              'description': 'Oil Filter',
              'part_number': 'OF-100',
              'qty': 2,
              'unit': 'ea',
            },
            templateId: 'tpl-1',
            onRefresh: () {},
          ),
        ),
      ),
    );

    expect(find.text('Oil Filter'), findsOneWidget);
    expect(find.text('PN: OF-100'), findsOneWidget);
    expect(find.text('2 ea'), findsOneWidget);
  });
}
