import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/work_orders/work_order_log_hours_sheet.dart';
import 'package:vortice_app/features/work_orders/work_order_provider.dart';
import 'package:vortice_app/l10n/app_localizations.dart';

class RecordingController extends WorkOrderController {
  RecordingController(super.ref);
  final updates = <Map<String, dynamic>>[];

  @override
  Future<bool> updateWorkOrder(
    String id,
    Map<String, dynamic> data, {
    List<String>? assignedProfileIds,
  }) async {
    updates.add(data);
    return false;
  }
}

void main() {
  testWidgets(
    'rejects invalid hours, retains input, and accepts finite values',
    (tester) async {
      late RecordingController controller;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            workOrderControllerProvider.overrideWith((ref) {
              controller = RecordingController(ref);
              return controller;
            }),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: LogHoursSheet(workOrderId: 'test-work')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      for (final invalid in ['-1', 'abc', 'NaN', 'Infinity']) {
        await tester.enterText(fields.at(0), invalid);
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(controller.updates, isEmpty, reason: invalid);
        expect(find.text(invalid), findsOneWidget);
      }
      await tester.enterText(fields.at(0), '0.5');
      await tester.enterText(fields.at(1), '-2');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(controller.updates, isEmpty);
      await tester.enterText(fields.at(1), '101');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(controller.updates, [
        {'labour_hours': 0.5, 'hours_at_end': 101.0},
      ]);
    },
  );
}
