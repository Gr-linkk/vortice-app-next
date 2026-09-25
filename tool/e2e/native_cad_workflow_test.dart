// Explicit Next-only synthetic invoice journey; cleanup_native_cad.py removes
// only the exact new job and the test issuer profile recorded in its manifest.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/features/invoices/billing_fields.dart';
import 'package:vortice_app/features/invoices/billing_profile.dart';
import 'package:vortice_app/features/invoices/canadian_invoice.dart';
import 'package:vortice_app/features/invoices/invoice_pdf_service.dart';
import 'package:vortice_app/features/invoices/invoice_excel_service.dart';
import 'package:vortice_app/features/membership/organization_work_provider.dart';
import 'package:vortice_app/models/invoice.dart';
import 'audit_output.dart';
import 'connected_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Canadian provider invoice is reviewed, issued and read by its customer',
    (tester) async {
      await tester.runAsync(() async {
        final h = ConnectedHarness(tester, report: 'native-cad');
        await h.start();
        final marker = 'E2E-CAD-${const Uuid().v4()}';
        final manifest = <String, dynamic>{'title': marker};
        void saveManifest() => File(
          auditOutputPath('NEXT-011-native-cad.json'),
        ).writeAsStringSync(jsonEncode(manifest));
        saveManifest();
        Finder field(String key) => find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(TextFormField),
        );
        Finder profileField(String label) => find.descendant(
          of: find.widgetWithText(BillingTextField, label),
          matching: find.byType(TextFormField),
        );
        try {
          await h.login('demo_service_owner@vortice.dev');
          final repo = h.container.read(organizationWorkRepositoryProvider);
          final profile = await BillingProfileRepository().load();
          // Never overwrite an existing company profile to run this fixture.
          expect(
            profile['details'],
            isNull,
            reason:
                'Use a separate test company if invoice setup already exists',
          );
          manifest['organization'] = profile['organization_id'];
          saveManifest();
          final creation = await repo.customerCreationContext();
          final equipment = (creation['equipment'] as List).cast<Map>().first;
          final id = await repo.createCustomerWork(
            const Uuid().v4(),
            equipment['relationship_id'] as String,
            equipment['asset_id'] as String,
            marker,
            'Synthetic Canadian invoice acceptance. No customer charge.',
          );
          manifest['work_order_id'] = id;
          saveManifest();
          await h.step(
            'ordinary approved-work path to Canadian invoice setup',
            () async {
              await h.go('/work-orders/$id');
              final context = await repo.context(id);
              final person = (context['people'] as List)
                  .cast<Map>()
                  .singleWhere((p) => p['id'] == supabase.auth.currentUser!.id);
              await h.tap(find.text('Assign teammate'));
              await h.tap(find.text(person['name'] as String));
              await h.tap(find.text('Start work'));
              if (context['work_order']['engine_id'] != null) {
                await h.tap(find.widgetWithText(FilledButton, 'Start work'));
              }
              await h.tap(find.text('Pause my labour'));
              await h.tap(find.text('Continue service report'));
              await h.fill(
                h.hint('Describe the problem found'),
                'Synthetic hydraulic fitting inspection',
              );
              await h.fill(
                h.hint('Describe the work performed and how it was checked'),
                'Fitting inspected and pressure checked. Test record only.',
              );
              if (context['work_order']['engine_id'] != null) {
                await h.fill(
                  h.field('Completion reading (km)'),
                  context['current_meter'].toString(),
                );
              }
              await h.tap(
                find.widgetWithText(FilledButton, 'Submit for review'),
              );
              await h.go('/work-orders/$id');
              await h.tap(find.text('Approve and share report'));
              await h.tap(find.text('Generate invoice'));
              await h.tap(find.text('Set up company details'));
              await h.fill(profileField('Legal or trading name'), marker);
              await h.fill(
                profileField('Business address'),
                '123 Example Street, Ottawa ON, Canada — TEST ONLY',
              );
              await h.fill(
                profileField('Billing email or phone'),
                'test@example.invalid',
              );
              await h.tap(find.byType(BillingDropdown));
              await h.tap(find.text('Registered').last);
              await h.fill(
                profileField('Tax registration numbers'),
                'GST/HST: TEST ONLY — NOT A REGISTRATION',
              );
              await h.tap(find.text('Save company details'));
              await h.fill(
                field('customer_address'),
                '456 Sample Street, Ottawa ON, Canada — TEST ONLY',
              );
              await h.fill(field('labour_rate'), '100.00');
              await h.fill(field('parts_total'), '50.01');
              await h.tap(find.byKey(const ValueKey('supply_province')));
              await h.tap(find.text('ON').last);
              await h.tap(find.byKey(const ValueKey('tax_treatment')));
              await h.tap(find.text('Taxable').last);
              await h.fill(
                profileField('Tax name (GST, HST, PST, QST…)'),
                'SYNTHETIC TAX',
              );
              await h.fill(profileField('Reviewed rate (%)'), '5');
              await h.fill(profileField('Taxable base (CAD)'), '50.01');
              await h.fill(
                field('tax_review_note'),
                'Synthetic test only: explicit 5% rate on parts. Not a tax determination or customer invoice.',
              );
              await h.fill(
                field('due_date'),
                DateTime.now()
                    .add(const Duration(days: 30))
                    .toIso8601String()
                    .split('T')
                    .first,
              );
              await h.fill(
                field('payment_terms'),
                'Test document only. No payment due.',
              );
              await h.tap(find.byType(CheckboxListTile));
              await h.screenshot('cad-reviewed-draft');
              await h.tap(find.text('Save invoice draft'));
              final saved = await repo.context(id);
              expect(saved['invoice']['billing_currency'], 'CAD');
              expect(saved['invoice']['total_usd'], isNull);
              manifest['invoice_id'] = saved['invoice']['id'];
              saveManifest();
            },
          );
          expect(h.issues, isEmpty);
          await h.step(
            'customer cannot read draft, then receives frozen issued CAD invoice',
            () async {
              await h.login('demo_fleet_owner@vortice.dev');
              final customer = h.container.read(
                organizationWorkRepositoryProvider,
              );
              expect((await customer.context(id))['invoice'], isNull);
              expect(
                await supabase
                    .from('invoices')
                    .select('id')
                    .eq('id', manifest['invoice_id']),
                isEmpty,
              );
              await h.login('demo_service_owner@vortice.dev');
              await h.go('/work-orders/$id');
              await h.tap(find.text('Edit draft'));
              await h.fill(field('parts_total'), '75.00');
              await h.tap(find.byType(CheckboxListTile));
              await h.tap(find.text('Save invoice draft'));
              await h.tap(find.text('Issue invoice to customer'));
              await h.tap(find.widgetWithText(FilledButton, 'Issue invoice'));
              await h.login('demo_fleet_owner@vortice.dev');
              await h.go('/work-orders/$id');
              await h.tap(find.text('View / export invoice'));
              await h.screenshot('customer-issued-cad-invoice');
              final invoice = Invoice.fromJson(
                await supabase
                    .from('invoices')
                    .select()
                    .eq('id', manifest['invoice_id'])
                    .single(),
              );
              expect(invoice.status, InvoiceStatus.sent);
              expect(invoice.cadDetails['parts_total'], 75);
              expect(invoice.cadDetails['tax_total'], 2.5);
              expect(invoice.cadDetails['issuer']['legal_name'], marker);
              File(auditOutputPath('customer-invoice-fr.pdf')).writeAsBytesSync(
                await InvoicePdfService.generateBytes(invoice, french: true),
              );
              File(
                auditOutputPath('customer-invoice-fr.xlsx'),
              ).writeAsBytesSync(
                InvoiceExcelService.generateBytes(invoice, french: true)!,
              );
              await h.login('demo_fleet_mechanic@vortice.dev');
              expect(
                await supabase
                    .from('invoices')
                    .select('id')
                    .eq('id', invoice.id),
                isEmpty,
              );
            },
          );
          expect(h.issues, isEmpty);
        } finally {
          await h.close();
        }
      });
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}
