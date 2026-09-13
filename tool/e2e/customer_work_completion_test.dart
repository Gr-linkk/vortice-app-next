import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/features/membership/organization_work_provider.dart';
import 'connected_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'provider-created customer work completes and shares its report',
    (tester) async {
      await tester.runAsync(() async {
        final h = ConnectedHarness(
          tester,
          report: 'next006-customer-completion',
        );
        await h.start();
        final fixture =
            jsonDecode(
                  File('config/next006-fixtures.local.json').readAsStringSync(),
                )
                as Map;
        final accounts = (fixture['accounts'] as List).cast<Map>();
        for (final account in accounts) {
          h.passwords[account['email']] = account['password'];
        }
        try {
          for (final purpose in ['service', 'both']) {
            await h.step(
              '$purpose owner assigns, executes, submits and shares customer report',
              () async {
                final account = accounts.firstWhere(
                  (row) => row['purpose'] == purpose,
                );
                await h.login(account['email'] as String);
                final orders =
                    await supabase.rpc('organization_work_orders') as List;
                final job =
                    orders.firstWhere(
                          (row) =>
                              row['status'] == 'draft' &&
                              (row['title'] as String).startsWith(
                                'NEXT006 $purpose customer followup',
                              ),
                        )
                        as Map;
                final id = job['id'] as String;
                await h.go('/work-orders/$id');
                await h.tap(find.text('Assign teammate'));
                await h.tap(find.text('NEXT006 $purpose Owner'));
                await h.tap(find.text('Start work'));
                await h.tap(find.text('Pause my labour'));
                await h.tap(find.text('Continue service report'));
                await h.fill(
                  h.hint('Describe the problem found'),
                  'Customer equipment required inspection',
                );
                await h.fill(
                  h.hint('Describe the work performed and how it was checked'),
                  'Inspected, adjusted and verified equipment operation',
                );
                await h.screenshot('customer-report-$purpose');
                await h.tap(
                  find.widgetWithText(FilledButton, 'Submit for review'),
                );
                await h.go('/work-orders/$id');
                await h.tap(find.text('Approve and share report'));
                final saved = await h.container
                    .read(organizationWorkRepositoryProvider)
                    .context(id);
                expect(saved['work_order']['status'], 'closed');
                await h.screenshot('customer-complete-$purpose');
                await h.login(
                  accounts.firstWhere(
                        (row) => row['purpose'] == 'fleet',
                      )['email']
                      as String,
                );
                await h.go('/work-orders/$id');
                final visible = await h.container
                    .read(organizationWorkRepositoryProvider)
                    .context(id);
                expect(
                  visible['report']['repair'],
                  contains('verified equipment operation'),
                );
                expect(
                  (visible['work_order'] as Map).containsKey('notes_internal'),
                  isFalse,
                );
                await h.screenshot('customer-received-$purpose');
              },
            );
            expect(h.issues, isEmpty);
          }
        } finally {
          await h.close();
        }
      });
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}
