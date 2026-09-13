// Dedicated temporary identities, never the existing demo owners.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/membership/membership_provider.dart';
import 'package:vortice_app/features/membership/organization_work_provider.dart';
import 'package:vortice_app/features/maintenance/maintenance_repository.dart';
import 'package:vortice_app/features/maintenance/planning/planning_repository.dart';
import 'package:vortice_app/features/maintenance/work_focus.dart';
import 'package:vortice_app/features/work_orders/work_order_provider.dart';
import 'audit_output.dart';
import 'connected_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'fresh company purpose, own work, customer work and UI acceptance',
    (tester) async {
      await tester.runAsync(() async {
        final h = ConnectedHarness(tester, report: 'next006-company-purpose');
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
        final manifest = <String, dynamic>{
          'accounts': [for (final account in accounts) account['id']],
          'assets': <String>[],
          'jobs': <String>[],
        };
        void save() => File(
          auditOutputPath('next006-fixture.json'),
        ).writeAsStringSync(jsonEncode(manifest));
        save();
        final assets = <String, String>{},
            assetNames = <String, String>{},
            companies = <String, String>{};
        Future<void> login(String purpose) async => h.login(
          accounts.firstWhere((row) => row['purpose'] == purpose)['email']
              as String,
        );
        final errors = FlutterError.onError;
        FlutterError.onError = (details) {
          h.issues.add(details.exceptionAsString());
          stdout.writeln('FRAMEWORK ${details.exceptionAsString()}');
        };
        try {
          for (final purpose in ['fleet', 'service', 'both']) {
            await h.step(
              '$purpose: onboard, reopen and complete own-equipment work',
              () async {
                await login(purpose);
                if ((await h.container.read(
                  profileProvider.future,
                ))!.onboardingRequired) {
                  await h.fill(h.field('Your name'), 'NEXT006 $purpose Owner');
                  await h.fill(
                    h.field('Company name'),
                    'NEXT006 $purpose Company',
                  );
                  await h.tap(find.byKey(ValueKey('company-purpose-$purpose')));
                  await h.screenshot('onboarding-$purpose');
                  await h.tap(
                    find.widgetWithText(FilledButton, 'Create company'),
                  );
                  await h.settle(25);
                }
                final profile = await h.container.read(profileProvider.future);
                expect(profile!.onboardingRequired, isFalse);
                companies[purpose] = profile.orgId!;
                manifest['companies'] = companies;
                save();
                final membership = await h.container.read(
                  organizationContextProvider.future,
                );
                expect(membership.active!.companyPurpose!.name, purpose);
                expect(membership.active!.can('assets_manage'), isTrue);
                expect(membership.active!.providerEnabled, purpose != 'fleet');
                final expectedFocus = purpose == 'fleet'
                    ? WorkFocus.own
                    : purpose == 'service'
                    ? WorkFocus.customer
                    : WorkFocus.all;
                expect(
                  await h.container.read(workFocusProvider.future),
                  expectedFocus,
                );
                final repo = h.container.read(maintenanceRepositoryProvider);
                final workspace = await repo.workspace();
                final asset = const Uuid().v4();
                assets[purpose] = asset;
                assetNames[purpose] =
                    'NEXT006 $purpose Equipment ${asset.substring(0, 6)}';
                (manifest['assets'] as List).add(asset);
                save();
                await repo.setup(const Uuid().v4(), 'asset', asset, 0, {
                  'name': assetNames[purpose],
                  'asset_type_id':
                      (workspace['asset_types'] as List).first['id'],
                });
                await h.go('/maintenance/assets/$asset');
                await h.tap(find.text('New work order'));
                await h.fill(
                  h.field('Work order title'),
                  'NEXT006 $purpose own maintenance',
                );
                await h.fill(
                  h.field('Instructions'),
                  'Inspect and document equipment condition',
                );
                await h.tap(find.text('Optional details'));
                final context = await repo.assetContext(asset);
                final assignee = (context['assignees'] as List).firstWhere(
                  (row) => row['id'] == profile.id,
                );
                await h.select('Assigned to', assignee['name'] as String);
                await h.screenshot('own-work-form-$purpose');
                await h.tap(
                  find.widgetWithText(FilledButton, 'Create work order'),
                );
                final job = (await repo.jobs(assetId: asset)).single;
                (manifest['jobs'] as List).add(job.id);
                save();
                await h.go('/maintenance/jobs/${job.id}');
                await h.tap(find.widgetWithText(FilledButton, 'Start work'));
                await h.tap(find.widgetWithText(TextButton, 'Pause'));
                await h.tap(find.text('Create service report'));
                await h.fill(
                  h.field('Findings'),
                  'Equipment inspected; no defects',
                );
                await h.fill(
                  h.field('Work performed and results'),
                  'Completed the inspection and verified operation',
                );
                await h.tap(
                  find.widgetWithText(FilledButton, 'Submit for review'),
                );
                await h.go('/maintenance/jobs/${job.id}');
                await h.tap(
                  find.widgetWithText(FilledButton, 'Approve & complete'),
                );
                await h.tap(find.widgetWithText(FilledButton, 'Confirm'));
                expect(
                  (await repo.jobs(jobId: job.id)).single.status,
                  'closed',
                );
                await h.screenshot('own-work-complete-$purpose');
              },
            );
            expect(h.issues, isEmpty);
          }
          await h.step(
            'invited mechanic inherits company purpose without owner privileges',
            () async {
              await login('fleet');
              final invite = await h.container
                  .read(membershipRepositoryProvider)
                  .invite(companies['fleet']!, ['mechanic'], [], '');
              await login('mechanic');
              if ((await h.container.read(
                profileProvider.future,
              ))!.onboardingRequired) {
                await h.tap(find.text('Use invitation'));
                expect(
                  find.byKey(const ValueKey('company-purpose-service')),
                  findsNothing,
                );
                await h.fill(h.field('Your name'), 'NEXT006 Mechanic');
                await h.fill(
                  h.field('Invitation code'),
                  invite['code'] as String,
                );
                await h.tap(find.widgetWithText(FilledButton, 'Join company'));
                await h.settle(20);
              }
              final company = (await h.container.read(
                organizationContextProvider.future,
              )).active!;
              expect(company.companyPurpose!.name, 'fleet');
              expect(company.can('billing'), isFalse);
              expect(company.roles, ['mechanic']);
              await h.screenshot('invited-mechanic');
            },
          );
          expect(h.issues, isEmpty);
          for (final purpose in ['service', 'both']) {
            await h.step(
              '$purpose: customer sharing, creation, focus and saved work',
              () async {
                final followupTitle =
                    'NEXT006 $purpose customer followup ${assets['fleet']!.substring(0, 6)}';
                await login('fleet');
                final code =
                    (await h.container
                            .read(organizationWorkRepositoryProvider)
                            .configuration())['settings']['connection_code']
                        as String;
                await login(purpose);
                final configuration = await h.container
                    .read(organizationWorkRepositoryProvider)
                    .configuration();
                final existing = (configuration['relationships'] as List)
                    .where(
                      (row) =>
                          row['client_organization_id'] == companies['fleet'] &&
                          row['status'] == 'active',
                    )
                    .firstOrNull;
                final relation =
                    existing?['id'] as String? ??
                    await supabase.rpc(
                          'propose_organization_customer',
                          params: {'p_connection_code': code},
                        )
                        as String;
                await login('fleet');
                if (existing == null) {
                  await h.container
                      .read(organizationWorkRepositoryProvider)
                      .relationship(
                        companies[purpose]!,
                        companies['fleet']!,
                        'accept',
                      );
                }
                final requested = await h.container
                    .read(organizationWorkRepositoryProvider)
                    .request(
                      const Uuid().v4(),
                      relation,
                      assets['fleet']!,
                      'NEXT006 share with $purpose',
                      'Customer explicitly shares this equipment',
                    );
                (manifest['jobs'] as List).add(requested);
                save();
                h.container.invalidate(maintenancePlanningProvider);
                h.container.invalidate(workOrdersProvider);
                final fleetWork = await h.container.read(
                  maintenancePlanningProvider(null).future,
                );
                expect(
                  fleetWork.jobs
                      .firstWhere((row) => row.id == requested)
                      .ownEquipment,
                  isTrue,
                );
                await login(purpose);
                await h.go('/maintenance/planning?filter=open');
                expect(
                  (await h.container.read(
                    organizationContextProvider.future,
                  )).activeOrganizationId,
                  companies[purpose],
                );
                await h.container.read(workFocusProvider.future);
                final providerWork = await h.container.read(
                  displayedMaintenancePlanningProvider(null).future,
                );
                expect(
                  providerWork.jobs.any((job) => job.id == requested),
                  isTrue,
                  reason:
                      'Newly shared work must finish loading in the provider account',
                );
                await h.tap(find.byKey(const ValueKey('work-focus-customer')));
                expect(
                  h.container.read(workFocusProvider).requireValue,
                  WorkFocus.customer,
                );
                await h.reveal(find.text('NEXT006 share with $purpose'));
                expect(find.text('NEXT006 share with $purpose'), findsWidgets);
                await h.screenshot('customer-work-$purpose');
                await h.tap(find.widgetWithText(FilledButton, 'Create work'));
                final label = 'NEXT006 fleet Company · ${assetNames['fleet']}';
                await h.select('Customer equipment', label);
                await h.fill(h.field('Work order title'), followupTitle);
                await h.fill(
                  h.field('Work details'),
                  'Follow-up work on explicitly shared customer equipment',
                );
                await h.screenshot('customer-create-$purpose');
                await h.tap(
                  find.widgetWithText(FilledButton, 'Create work order'),
                );
                final orders =
                    await supabase.rpc('organization_work_orders') as List;
                final job =
                    orders.firstWhere((row) => row['title'] == followupTitle)
                        as Map;
                final id = job['id'] as String;
                (manifest['jobs'] as List).add(id);
                save();
                expect(job['provider_organization_id'], companies[purpose]);
                expect(job['customer_organization_id'], companies['fleet']);
                await h.go('/work-orders/$id');
                await h.screenshot('customer-detail-$purpose');
                await h.go('/maintenance/planning?filter=open');
                await h.tap(find.byKey(const ValueKey('work-focus-own')));
                expect(find.text(followupTitle), findsNothing);
                await h.go('/more');
                await h.go('/maintenance/planning?filter=open');
                expect(
                  h.container.read(workFocusProvider).requireValue,
                  WorkFocus.own,
                );
                await h.tap(find.byKey(const ValueKey('work-focus-all')));
                await h.reveal(find.text(followupTitle));
                expect(find.text(followupTitle), findsOneWidget);
                await h.tap(find.byTooltip('Search & filters'));
                await h.screenshot('work-filters-$purpose');
              },
            );
            expect(h.issues, isEmpty);
          }
          await h.step(
            'large text work filters and customer dropdown remain readable',
            () async {
              tester.view.physicalSize = const Size(320, 844);
              tester.platformDispatcher.textScaleFactorTestValue = 2;
              await h.go('/maintenance/planning?filter=open');
              final scrollable = find
                  .descendant(
                    of: find.byKey(const ValueKey('work-hub-list')),
                    matching: find.byType(Scrollable),
                  )
                  .first;
              tester.state<ScrollableState>(scrollable).position.jumpTo(0);
              await tester.pump(const Duration(milliseconds: 300));
              await h.tap(find.byKey(const ValueKey('work-focus-customer')));
              await h.screenshot('work-320-large-text');
              await h.tap(find.widgetWithText(FilledButton, 'Create work'));
              await h.select(
                'Customer equipment',
                'NEXT006 fleet Company · ${assetNames['fleet']}',
              );
              await h.screenshot('customer-dropdown-320-large-text');
              expect(tester.takeException(), isNull);
            },
          );
          expect(h.issues, isEmpty);
        } finally {
          FlutterError.onError = errors;
          tester.platformDispatcher.clearTextScaleFactorTestValue();
          await h.close();
        }
      });
    },
    timeout: const Timeout(Duration(minutes: 25)),
  );
}
