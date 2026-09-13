// Apply the selected workflow to the two established demo companies only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/membership/organization_work_provider.dart';
import 'package:vortice_app/features/maintenance/work_focus.dart';
import 'connected_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'demo owners select their company purpose through settings',
    (tester) async {
      await tester.runAsync(() async {
        final h = ConnectedHarness(tester, report: 'next006-demo-purpose');
        await h.start();
        try {
          for (final entry in const {
            'demo_fleet_owner@vortice.dev': 'fleet',
            'demo_service_owner@vortice.dev': 'service',
          }.entries) {
            await h.step(
              'save and reopen ${entry.value} demo company purpose',
              () async {
                await h.login(entry.key);
                final repo = h.container.read(
                  organizationWorkRepositoryProvider,
                );
                final before = await repo.configuration();
                expect(
                  before['settings']['provider_enabled'],
                  entry.value == 'service',
                );
                await h.go('/company/services');
                await h.tap(
                  find.byKey(ValueKey('company-purpose-${entry.value}')),
                );
                final after = await repo.configuration();
                expect(after['settings']['company_purpose'], entry.value);
                expect(
                  after['settings']['billing_enabled'],
                  before['settings']['billing_enabled'],
                );
                await h.screenshot('demo-purpose-${entry.value}');
                await h.go('/maintenance/planning?filter=open');
                expect(
                  await h.container.read(workFocusProvider.future),
                  entry.value == 'fleet' ? WorkFocus.own : WorkFocus.customer,
                );
                await h.screenshot('demo-work-${entry.value}');
              },
            );
          }
          expect(h.issues, isEmpty);
        } finally {
          await h.close();
        }
      });
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
