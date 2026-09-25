import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/membership/organization_services_screen.dart';
import 'package:vortice_app/features/membership/organization_work_provider.dart';

void main() {
  testWidgets('billing appears for providers, not fleet owners at phone size', (
    tester,
  ) async {
    await (FontLoader('Roboto')
          ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf')))
        .load();
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final purpose in ['fleet', 'service']) {
      await tester.pumpWidget(
        ProviderScope(
          key: ValueKey(purpose),
          overrides: [
            organizationServiceConfigurationProvider.overrideWith(
              (ref) async => {
                'organization_id': 'company',
                'can_manage': true,
                'can_admin': false,
                'settings': {
                  'company_purpose': purpose,
                  'provider_enabled': purpose == 'service',
                  'billing_enabled': false,
                  'connection_code': 'EXAMPLE',
                },
                'relationships': <Object>[],
              },
            ),
          ],
          child: const MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(2)),
              child: OrganizationServicesScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Your company code'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.byType(SwitchListTile),
        purpose == 'service' ? findsOneWidget : findsNothing,
      );
      if (purpose == 'service') {
        await tester.ensureVisible(find.text('Enable company billing'));
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
}
