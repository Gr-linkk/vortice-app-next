import 'dart:io';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/invoices/billing_profile.dart';
import 'package:vortice_app/features/invoices/canadian_invoice.dart';
import 'package:vortice_app/features/invoices/canadian_invoice_editor.dart';
import 'package:vortice_app/features/invoices/invoice_excel_service.dart';
import 'package:vortice_app/features/invoices/invoice_pdf_service.dart';
import 'package:vortice_app/features/membership/organization_work_provider.dart';
import 'package:vortice_app/models/invoice.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/sync/online_action_gate.dart';
import '../fleet/fleet_test_support.dart'
    show captureFleet, loadFleetScreenshotFonts;

const issuer = {
  'legal_name': 'Atelier Boréal Test Inc.',
  'address': '123 rue Exemple, Montréal, QC, Canada',
  'contact': 'comptabilite@example.invalid',
  'registration_status': 'registered',
  'tax_registration': 'GST/HST: TEST ONLY · QST: TEST ONLY',
};
Map<String, dynamic> details() => {
  'issuer': issuer,
  'customer_name': 'Example Fleet Ltd.',
  'customer_address': '456 Sample Road, Ottawa, ON, Canada',
  'supply_description': 'Replace hydraulic hose and test pressure',
  'supply_province': 'ON',
  'tax_treatment': 'taxable',
  'tax_review_note':
      'Synthetic test: reviewed taxable service, full subtotal. Not a live tax determination.',
  'issue_date': '2026-09-25',
  'due_date': '2026-10-25',
  'payment_terms': 'Due in 30 days',
  'labour_rate': 100.0,
  'labour_total': 200.0,
  'parts_total': 50.01,
  'subtotal': 250.01,
  'tax_total': 32.50,
  'total': 282.51,
  'taxes': [
    {'name': 'HST', 'rate': 13.0, 'base': 250.01, 'amount': 32.50},
  ],
};
Invoice nativeInvoice({InvoiceStatus status = InvoiceStatus.sent}) => Invoice(
  id: 'cad-native',
  workOrderId: 'job',
  clientId: 'customer',
  invoiceNumber: 'INV-CAD-NATIVE',
  status: status,
  billingCurrency: 'CAD',
  billingDetails: details(),
  labourHours: 2,
  totalCad: 282.51,
  exportSnapshot: const {'parts': []},
);

class _BillingProfile extends BillingProfileRepository {
  String? organization;
  Map<String, dynamic>? saved;
  @override
  Future<void> save(String organizationId, Map<String, dynamic> details) async {
    organization = organizationId;
    saved = details;
  }
}

class _BillingWork extends OrganizationWorkRepository {
  Map<String, dynamic>? saved;
  String? action;
  @override
  Future<void> invoice(
    String id,
    String action,
    Map<String, dynamic> data,
  ) async {
    this.action = action;
    saved = data;
  }
}

