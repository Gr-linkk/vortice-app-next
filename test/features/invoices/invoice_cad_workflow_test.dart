import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/invoices/invoice_detail_screen.dart';
import 'package:vortice_app/features/invoices/invoice_detail_summary.dart';
import 'package:vortice_app/features/invoices/invoice_provider.dart';
import 'package:vortice_app/features/invoices/invoice_screen.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/models/invoice.dart';
import 'package:vortice_app/models/profile.dart';
import '../fleet/fleet_test_support.dart'
    show captureFleet, loadFleetScreenshotFonts;

void main() {
  for (final scale in [1.0, 2.0]) {
    for (final historical in [false, true]) {
      testWidgets(
        'invoice list to CAD and back, scale $scale historical $historical',
        (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.runAsync(loadFleetScreenshotFonts);
          final invoice = Invoice(
            id: 'cad-test',
            workOrderId: 'work',
            clientId: 'client',
            invoiceNumber: 'INV-CAD-TEST',
            status: InvoiceStatus.sent,
            labourHours: 2,
            billableRateUsd: 60,
            labourTotalUsd: 120,
            partsTotalUsd: 23,
            consumablesTotalUsd: 6,
            subtotalUsd: 149,
            ivaPct: 16,
            ivaTotalUsd: 23.84,
            totalUsd: 172.84,
            exchangeRate: 17.5,
            totalMxn: 3024.70,
            cadExchangeRate: historical ? null : 1.375,
            totalCad: historical ? null : 237.66,
          );
          final router = GoRouter(
            routes: [
              GoRoute(path: '/', builder: (_, _) => const InvoiceScreen()),
              GoRoute(
                path: '/client/invoices/:id',
                builder: (_, _) =>
                    const InvoiceDetailScreen(invoiceId: 'cad-test'),
              ),
            ],
          );
          addTearDown(router.dispose);
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                profileProvider.overrideWith(
                  (_) async => const Profile(
                    id: 'client',
                    email: 'fixture@example.invalid',
                    fullName: 'Test customer',
                    role: UserRole.client,
                  ),
                ),
                invoicesProvider.overrideWith((_) async => [invoice]),
                invoiceByIdProvider(
                  'cad-test',
                ).overrideWith((_) async => invoice),
              ],
              child: RepaintBoundary(
                key: const Key('fleet-capture'),
                child: MaterialApp.router(
                  routerConfig: router,
                  theme: AppTheme.darkNavyTheme,
                  debugShowCheckedModeBanner: false,
                  localizationsDelegates: const [
                    AppLocalizations.delegate,
                    GlobalMaterialLocalizations.delegate,
                    GlobalWidgetsLocalizations.delegate,
                    GlobalCupertinoLocalizations.delegate,
                  ],
                  supportedLocales: const [Locale('en'), Locale('es')],
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('INV-CAD-TEST'));
          await tester.pumpAndSettle();
          await tester.tap(find.textContaining('🇨🇦'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          if (historical) {
            expect(
              find.text('This invoice has no saved CAD exchange rate.'),
              findsOneWidget,
            );
            expect(find.text(r'$0.00 CAD'), findsNothing);
          } else {
            expect(find.textContaining(r'$165.00 CAD'), findsOneWidget);
            expect(find.text(r'$237.66 CAD'), findsOneWidget);
          }
          await captureFleet(tester, 'cad-$scale-$historical-lines');
          await tester.ensureVisible(find.byType(InvoiceDetailSummaryCard));
          await tester.pumpAndSettle();
          await captureFleet(tester, 'cad-$scale-$historical-total');
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.textContaining('🇲🇽'));
          await tester.tap(find.textContaining('🇲🇽'));
          await tester.pumpAndSettle();
          expect(find.text(r'$3024.70 MXN'), findsOneWidget);
          await tester.tap(find.textContaining('🇺🇸'));
          await tester.pumpAndSettle();
          expect(find.text(r'$172.84 USD'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
