// Read-only connected company/role acceptance using explicitly prepared demos.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/assets/asset_workspace.dart';
import 'package:vortice_app/features/membership/membership_models.dart';
import 'connected_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'modern demo roles switch through UI and retain exact company scope',
    (tester) async {
      await tester.runAsync(() async {
        final h = ConnectedHarness(tester, report: 'next002-modern-membership');
        await h.start();
        try {
          var first = true;
          String? fleetOrg;
          for (final persona in const {
            'demo_fleet_owner@vortice.dev': 'company_owner',
            'demo_fleet_supervisor@vortice.dev': 'supervisor',
            'demo_fleet_mechanic@vortice.dev': 'mechanic',
            'demo_fleet_operator@vortice.dev': 'operator',
            'demo_service_owner@vortice.dev': 'company_owner',
          }.entries) {
            await h.step(
              'switch to ${persona.key} and inspect company scope',
              () async {
                if (first) {
                  await h.tap(find.byKey(const ValueKey('dev-sign-in')));
                  first = false;
                } else {
                  await h.go('/more');
                  await h.tap(find.byKey(const ValueKey('dev-switch-account')));
                }
                final tile = find.byKey(ValueKey('dev-account:${persona.key}'));
                await h.tap(tile);
                for (var attempt = 0; attempt < 150; attempt++) {
                  await tester.pump(const Duration(milliseconds: 100));
                  await Future<void>.delayed(const Duration(milliseconds: 100));
                  if (h.container.read(profileProvider).valueOrNull?.email ==
                      persona.key) {
                    break;
                  }
                }
                final profile = await h.container.read(profileProvider.future);
                expect(profile?.email, persona.key);
                expect(profile!.membershipManaged, isTrue);
                expect(profile.onboardingRequired, isFalse);
                expect(profile.organizationRoles, [persona.value]);
                final provider =
                    persona.key == 'demo_service_owner@vortice.dev';
                if (provider) {
                  expect(profile.orgId, isNot(fleetOrg));
                } else {
                  fleetOrg ??= profile.orgId;
                  expect(profile.orgId, fleetOrg);
                }
                expect(
                  profile.canInOrganization('team_admin'),
                  persona.value == 'company_owner',
                );
                expect(
                  profile.canInOrganization('planning'),
                  ['company_owner', 'supervisor'].contains(persona.value),
                );
                final assets = await supabase
                    .from('assets')
                    .select('id,name,meter_unit')
                    .eq('id', 'd0210000-0000-4000-8000-000000000010');
                expect(
                  assets.length,
                  provider ? 0 : 1,
                  reason:
                      'A relationship does not expose a customer private fleet',
                );
                if (!provider) {
                  expect(assets.single['meter_unit'], 'km');
                  final engines = await supabase
                      .from('asset_engines')
                      .select('current_hours,meter_unit')
                      .eq('asset_id', assets.single['id']);
                  expect(engines.single['current_hours'], 62000);
                  expect(engines.single['meter_unit'], 'km');
                  final workspace = await h.container.read(
                    assetWorkspaceProvider.future,
                  );
                  expect(
                    (workspace['items'] as List).where(
                      (row) => row['id'] == assets.single['id'],
                    ),
                    hasLength(1),
                  );
                  await h.go('/assets');
                  expect(find.text('Demo Truck 01'), findsOneWidget);
                } else {
                  await h.go('/more');
                }
                await h.screenshot(
                  'modern-${provider ? 'provider' : persona.value}',
                );
                expect(tester.takeException(), isNull);
              },
            );
            expect(h.issues, isEmpty);
          }
        } finally {
          await h.close();
        }
      });
    },
  );
}
