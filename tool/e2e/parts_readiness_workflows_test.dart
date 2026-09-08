import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/maintenance/maintenance_repository.dart';
import 'package:vortice_app/features/checklist_builder/checklist_builder_repository.dart';
import 'package:vortice_app/features/parts/parts_readiness_repository.dart';
import 'package:vortice_app/features/parts/parts_readiness_models.dart';
import 'audit_output.dart';
import 'connected_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'PM parts readiness through stock, purchasing, use and return',
    (tester) async {
      await tester.runAsync(() async {
        final h = ConnectedHarness(tester, report: 'parts022');
        await h.start();
        final marker = 'E2E-022-${const Uuid().v4().substring(0, 8)}';
        final asset = const Uuid().v4();
        final manifest = <String, dynamic>{
          'marker': marker,
          'asset': asset,
          'asset_name': '$marker Parts vessel',
          'stocks': <Map<String, dynamic>>[],
        };
        void save() => File(
          auditOutputPath('NOW-022-fixture-$marker.json'),
        ).writeAsStringSync(jsonEncode(manifest));
        save();
        String? job;
        final description = '$marker Oil filter';
        final originalError = FlutterError.onError;
        FlutterError.onError = (details) {
          h.issues.add(details.exceptionAsString());
          stdout.writeln('FRAMEWORK ${details.exceptionAsString()}');
        };
        Future<PartsWorkspace> parts() =>
            h.container.read(partsReadinessRepositoryProvider).load(job);
        Future<void> openParts() async {
          await h.go('/maintenance');
          await h.go('/maintenance/jobs/$job');
          await h.tap(find.text('Parts readiness'));
        }

        Future<void> saveForm() =>
            h.tap(find.widgetWithText(FilledButton, 'Save'));
        Future<void> capture(String name) async {
          ScaffoldMessenger.of(
            tester.element(find.byType(Scaffold).last),
          ).clearSnackBars();
          await h.settle();
          await h.screenshot(name);
        }

        try {
          await h.login('paradise@vortice.dev');
          final maintenance = h.container.read(maintenanceRepositoryProvider);
          final workspace = await maintenance.workspace();
          await maintenance.setup(const Uuid().v4(), 'asset', asset, 0, {
            'name': manifest['asset_name'],
            'location': '$marker Dock',
            'asset_type_id': (workspace['asset_types'] as List).first['id'],
          });
          final context = await maintenance.assetContext(asset);
          final mechanic =
              (context['assignees'] as List).firstWhere(
                    (p) => p['role'] == 'client_mechanic',
                  )
                  as Map;
          final builder = h.container.read(checklistBuilderRepositoryProvider);
          final procedure = const Uuid().v4();
          await builder.save(const Uuid().v4(), procedure, 0, 'draft', {
            'name': '$marker Filter procedure',
            'checklist_type': 'pm',
            'items': [
              {'description_en': 'Inspect replacement filter and check leaks'},
            ],
          });
          final template = await builder.save(
            const Uuid().v4(),
            procedure,
            1,
            'publish',
            {},
          );
          await h.step(
            'company manager edits the existing PM kit from the checklist library',
            () async {
              await h.go('/checklist-library');
              await h.fill(find.byType(TextField).first, marker);
              await h.tap(find.text('PM parts kit'));
              await h.tap(find.byType(FloatingActionButton));
              await h.fill(h.field('Part Name'), description);
              await h.fill(h.field('Part Number'), 'E2E-FILTER');
              await h.fill(h.field('Qty'), '2');
              await h.fill(h.field('Unit'), 'ea');
              await h.tap(find.widgetWithText(ElevatedButton, 'Save'));
              expect(find.text(description), findsOneWidget);
              await capture('NOW-022-standard-pm-kit');
            },
          );
          job = await maintenance.create(const Uuid().v4(), {
            'asset_id': asset,
            'title': '$marker Friday service',
            'job_type': 'preventative',
            'assigned_to': mechanic['id'],
            'description': 'Replace filter and check for leaks',
            'checklist_template_id': template,
          });
          manifest['work_order'] = job;
          save();
          await h.step(
            'job snapshots the PM kit and manager counts opening stock through native forms',
            () async {
              await openParts();
              expect((await parts()).requirements.single.required, 2);
              await h.tap(find.text('Stock').first);
              await h.tap(find.text('Add stock item'));
              await h.fill(h.field('Description'), description);
              await h.fill(h.field('Part number'), 'E2E-FILTER');
              await h.fill(h.field('Stock location'), '$marker Workshop');
              await h.fill(h.field('Unit cost (USD)'), '10');
              await saveForm();
              final stock = (await parts()).stock.singleWhere(
                (s) => s.description == description,
              );
              (manifest['stocks'] as List).add({
                'id': stock.id,
                'description': description,
              });
              save();
              final card = find
                  .ancestor(
                    of: find.text(description),
                    matching: find.byType(Card),
                  )
                  .last;
              await h.tap(
                find.descendant(
                  of: card,
                  matching: find.text('Count / adjust'),
                ),
              );
              await h.fill(h.field('Quantity'), '1');
              await h.fill(h.field('Minimum stock'), '1');
              await h.fill(
                h.field('Reason for adjustment'),
                'Opening count for isolated parts test',
              );
              await saveForm();
              expect(
                (await parts()).stock
                    .singleWhere((s) => s.id == stock.id)
                    .onHand,
                1,
              );
            },
          );
          await h.step(
            'reserve one filter and request the missing filter',
            () async {
              await h.tap(find.text('Job parts').first);
              await h.tap(find.widgetWithText(FilledButton, 'Choose stock'));
              await h.tap(
                find.descendant(
                  of: find.byType(SimpleDialog),
                  matching: find.textContaining(description),
                ),
              );
              expect(find.text('Shortage: 1 ea'), findsOneWidget);
              await capture('NOW-022-job-shortage');
              await h.tap(find.widgetWithText(FilledButton, 'Reserve parts'));
              await saveForm();
              expect((await parts()).requirements.single.reserved, 1);
              await h.tap(find.widgetWithText(FilledButton, 'Request parts'));
              await saveForm();
              expect((await parts()).purchases.single['status'], 'requested');
            },
          );
          await h.step(
            'record supplier order and receive delivery through native forms',
            () async {
              await h.tap(find.text('Orders').first);
              await h.tap(find.widgetWithText(FilledButton, 'Record order'));
              await h.fill(h.field('Supplier'), 'Fixture supplier');
              await h.fill(h.field('Order reference'), '$marker PO');
              await h.fill(h.field('Expected date (YYYY-MM-DD)'), '2026-09-11');
              await saveForm();
              expect((await parts()).purchases.single['status'], 'ordered');
              await capture('NOW-022-purchase-order');
              await h.tap(
                find.widgetWithText(FilledButton, 'Receive delivery'),
              );
              await h.fill(h.field('Unit cost (USD)'), '12');
              await saveForm();
              final result = await parts();
              expect(result.purchases.single['status'], 'received');
              expect(result.stockFor(result.requirements.single)!.onHand, 2);
              await h.tap(find.text('Job parts').first);
              await h.tap(find.widgetWithText(FilledButton, 'Reserve parts'));
              await saveForm();
              expect((await parts()).requirements.single.reserved, 2);
            },
          );
          await h.step(
            'Spanish dark parts screen and quantity form remain usable at 200 percent text',
            () async {
              await h.container
                  .read(localeProvider.notifier)
                  .setLocale(const Locale('es'));
              tester.platformDispatcher.platformBrightnessTestValue =
                  Brightness.dark;
              tester.platformDispatcher.textScaleFactorTestValue = 2;
              await h.settle();
              await capture('NOW-022-spanish-dark-large');
              await h.tap(find.byTooltip('Acciones del repuesto'));
              await h.tap(find.text('Editar cantidad necesaria'));
              await capture('NOW-022-spanish-quantity-form');
              await h.tap(find.text('Cancelar'));
              tester.platformDispatcher.clearPlatformBrightnessTestValue();
              tester.platformDispatcher.clearTextScaleFactorTestValue();
              await h.container
                  .read(localeProvider.notifier)
                  .setLocale(const Locale('en'));
              await h.settle();
            },
          );
          await h.step(
            'assigned mechanic records two filters used and returns one',
            () async {
              await h.login('client_mechanic@vortice.dev');
              await h.go('/maintenance');
              await h.go('/maintenance/jobs/$job');
              await h.tap(find.widgetWithText(FilledButton, 'Start work'));
              await h.tap(find.text('Parts readiness'));
              expect(find.text('Add requirement'), findsNothing);
              await h.tap(find.widgetWithText(FilledButton, 'Record use'));
              await saveForm();
              expect((await parts()).requirements.single.used, 2);
              await h.tap(find.byTooltip('Part actions'));
              await h.tap(find.text('Return unused parts'));
              await h.fill(h.field('Quantity'), '1');
              await saveForm();
              final result = await parts();
              expect(result.requirements.single.used, 1);
              expect(result.stockFor(result.requirements.single)!.onHand, 1);
              final saved = await h.container
                  .read(maintenanceRepositoryProvider)
                  .jobs(jobId: job);
              expect(saved.single.partsCost, 11);
              await h.tap(find.text('Activity').first);
              expect(find.text('Parts returned'), findsOneWidget);
              await capture('NOW-022-stock-activity');
            },
          );
          await h.step(
            'work submission retains actual cost and manager can reopen stock history',
            () async {
              final repository = h.container.read(
                maintenanceRepositoryProvider,
              );
              var current = (await repository.jobs(jobId: job)).single;
              await repository.change(
                job!,
                current.revision,
                const Uuid().v4(),
                'pause',
                {},
              );
              current = (await repository.jobs(jobId: job)).single;
              await repository.change(
                job,
                current.revision,
                const Uuid().v4(),
                'submit',
                {
                  'diagnosis': 'Filter inspected; one replacement required',
                  'repair': 'Replaced filter and checked for leaks',
                  'answers': {
                    for (final item in current.checklist)
                      item['id']: {'result': 'pass', 'note': ''},
                  },
                  'evidence_paths': [],
                },
              );
              await h.login('paradise@vortice.dev');
              final manager = h.container.read(maintenanceRepositoryProvider);
              current = (await manager.jobs(jobId: job)).single;
              await manager.change(
                job,
                current.revision,
                const Uuid().v4(),
                'approve',
                {},
              );
              await openParts();
              expect((await parts()).canChange, isFalse);
              expect((await parts()).requirements.single.used, 1);
              await capture('NOW-022-completed-parts');
            },
          );
          await h.step(
            'other company cannot read or change the fixture stock or job',
            () async {
              await h.login('client@vortice.dev');
              await expectLater(parts(), throwsA(isA<Exception>()));
              final own = await h.container
                  .read(partsReadinessRepositoryProvider)
                  .load(null);
              expect(
                own.stock.any((s) => s.description == description),
                isFalse,
              );
              await expectLater(
                supabase.rpc(
                  'parts_change',
                  params: {
                    'p_job': job,
                    'p_operation': const Uuid().v4(),
                    'p_action': 'stock_count',
                    'p_data': {
                      'stock_id': (manifest['stocks'] as List).first['id'],
                      'revision': 0,
                      'quantity': 100,
                      'note': 'Denied cross-company attempt',
                    },
                  },
                ),
                throwsA(isA<Exception>()),
              );
            },
          );
        } finally {
          tester.platformDispatcher.clearPlatformBrightnessTestValue();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
          FlutterError.onError = originalError;
          await h.close();
        }
        expect(h.issues, isEmpty, reason: 'See parts022 connected results');
      });
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