Future<void> reveal(
  WidgetTester tester,
  Finder target, {
  double delta = 300,
}) async {
  for (var i = 0; i < 100 && target.evaluate().isEmpty; i++) {
    await tester.dragFrom(const Offset(10, 500), Offset(0, -delta));
    await tester.pumpAndSettle();
  }
  expect(target, findsOneWidget);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'CAD preview matches server cent rounding, including French decimals',
    () {
      expect(canadianSubtotal(1.5, '0.67', '0'), 1.01);
      expect(canadianSubtotal(2, '100,00', '50,01'), 250.01);
    },
  );
  test(
    'native CAD round trip and exports use saved issuer/taxes without USD conversion',
    () async {
      final invoice = Invoice.fromJson(nativeInvoice().toJson());
      expect(invoice.isNativeCad, isTrue);
      expect(invoice.totalUsd, isNull);
      expect(invoice.nativeTotal, 282.51);
      final bytes = InvoiceExcelService.generateBytes(invoice, french: true)!;
      final book = Excel.decodeBytes(bytes);
      final text = book.tables['Invoice']!.rows
          .map((r) => r.map((c) => c?.value.toString() ?? '').join(' '))
          .join('\n');
      expect(text, contains('Atelier Boréal Test Inc.'));
      expect(text, contains('282,51 CAD'));
      expect(text, contains('HST (13%)'));
      expect(text, contains('250,01 CAD : 32,50 CAD'));
      expect(text, contains('Total à payer'));
      expect(text, isNot(contains('Vortice Mechanical')));
      expect(text, isNot(contains('MXN')));
      expect(text, isNot(contains('USD')));
      final amountRows = book.tables['CAD amounts']!.rows;
      expect(
        amountRows
            .singleWhere((r) => r.first?.value.toString() == 'total')[1]!
            .value,
        const DoubleCellValue(282.51),
      );
      final directory = Platform.environment['VORTICE_CAPTURE_DIR'];
      for (final language in ['en', 'fr']) {
        final pdf = await InvoicePdfService.generateBytes(
          invoice,
          french: language == 'fr',
        );
        expect(pdf.length, greaterThan(2000));
        if (directory != null) {
          Directory(directory).createSync(recursive: true);
          File('$directory/native-cad-$language.pdf').writeAsBytesSync(pdf);
          File('$directory/native-cad-fr.xlsx').writeAsBytesSync(bytes);
        }
      }
    },
  );
  test('long French invoice fields export completely across pages', () async {
    final longText = List.generate(
      25,
      (i) =>
          'Réparation numéro $i : inspection des conduites et essai de pression.',
    ).join('\n');
    final invoice = nativeInvoice().copyWith(
      billingDetails: {
        ...details(),
        'supply_description': longText,
        'tax_review_note': longText,
        'payment_terms': longText,
      },
    );
    final bytes = await InvoicePdfService.generateBytes(invoice, french: true);
    expect(bytes.length, greaterThan(2000));
    final directory = Platform.environment['VORTICE_CAPTURE_DIR'];
    if (directory != null) {
      File('$directory/native-cad-fr-long.pdf').writeAsBytesSync(bytes);
    }
  });
  testWidgets(
    'French company invoice setup retains edits on back and saves to its original company',
    (tester) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(loadFleetScreenshotFonts);
      final repository = _BillingProfile();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            billingProfileRepositoryProvider.overrideWithValue(repository),
            onlineActionGateProvider.overrideWith(
              (ref) => OnlineActionGate(
                account: 'actor',
                currentAccount: () => 'actor',
                probe: () async {},
              ),
            ),
          ],
          child: RepaintBoundary(
            key: const Key('fleet-capture'),
            child: MaterialApp(
              locale: const Locale('fr'),
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              theme: AppTheme.lightTheme,
              debugShowCheckedModeBanner: false,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const BillingProfileScreen(
                          details: issuer,
                          organizationId: 'original-company',
                        ),
                      ),
                    ),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).first,
        'Atelier Boréal Révisé',
      );
      await tester.pumpAndSettle();
      await captureFleet(tester, 'native-fr-profile-2.0');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Abandonner les modifications'),
        findsOneWidget,
      );
      await tester.tap(find.text('Continuer à modifier'));
      await tester.pumpAndSettle();
      final save = find.widgetWithText(
        FilledButton,
        'Enregistrer les coordonnées',
      );
      await reveal(tester, save);
      await captureFleet(tester, 'native-fr-profile-save-2.0');
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(repository.organization, 'original-company');
      expect(repository.saved?['legal_name'], 'Atelier Boréal Révisé');
      expect(find.text('Open'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  for (final lang in ['en', 'fr']) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'CAD draft edit validation and saved tax lines $lang $scale',
        (tester) async {
          SharedPreferences.setMockInitialValues({});
          tester.view.physicalSize = Size(scale == 2 ? 320 : 390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.runAsync(loadFleetScreenshotFonts);
          final work = _BillingWork();
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                billingProfileProvider.overrideWith(
                  (_) async => {
                    'organization_id': 'company',
                    'details': issuer,
                    'can_manage': true,
                  },
                ),
                organizationWorkRepositoryProvider.overrideWithValue(work),
                onlineActionGateProvider.overrideWith(
                  (ref) => OnlineActionGate(
                    account: 'actor',
                    currentAccount: () => 'actor',
                    probe: () async {},
                  ),
                ),
              ],
              child: RepaintBoundary(
                key: const Key('fleet-capture'),
                child: MaterialApp(
                  locale: Locale(lang),
                  supportedLocales: AppLocalizations.supportedLocales,
                  localizationsDelegates: const [
                    AppLocalizations.delegate,
                    GlobalMaterialLocalizations.delegate,
                    GlobalWidgetsLocalizations.delegate,
                    GlobalCupertinoLocalizations.delegate,
                  ],
                  theme: AppTheme.lightTheme,
                  debugShowCheckedModeBanner: false,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!,
                  ),
                  home: CanadianInvoiceEditor(
                    workOrderId: 'job',
                    customerName: 'Example Fleet Ltd.',
                    description: 'Hydraulic repair',
                    hours: 2,
                    invoice: nativeInvoice(status: InvoiceStatus.draft),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await captureFleet(tester, 'native-$lang-$scale-issuer');
          final labour = find.byKey(const ValueKey('labour_rate'));
          await reveal(tester, labour);
          await tester.enterText(
            find.descendant(of: labour, matching: find.byType(TextFormField)),
            '-1',
          );
          final check = find.byType(CheckboxListTile);
          await reveal(tester, check);
          await tester.tap(check);
          await tester.pumpAndSettle();
          final save = find.widgetWithText(
            FilledButton,
            lang == 'fr' ? 'Enregistrer le brouillon' : 'Save invoice draft',
          );
          await reveal(tester, save);
          await tester.tap(save);
          await tester.pumpAndSettle();
          expect(work.saved, isNull);
          await reveal(tester, labour, delta: -300);
          await tester.enterText(
            find.descendant(of: labour, matching: find.byType(TextFormField)),
            lang == 'fr' ? '100,00' : '100.00',
          );
          await captureFleet(tester, 'native-$lang-$scale-charges');
          await reveal(tester, find.byKey(const ValueKey('tax_review_note')));
          await captureFleet(tester, 'native-$lang-$scale-taxes');
          await reveal(tester, check);
          await tester.tap(check);
          await tester.pumpAndSettle();
          await reveal(tester, save);
          await captureFleet(tester, 'native-$lang-$scale-review');
          await tester.tap(save);
          await tester.pumpAndSettle();
          expect(work.action, 'revise_cad');
          expect(work.saved!['labour_rate'], '100.00');
          expect((work.saved!['taxes'] as List).single['name'], 'HST');
          expect(work.saved, isNot(contains('exchange_rate')));
          expect(work.saved, isNot(contains('issuer')));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
