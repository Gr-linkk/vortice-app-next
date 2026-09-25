import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vortice_app/features/invoices/billing_profile.dart';
import 'package:vortice_app/features/invoices/billing_fields.dart';
import 'package:vortice_app/features/invoices/canadian_invoice_editor.dart';
import 'organization_work_execution_test.dart'
    show ExecutionFixture, app, reveal;

void main() {
  testWidgets(
    'approved customer work opens CAD setup before accepting charges',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final fixture = ExecutionFixture();
      (fixture.data['work_order'] as Map)['status'] = 'closed';
      fixture.data['can_bill'] = true;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            billingProfileProvider.overrideWith(
              (_) async => {
                'organization_id': 'company',
                'details': null,
                'can_manage': true,
              },
            ),
          ],
          child: app(fixture),
        ),
      );
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Generate invoice'));
      await tester.tap(find.text('Generate invoice'));
      await tester.pumpAndSettle();
      expect(find.byType(CanadianInvoiceEditor), findsOneWidget);
      expect(find.text('Set up company details'), findsOneWidget);
      expect(find.text('MXN per USD'), findsNothing);
      await tester.tap(find.text('Set up company details'));
      await tester.pumpAndSettle();
      expect(find.byType(BillingProfileScreen), findsOneWidget);
      expect(
        find.widgetWithText(BillingTextField, 'Legal or trading name'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
