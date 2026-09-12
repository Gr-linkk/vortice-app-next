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
import 'package:vortice_app/features/equipment_reporting/equipment_report.dart';
import 'package:vortice_app/sync/field_work_provider.dart';
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
        final executor =
            Platform.environment['VORTICE_E2E_EXECUTOR'] ??
            'client_mechanic@vortice.dev';
        if (![
          'client_mechanic@vortice.dev',
          'paradise@vortice.dev',
        ].contains(executor)) {
          throw StateError(
            'Use an explicitly configured isolated test executor',
          );
        }
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
        String? plan;
        final now = DateTime.now().toUtc();
        final anchorDate = DateTime.utc(now.year, now.month, 1);
        final nextDate = DateTime.utc(now.year, now.month + 1, 1);
        String dateText(DateTime value) =>
            value.toIso8601String().substring(0, 10);
        final reportPeriod = (
          from: DateTime.now().subtract(const Duration(days: 1)),
          to: DateTime.now().add(const Duration(days: 1)),
        );
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
          await h.tap(find.text('Review parts'));
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
          final executorId =
              (await supabase
                      .from('profiles')
                      .select('id')
                      .eq('email', executor))
                  .single['id'];
          final mechanic =
              (context['assignees'] as List).firstWhere(
                    (p) => p['id'] == executorId,
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
          await h.step(
            'manager configures a fixed hour and calendar plan through the native editor',
            () async {
              final component = const Uuid().v4();
              await maintenance
                  .setup(const Uuid().v4(), 'component', component, 0, {
                    'asset_id': asset,
                    'label': '$marker Main engine',
                    'kind': 'engine',
                    'current_hours': 7020,
                  });
              await h.go('/maintenance/assets/$asset');
              await h.tap(find.text('Add plan'));
              await h.fill(h.field('Plan name'), '$marker Recurring service');
              await h.select('Component', '$marker Main engine');
              await h.select('Schedule by', 'Hours or calendar');
              await h.fill(h.field('Service every (h)'), '250');
              await h.fill(h.field('Last service meter (h)'), '6700');
              await h.fill(h.field('Service every (months)'), '1');
              await h.select(
                'Repeat schedule',
                'Fixed milestones / transition',
              );
              await h.fill(h.field('First meter milestone (h)'), '7000');
              await h.fill(
                h.field('First date milestone'),
                dateText(anchorDate),
              );
              await h.select(
                'Checklist (optional)',
                '$marker Filter procedure',
              );
              await capture('INTEGRATED-fixed-recurrence-editor');
              await saveForm();
              final catalog = await maintenance.assetContext(asset);
              final saved = (catalog['plans'] as List).cast<Map>().singleWhere(
                (p) => p['interval_label'] == '$marker Recurring service',
              );
              plan = saved['id'] as String;
              manifest['plan'] = plan;
              save();
              expect(saved['next_due_hours'], 7000);
              expect(saved['next_due_date'], dateText(anchorDate));
              expect(saved['last_service_hours'], 6700);
            },
          );
          expect(
            plan,
            isNotNull,
            reason: 'A linked recurrence plan is required',
          );
          job = await maintenance.create(const Uuid().v4(), {
            'service_interval_id': plan,
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
            'assigned executor records two filters used and returns one ($executor)',
            () async {
              await h.login(executor);
              await h.go('/maintenance');
              await h.go('/maintenance/jobs/$job');
              await h.tap(find.widgetWithText(FilledButton, 'Start work'));
              await h.tap(
                find.descendant(
                  of: find.byType(AlertDialog),
                  matching: find.widgetWithText(FilledButton, 'Start work'),
                ),
              );
              // The visible local start can precede its automatic upload.
              // Wait for that upload instead of racing the next server action.
              for (var attempt = 0; attempt < 60; attempt++) {
                final queued = await h.container
                    .read(fieldWorkQueueProvider)!
                    .list();
                if (queued.isNotEmpty && queued.every((o) => o.synced)) break;
                await Future<void>.delayed(const Duration(milliseconds: 500));
                await h.settle(3);
              }
              final operations = await h.container
                  .read(fieldWorkQueueProvider)!
                  .list();
              expect(
                operations.every((o) => o.synced),
                isTrue,
                reason: operations
                    .map((o) => '${o.status}: ${o.error}')
                    .join('\n'),
              );
              await h.tap(find.text('Review parts'));
              expect(
                find.text('Add requirement'),
                executor == 'client_mechanic@vortice.dev'
                    ? findsNothing
                    : findsOneWidget,
              );
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
                  'completion_hours': 7020,
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
            'approval advances both recurrence targets and reports actual net parts cost',
            () async {
              final catalog = await h.container
                  .read(maintenanceRepositoryProvider)
                  .assetContext(asset);
              final saved = (catalog['plans'] as List).cast<Map>().singleWhere(
                (p) => p['id'] == plan,
              );
              expect(saved['last_service_hours'], 7020);
              expect(saved['next_due_hours'], 7250);
              expect(saved['next_due_date'], dateText(nextDate));
              final report = await h.container.read(
                equipmentReportLoaderProvider,
              )(reportPeriod);
              final row = report.assets.singleWhere((a) => a['id'] == asset);
              expect(reportNumber(row, 'parts'), 11);
              final records = reportRows(row['records'])
                  .where((r) => r['kind'] == 'internal' && r['id'] == job)
                  .toList();
              expect(records, hasLength(1));
              expect(reportNumber(records.single, 'parts'), 11);
              await h.go('/fleet/reporting');
              expect(find.text('Equipment report'), findsOneWidget);
              await h.tap(find.text(manifest['asset_name'] as String));
              final card = find
                  .ancestor(
                    of: find.text(manifest['asset_name'] as String),
                    matching: find.byType(Card),
                  )
                  .last;
              expect(
                find.descendant(
                  of: card,
                  matching: find.textContaining(' / 11.00 / '),
                ),
                findsOneWidget,
              );
              await capture('INTEGRATED-approved-equipment-report');
              await h.tap(find.text('$marker Friday service'));
              expect(find.text('Parts for this work'), findsWidgets);
            },
          );
          await h.step(
            'other company cannot read or change the fixture stock or job',
            () async {
              await h.login('client@vortice.dev');
              await expectLater(parts(), throwsA(isA<Exception>()));
              final otherReport = await h.container.read(
                equipmentReportLoaderProvider,
              )(reportPeriod);
              expect(otherReport.assets.any((a) => a['id'] == asset), isFalse);
              await h.go('/fleet/reporting');
              expect(find.text(manifest['asset_name'] as String), findsNothing);
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
