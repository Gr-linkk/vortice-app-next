// Explicit read-only connected capture for the NEXT-004 usability review.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/core/router.dart';
import 'package:vortice_app/features/assets/add_asset_screen.dart';
import 'connected_harness.dart';
import 'audit_output.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('modern role usability evidence', (tester) async {
    await tester.runAsync(() async {
      final h = ConnectedHarness(tester, report: 'usability');
      await h.start();
      final width = double.parse(
        Platform.environment['VORTICE_AUDIT_WIDTH'] ?? '390',
      );
      tester.view.physicalSize = Size(width, width > 800 ? 900 : 844);
      tester.platformDispatcher.textScaleFactorTestValue = double.parse(
        Platform.environment['VORTICE_AUDIT_TEXT_SCALE'] ?? '1',
      );
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await h.settle();
      final pages = <Map<String, dynamic>>[];
      final originalError = FlutterError.onError;
      FlutterError.onError = (e) => h.issues.add(e.exceptionAsString());
      Future<void> capture(String name) async {
        await h.screenshot(name);
        pages.add({
          'screen': name,
          'topRoute': h.container
              .read(routerProvider)
              .routerDelegate
              .currentConfiguration
              .last
              .matchedLocation,
          'route': h.container
              .read(routerProvider)
              .routeInformationProvider
              .value
              .uri
              .toString(),
          'text': find
              .byType(Text)
              .evaluate()
              .map((e) {
                final t = e.widget as Text;
                return t.data ?? t.textSpan?.toPlainText() ?? '';
              })
              .where((s) => s.isNotEmpty)
              .toList(),
        });
        File(
          auditOutputPath('usability-pages.json'),
        ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(pages));
      }

      try {
        await h.go('/login');
        await capture('00-sign-in');
        for (final role in [
          'fleet_owner',
          'fleet_supervisor',
          'fleet_mechanic',
          'fleet_operator',
          'service_owner',
        ]) {
          await h.step('$role ordinary entry screens', () async {
            await h.login('demo_$role@vortice.dev');
            await h.go('/client/dashboard');
            await capture('$role-home');
            if (role == 'service_owner') {
              // The prepared service company has no own equipment. Its owner
              // must be able to start setup directly from the empty Home card.
              await h.reveal(find.text('Add asset'));
              await capture('$role-home-add-asset');
              await h.tap(find.text('Add asset'));
              expect(
                h.container
                    .read(routerProvider)
                    .routerDelegate
                    .currentConfiguration
                    .last
                    .matchedLocation,
                '/assets/new',
              );
              expect(find.byType(AddAssetScreen), findsOneWidget);
              await capture('$role-home-add-asset-form');
              await h.reveal(h.field('Location'));
              await capture('$role-home-add-asset-details');
              await h.go('/client/dashboard');
            }
            // Use the actual navigation controls to establish discoverability.
            for (final label in ['Assets', 'Work orders', 'Faults', 'More']) {
              final target = find.text(label).hitTestable();
              if (target.evaluate().isNotEmpty) {
                await h.tap(target.first);
                await capture(
                  '$role-${label.toLowerCase().replaceAll(' ', '-')}',
                );
              }
            }
            await h.go('/assets/d0210000-0000-4000-8000-000000000010');
            await capture('$role-asset-detail');
            if (role != 'service_owner') {
              await h.go(
                '/fleet/report?assetId=d0210000-0000-4000-8000-000000000010',
              );
              await capture('$role-report-fault');
            }
            if (role == 'fleet_owner') {
              for (final route in [
                '/maintenance/new',
                '/maintenance/new?assetId=d0210000-0000-4000-8000-000000000010',
                '/company',
                '/company/services',
                '/checklist-library',
                '/maintenance/assets/d0210000-0000-4000-8000-000000000010',
              ]) {
                await h.go('/client/dashboard');
                await h.go(route);
                await capture(
                  '$role-${route.replaceAll(RegExp(r'[^a-zA-Z0-9-]'), '-')}',
                );
              }
            }
            if (role == 'fleet_operator') {
              await h.go('/client/dashboard');
              await h.tap(find.text('Demo Truck 01'));
              await capture('operator-start-check');
            }
            if (role == 'service_owner' || role == 'fleet_owner') {
              await h.go('/work-orders/5b529c9b-b916-4248-9fed-ac2041446497');
              await capture('$role-completed-work');
              if (role == 'service_owner') {
                await h.reveal(find.text('Internal labour and parts'));
                await capture('$role-completed-work-footer');
              }
            }
            expect(tester.takeException(), isNull);
          });
        }
        expect(h.issues, isEmpty);
      } finally {
        FlutterError.onError = originalError;
        await h.close();
      }
    });
  }, timeout: const Timeout(Duration(minutes: 12)));
}
