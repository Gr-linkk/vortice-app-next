import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'connected_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'large text can return to work focus and select customer equipment',
    (tester) async {
      await tester.runAsync(() async {
        final h = ConnectedHarness(tester, report: 'next006-work-focus-ui');
        await h.start();
        final accounts =
            (jsonDecode(
                      File(
                        'config/next006-fixtures.local.json',
                      ).readAsStringSync(),
                    )['accounts']
                    as List)
                .cast<Map>();
        final account = accounts.firstWhere((row) => row['purpose'] == 'both');
        h.passwords[account['email']] = account['password'];
        try {
          await h.login(account['email'] as String);
          await h.go('/maintenance/planning?filter=open');
          await h.tap(find.byTooltip('Search & filters'));
          final finder = find
              .descendant(
                of: find.byKey(const ValueKey('work-hub-list')),
                matching: find.byType(Scrollable),
              )
              .first;
          final scroll = tester.state<ScrollableState>(finder);
          scroll.position.jumpTo(scroll.position.maxScrollExtent);
          await tester.pump();
          tester.view.physicalSize = const Size(320, 844);
          tester.platformDispatcher.textScaleFactorTestValue = 2;
          await h.go('/maintenance/planning?filter=open');
          scroll.position.jumpTo(0);
          await h.settle();
          for (var retry = 0; retry < 8; retry++) {
            scroll.position.jumpTo(0);
            await tester.pump(const Duration(milliseconds: 100));
            if (scroll.position.pixels == 0) break;
          }
          await h.screenshot('work-focus-large-top');
          await h.tap(find.byKey(const ValueKey('work-focus-customer')));
          await h.tap(find.widgetWithText(FilledButton, 'Create work'));
          final field = find.byWidgetPredicate(
            (w) =>
                w is InputDecorator &&
                w.decoration.labelText == 'Customer equipment',
          );
          await h.tap(field);
          await h.screenshot('customer-dropdown-open-large');
          await h.tap(find.textContaining('NEXT006 fleet Company ·').first);
          await h.screenshot('customer-dropdown-selected-large');
          expect(tester.takeException(), isNull);
        } finally {
          tester.platformDispatcher.clearTextScaleFactorTestValue();
          await h.close();
        }
      });
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
