import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/features/assets/asset_type_provider.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/maintenance/maintenance_repository.dart';
import 'package:vortice_app/features/maintenance/planning/planning_repository.dart';
import 'package:vortice_app/features/maintenance/planning/maintenance_planning_screen.dart';
import 'connected_harness.dart';
import 'audit_output.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'review fleet import then create, book, reopen and reschedule from Month',
    (tester) async {
      await tester.runAsync(() async {
        final h = ConnectedHarness(tester, report: 'next007-import-calendar');
        await h.start();
        final marker = 'E2E-007-${const Uuid().v4().substring(0, 8)}';
        final name = '$marker Excavator';
        String? asset, job;
        final manifest = <String, dynamic>{
          'marker': marker,
          'asset_name': name,
        };
        void saveManifest() => File(
          auditOutputPath('NEXT-007-fixture-$marker.json'),
        ).writeAsStringSync(jsonEncode(manifest));
        final originalError = FlutterError.onError;
        FlutterError.onError = (e) {
          h.issues.add(e.exceptionAsString());
          stdout.writeln('FRAMEWORK ${e.exceptionAsString()}');
        };
        try {
          await h.login('demo_fleet_owner@vortice.dev');
          final type = (await h.container.read(
            assetTypesProvider.future,
          )).first;
          await h.step(
            'Assets opens the importer; pasted export maps and previews without saving',
            () async {
              await h.go('/assets');
              await h.tap(find.byTooltip('More actions').last);
              await h.tap(find.text('Import equipment'));
              await h.screenshot('import-start');
              await h.fill(
                find.byKey(const Key('import-paste')),
                'Name,Type,Serial,Make,Component,Component meter,Service name,Interval hours,Last service meter\n$name,${type.name},000${marker.substring(8)},Example,Main engine,125.5,Oil service,250,100',
              );
              await h.tap(find.text('Use pasted table'));
              await h.screenshot('import-column-mapping');
              await h.tap(find.text('Preview import'));
              expect(find.text('Review import'), findsOneWidget);
              expect(
                await supabase.from('assets').select('id').eq('name', name),
                isEmpty,
              );
              await h.screenshot('import-reviewed-baseline');
              await h.tap(find.byKey(const Key('import-confirm')));
              expect(find.text('Equipment imported'), findsOneWidget);
              final rows = await supabase
                  .from('assets')
                  .select('id,serial_number')
                  .eq('name', name);
              expect(rows, hasLength(1));
              asset = rows.single['id'] as String;
              manifest['asset'] = asset;
              saveManifest();
              expect(rows.single['serial_number'], '000${marker.substring(8)}');
              final context = await h.container
                  .read(maintenanceRepositoryProvider)
                  .assetContext(asset!);
              expect(
                (context['components'] as List).single['current_hours'],
                125.5,
              );
              final plans = await h.container
                  .read(planningRepositoryProvider)
                  .load(asset);
              expect(plans.plans.single.data['last_service_hours'], 100);
              await h.tap(find.text(name));
              await h.screenshot('imported-equipment');
            },
          );
          final selected = DateTime(
            DateTime.now().year,
            DateTime.now().month,
            20,
          );
          await h.step(
            'select a day, add work there, and confirm its booking',
            () async {
              if (asset == null) throw StateError('Import did not finish');
              await h.go('/maintenance/planning?assetId=$asset');
              expect(find.byType(PlanningMonth), findsOneWidget);
              await h.tap(
                find.byKey(
                  ValueKey('calendar-day-${selected.toIso8601String()}'),
                ),
              );
              await h.screenshot('calendar-selected-month');
              await h.tap(find.text('Add work here'));
              await h.fill(
                h.field('Work order title'),
                '$marker Hydraulic check',
              );
              await h.fill(
                h.field('Instructions'),
                '$marker Inspect hose connections',
              );
              await h.tap(
                find.widgetWithText(FilledButton, 'Create work order'),
              );
              final jobs = await h.container
                  .read(maintenanceRepositoryProvider)
                  .jobs(assetId: asset);
              job = jobs.single.id;
              manifest['maintenance_job'] = job;
              saveManifest();
              await h.settle();
              expect(find.text('Schedule work'), findsOneWidget);
              await h.screenshot('calendar-prefilled-schedule');
              await h.fill(
                h.field('Scheduling reason'),
                '$marker Monthly work planning',
              );
              await h.tap(find.widgetWithText(FilledButton, 'Save schedule'));
              final booked =
                  (await h.container
                          .read(planningRepositoryProvider)
                          .load(asset))
                      .jobs
                      .single;
              expect(booked.start!.year, selected.year);
              expect(booked.start!.month, selected.month);
              expect(booked.start!.day, selected.day);
              expect(
                booked.dueDate,
                isNull,
                reason: 'Booking is not a deadline',
              );
              await h.reveal(find.text('$marker Hydraulic check'));
              await h.screenshot('calendar-booked-agenda');
              await h.tap(find.text('$marker Hydraulic check'));
              expect(find.text('$marker Hydraulic check'), findsWidgets);
              await h.tap(find.byTooltip('Back'));
              await h.reveal(find.text('$marker Hydraulic check'));
              await h.tap(find.byTooltip('Reschedule'));
              await h.fill(h.field('Estimated duration (minutes)'), '90');
              await h.fill(
                h.field('Scheduling reason'),
                '$marker Allow inspection time',
              );
              await h.tap(find.widgetWithText(FilledButton, 'Save schedule'));
              expect(
                (await h.container.read(planningRepositoryProvider).load(asset))
                    .jobs
                    .single
                    .minutes,
                90,
              );
            },
          );
          await h.step(
            'existing fleet duplicates are stopped in review',
            () async {
              await h.go('/assets/import');
              await h.fill(
                find.byKey(const Key('import-paste')),
                'Name,Type\n$name,${type.name}',
              );
              await h.tap(find.text('Use pasted table'));
              await h.tap(find.text('Preview import'));
              await h.reveal(find.textContaining('Already in this fleet'));
              expect(find.byKey(const Key('import-confirm')), findsNothing);
              await h.screenshot('import-existing-duplicate');
            },
          );
          await h.step(
            'another company cannot read the imported fleet',
            () async {
              final owner = await h.container.read(profileProvider.future);
              await h.login('demo_service_owner@vortice.dev');
              expect(
                await supabase.from('assets').select('id').eq('id', asset!),
                isEmpty,
              );
              await expectLater(
                supabase.rpc(
                  'fleet_import_context',
                  params: {'p_client': owner!.id},
                ),
                throwsA(anything),
              );
            },
          );
        } finally {
          // Record a committed asset even if the response or a later assertion failed.
          if (asset == null) {
            try {
              await h.login('demo_fleet_owner@vortice.dev');
              final found = await supabase
                  .from('assets')
                  .select('id')
                  .eq('name', name);
              if (found.length == 1) {
                manifest['asset'] = found.single['id'];
                saveManifest();
              }
            } catch (_) {}
          }
          FlutterError.onError = originalError;
          await h.close();
        }
        expect(h.issues, isEmpty);
      });
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
