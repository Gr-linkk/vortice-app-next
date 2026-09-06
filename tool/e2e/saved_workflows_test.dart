import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/features/invoices/invoice_provider.dart';
import 'package:vortice_app/features/assets/asset_provider.dart';
import 'package:vortice_app/features/engines/engine_provider.dart';
import 'package:vortice_app/features/work_orders/work_order_read_providers.dart';
import 'package:vortice_app/features/maintenance/maintenance_repository.dart';
import 'package:vortice_app/l10n/app_localizations_en.dart';
import 'connected_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'saved asset, request, provider work, billing and account isolation',
    (tester) async {
      await tester.runAsync(() async {
        final h = ConnectedHarness(tester);
        await h.start();
        final marker = 'E2E-010-${const Uuid().v4().substring(0, 8)}';
        final assetName = '$marker Audit vessel';
        final manifest = <String, dynamic>{
          'marker': marker,
          'asset_name': assetName,
        };
        void save() => File(
          'outputs/NOW-010-fixture-$marker.json',
        ).writeAsStringSync(jsonEncode(manifest));
        save();
        String? asset, client, request, providerJob, generatedInvoice;
        final originalError = FlutterError.onError;
        FlutterError.onError = (details) {
          h.issues.add(details.exceptionAsString());
          stdout.writeln('FRAMEWORK ${details.exceptionAsString()}');
        };
        try {
          await h.login('paradise@vortice.dev');
          final workspace = await h.container
              .read(maintenanceRepositoryProvider)
              .workspace();
          await h.step(
            'asset create validates required fields and saves',
            () async {
              await h.go('/maintenance/assets');
              await h.tap(find.text('Add asset'));
              await h.tap(find.widgetWithText(FilledButton, 'Save'));
              expect(find.text('Required'), findsWidgets);
              await h.fill(h.field('Asset name'), assetName);
              await h.select(
                'Asset type',
                (workspace['asset_types'] as List).first['name'] as String,
              );
              await h.select(
                'Company owner',
                (workspace['clients'] as List).first['name'] as String,
              );
              await h.fill(h.field('Location'), '$marker Test dock');
              await h.tap(find.widgetWithText(FilledButton, 'Save'));
              final row = await supabase
                  .from('assets')
                  .select()
                  .eq('name', assetName)
                  .single();
              asset = row['id'] as String;
              client = row['client_id'] as String;
              manifest.addAll({'asset': asset, 'client': client});
              save();
              await h.go('/maintenance/assets/$asset');
              expect(find.text(assetName), findsWidgets);
            },
          );
          if (asset == null) {
            final rows = await supabase
                .from('assets')
                .select()
                .eq('name', assetName);
            if (rows.isEmpty) {
              throw StateError(
                'Asset creation did not complete; see recorded UI failure',
              );
            }
            asset = rows.single['id'] as String;
            client = rows.single['client_id'] as String;
            manifest.addAll({'asset': asset, 'client': client});
            save();
          }
          await h.step('component create and persisted meter', () async {
            await h.go('/maintenance/assets/$asset');
            await h.tap(find.text('Add component'));
            await h.fill(h.field('Component name'), '$marker Main engine');
            await h.fill(h.field('Initial meter hours'), '1250.5');
            await h.tap(find.widgetWithText(FilledButton, 'Save'));
            final row = await supabase
                .from('asset_engines')
                .select()
                .eq('asset_id', asset!)
                .single();
            expect(row['current_hours'], 1250.5);
            manifest['engine'] = row['id'];
            save();
          });
          await h.step('client service request validates and saves', () async {
            await h.go('/client/service-requests/new');
            await h.tap(find.text('Send Request'));
            expect(
              find.text('Please choose an asset or select Other'),
              findsWidgets,
            );
            await h.tap(find.byIcon(Icons.arrow_drop_down).first);
            await h.tap(find.text(assetName));
            await h.fill(h.hint('e.g. 1250.5'), '1250.5');
            await h.fill(
              h.hint('Describe the issue or service needed...'),
              '$marker Inspect intermittent vibration',
            );
            await h.fill(
              h.hint('Phone number or WhatsApp'),
              'E2E synthetic contact',
            );
            await h.tap(find.text('Send Request'));
            final row = await supabase
                .from('service_requests')
                .select()
                .eq('asset_id', asset!)
                .single();
            request = row['id'] as String;
            manifest['request'] = request;
            save();
            expect(row['engine_hours'], 1250.5);
            expect(row['status'], 'new');
          });
          await h.login('owner@vortice.dev');
          await h.step(
            'provider accepts request into linked work order',
            () async {
              if (request == null) {
                throw StateError('Request step did not complete');
              }
              await h.go('/owner/service-requests');
              final card = find
                  .ancestor(
                    of: find.text('$marker Inspect intermittent vibration'),
                    matching: find.byType(Card),
                  )
                  .first;
              await h.tap(
                find.descendant(of: card, matching: find.text('Accept + WO')),
              );
              await h.tap(find.text('Assign technicians'));
              final tech = await supabase
                  .from('profiles')
                  .select('id,full_name')
                  .eq('email', 'tech@vortice.dev')
                  .single();
              await h.tap(
                find.widgetWithText(
                  CheckboxListTile,
                  tech['full_name'] as String,
                ),
              );
              await h.tap(find.widgetWithText(ElevatedButton, 'Done'));
              await h.tap(
                find.widgetWithText(ElevatedButton, 'Create Work Order'),
              );
              final row = await supabase
                  .from('service_requests')
                  .select()
                  .eq('id', request!)
                  .single();
              providerJob = row['generated_work_order_id'] as String?;
              expect(providerJob, isNotNull);
              manifest['provider_job'] = providerJob;
              save();
              final work = await supabase
                  .from('work_orders')
                  .select()
                  .eq('id', providerJob!)
                  .single();
              expect(work['asset_id'], asset);
              expect(work['hours_at_start'], 1250.5);
            },
          );
          await h.step(
            'assigned technician starts, logs hours and submits report',
            () async {
              if (providerJob == null) {
                throw StateError('Provider creation did not complete');
              }
              await h.login('tech@vortice.dev');
              await h.go('/employee/work-orders/$providerJob');
              await h.tap(
                find.widgetWithText(ElevatedButton, 'Start Work Order'),
              );
              await h.go('/employee/work-orders/$providerJob');
              await h.tap(find.text('Log Hours'));
              await h.fill(h.field('Labour Hours'), '2');
              await h.tap(find.widgetWithText(ElevatedButton, 'Save'));
              expect(
                (await supabase
                    .from('work_orders')
                    .select('labour_hours')
                    .eq('id', providerJob!)
                    .single())['labour_hours'],
                2,
              );
              await h.go(
                '/employee/service-reports/new?workOrderId=$providerJob',
              );
              final en = AppLocalizationsEn();
              for (final hint in [
                en.srComplaintHint,
                en.srCauseHint,
                en.srCorrectionHint,
                en.srSecondaryDamageHint,
                en.srCommentsHint,
              ]) {
                await h.fill(
                  h.hint(hint),
                  '$marker Tested and recorded: $hint',
                );
              }
              await h.tap(find.widgetWithText(ElevatedButton, 'Submit Report'));
              final report = await supabase
                  .from('service_reports')
                  .select()
                  .eq('work_order_id', providerJob!)
                  .single();
              manifest['provider_report'] = report['id'];
              save();
              await h.go('/employee/work-orders/$providerJob');
              await h.tap(
                find.widgetWithText(ElevatedButton, 'Mark Completed'),
              );
              expect(
                (await supabase
                    .from('work_orders')
                    .select('status')
                    .eq('id', providerJob!)
                    .single())['status'],
                'closed',
              );
            },
          );
          await h.login('owner@vortice.dev');
          await h.step(
            'completed provider job generates invoice with logged labour',
            () async {
              if (providerJob == null) {
                throw StateError('Provider creation did not complete');
              }
              await h.go('/owner/work-orders/$providerJob');
              await h.tap(
                find.widgetWithText(ElevatedButton, 'Generate Invoice'),
              );
              final row = await supabase
                  .from('invoices')
                  .select()
                  .eq('work_order_id', providerJob!)
                  .single();
              generatedInvoice = row['id'] as String;
              manifest['invoice'] = generatedInvoice;
              save();
              h.check(
                row['labour_hours'] == 2,
                'Generated invoice includes the technician logged labour',
              );
            },
          );
          // A controlled invoice fixture allows both valid and invalid edits and
          // exact denial comparisons without touching anyone's existing invoice.
          if (providerJob == null) {
            final row = await supabase
                .from('work_orders')
                .insert({
                  'asset_id': asset,
                  'client_id': client,
                  'created_by': supabase.auth.currentUser!.id,
                  'title': '$marker billing fixture',
                  'job_type': 'repair',
                  'status': 'draft',
                })
                .select('id')
                .single();
            providerJob = row['id'] as String;
            manifest['provider_job'] = providerJob;
            save();
          }
          final invoice = generatedInvoice ?? const Uuid().v4();
          manifest['invoice'] = invoice;
          save();
          if (generatedInvoice == null) {
            await supabase.from('invoices').insert({
              'id': invoice,
              'work_order_id': providerJob,
              'client_id': client,
              'invoice_number': marker,
              'status': 'draft',
              'labour_hours': 2,
              'billable_rate_usd': 80,
              'labour_total_usd': 160,
              'parts_total_usd': 0,
              'consumables_total_usd': 8,
              'subtotal_usd': 168,
              'iva_total_usd': 26.88,
              'total_usd': 194.88,
              'exchange_rate': 17,
              'total_mxn': 3312.96,
            });
          }
          await h.step(
            'invoice edit saves whole-number exchange rate correctly',
            () async {
              await h.go('/owner/invoices/$invoice');
              await h.tap(find.byTooltip('Edit'));
              await h.fill(h.field('Labour Hours'), '3');
              await h.tap(find.text('Save'));
              final row = await supabase
                  .from('invoices')
                  .select()
                  .eq('id', invoice)
                  .single();
              h.check(
                row['labour_hours'] == 3,
                'Invoice valid edit persists when rate is an integer',
              );
              if (find.text('Cancel').evaluate().isNotEmpty) {
                await h.tap(find.text('Cancel'));
              }
            },
          );
          await h.step(
            'invoice negative values are rejected without changing saved amounts',
            () async {
              await h.go('/owner/invoices/$invoice');
              await h.tap(find.byTooltip('Edit'));
              await h.fill(h.field('Labour Hours'), '-2');
              await h.tap(find.text('Save'));
              final row = await supabase
                  .from('invoices')
                  .select()
                  .eq('id', invoice)
                  .single();
              h.check(
                (row['labour_hours'] as num) >= 0,
                'Invoice negative labour rejected',
              );
              if (find.text('Cancel').evaluate().isNotEmpty) {
                await h.tap(find.text('Cancel'));
              }
            },
          );
          await h.step(
            'same-device account switch cannot retain another company invoice',
            () async {
              await h.go('/owner/invoices/$invoice');
              expect(
                await h.container.read(invoiceByIdProvider(invoice).future),
                isNotNull,
              );
              await h.go('/owner/invoices');
              await h.container.read(invoicesProvider.future);
              expect(
                await h.container.read(assetByIdProvider(asset!).future),
                isNotNull,
              );
              expect(
                await h.container.read(enginesForAssetProvider(asset!).future),
                isNotEmpty,
              );
              expect(
                await h.container.read(
                  workOrderByIdProvider(providerJob!).future,
                ),
                isNotNull,
              );
              await h.login('client@vortice.dev');
              final authorized = await supabase
                  .from('invoices')
                  .select('id')
                  .eq('id', invoice);
              expect(authorized, isEmpty);
              await h.go('/client/invoices/$invoice');
              h.check(
                find.text(marker).evaluate().isEmpty,
                'Other company direct invoice screen excludes cached invoice',
              );
              h.check(
                await h.container.read(invoiceByIdProvider(invoice).future) ==
                    null,
                'Other company invoice provider refetches on account change',
              );
              await h.go('/client/invoices');
              h.check(
                !(await h.container.read(
                  invoicesProvider.future,
                )).any((i) => i.id == invoice),
                'Other company invoice list excludes cached invoice',
              );
              await h.screenshot('invoice-account-switch');
              await h.go('/client/assets/$asset');
              h.check(
                find.text(assetName).evaluate().isEmpty,
                'Other company asset detail excludes cached asset',
              );
              h.check(
                await h.container.read(assetByIdProvider(asset!).future) ==
                    null,
                'Asset detail provider refetches on account change',
              );
              h.check(
                (await h.container.read(
                  enginesForAssetProvider(asset!).future,
                )).isEmpty,
                'Engine list refetches on account change',
              );
              h.check(
                await h.container.read(
                      workOrderByIdProvider(providerJob!).future,
                    ) ==
                    null,
                'Provider work detail refetches on account change',
              );
            },
          );
        } finally {
          FlutterError.onError = originalError;
          save();
          await h.close();
        }
        expect(h.issues, isEmpty, reason: 'See outputs/NOW-010-journeys.json');
      });
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}
