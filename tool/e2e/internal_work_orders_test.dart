import 'dart:convert';
import 'dart:io';
import 'audit_output.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:vortice_app/features/maintenance/maintenance_repository.dart';
import 'package:vortice_app/features/maintenance/planning/planning_repository.dart';
import 'package:vortice_app/models/work_order.dart';
import 'connected_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'client company internal work orders from preparation to approval',
    (tester) async {
      await tester.runAsync(() async {
        final h = ConnectedHarness(tester, report: 'internal014');
        await h.start();
        final marker = 'E2E-014-${const Uuid().v4().substring(0, 8)}';
        final asset = const Uuid().v4(), component = const Uuid().v4();
        final name = '$marker Internal work vessel';
        final manifest = <String, dynamic>{
          'marker': marker,
          'asset': asset,
          'asset_name': name,
        };
        void save() => File(
          auditOutputPath('NOW-014-fixture-$marker.json'),
        ).writeAsStringSync(jsonEncode(manifest));
        save();
        String? order;
        final originalError = FlutterError.onError;
        FlutterError.onError = (details) {
          h.issues.add(details.exceptionAsString());
          stdout.writeln('FRAMEWORK ${details.exceptionAsString()}');
        };
        try {
          await h.login('paradise@vortice.dev');
          MaintenanceRepository repository() =>
              h.container.read(maintenanceRepositoryProvider);
          final workspace = await repository().workspace();
          await repository().setup(const Uuid().v4(), 'asset', asset, 0, {
            'name': name,
            'location': '$marker Dock',
            'asset_type_id': (workspace['asset_types'] as List).first['id'],
          });
          await repository().setup(
            const Uuid().v4(),
            'component',
            component,
            0,
            {'asset_id': asset, 'label': 'Generator', 'current_hours': 240},
          );
          final context = await repository().assetContext(asset);
          final mechanic =
              (context['assignees'] as List).firstWhere(
                    (person) => person['role'] == 'client_mechanic',
                  )
                  as Map;
          await h.step(
            'client creates a general internal work order for its own component and mechanic',
            () async {
              await h.go('/maintenance/assets/$asset');
              await h.tap(find.text('New work order'));
              expect(find.text('General work'), findsOneWidget);
              await h.fill(
                h.field('Work order title'),
                '$marker Seasonal preparation',
              );
              await h.fill(
                h.field('Instructions'),
                '$marker Prepare the generator bay and check access',
              );
              await h.tap(find.text('Optional details'));
              await h.select('Component (optional)', 'Generator');
              await h.select('Assigned to', mechanic['name'] as String);
              await h.fill(
                h.field('Expected parts / materials'),
                '$marker Absorbent pads and fasteners',
              );
              await h.tap(
                find.widgetWithText(FilledButton, 'Create work order'),
              );
              final orders = await repository().jobs(assetId: asset);
              expect(orders, hasLength(1));
              final saved = orders.single;
              order = saved.id;
              manifest['work_order'] = order;
              save();
              expect(saved.workType, WorkOrderJobType.general);
              expect(saved.data['assigned_to'], mechanic['id']);
              expect(saved.expectedMaterials, contains('Absorbent pads'));
              expect(saved.data['engine_id'], component);
              await h.screenshot('internal014-created');
            },
          );
          await h.step(
            'manager revises scope before work starts and the planner reflects the type',
            () async {
              await h.tap(find.text('Edit work order'));
              await h.fill(
                h.field('Work order title'),
                '$marker Mounting inspection',
              );
              await h.select('Work type', 'Inspection');
              await h.fill(
                h.field('Expected parts / materials'),
                '$marker Torque wrench',
              );
              await h.fill(
                h.field('Reason for change'),
                '$marker Inspect mounting torque during preparation',
              );
              await h.tap(find.widgetWithText(FilledButton, 'Save work order'));
              final saved = (await repository().jobs(jobId: order)).single;
              expect(saved.workType, WorkOrderJobType.inspection);
              expect(saved.revision, 1);
              expect(saved.expectedMaterials, contains('Torque wrench'));
              await h.go('/maintenance/planning?assetId=$asset');
              await h.tap(find.byKey(const ValueKey('planning-collection')));
              await h.tap(find.text('Unscheduled'));
              await h.reveal(find.text('$marker Mounting inspection'));
              expect(find.text('Inspection'), findsOneWidget);
              await h.screenshot('internal014-planning');
            },
          );
          await h.step(
            'preventive work without a recurring plan and repairs use the same creation form',
            () async {
              for (final kind in [
                WorkOrderJobType.preventative,
                WorkOrderJobType.repair,
              ]) {
                await h.go('/maintenance/new?assetId=$asset');
                await h.fill(
                  h.field('Work order title'),
                  '$marker ${kind.dbValue}',
                );
                await h.select('Work type', kind.label(false));
                await h.tap(
                  find.widgetWithText(FilledButton, 'Create work order'),
                );
                final saved = (await repository().jobs(
                  assetId: asset,
                )).firstWhere((j) => j.title == '$marker ${kind.dbValue}');
                expect(saved.workType, kind);
                expect(saved.isService, isFalse);
              }
            },
          );
          await h.step(
            'assigned mechanic performs the inspection and submits a work report',
            () async {
              await h.login('client_mechanic@vortice.dev');
              await h.go('/maintenance?assetId=$asset');
              expect(find.text('New work order'), findsNothing);
              await h.tap(find.text('$marker Mounting inspection'));
              expect(find.text('Edit work order'), findsNothing);
              await h.tap(find.widgetWithText(FilledButton, 'Start work'));
              await h.tap(find.widgetWithText(TextButton, 'Pause'));
              await h.tap(find.text('Continue service report'));
              await h.fill(
                h.field('Findings'),
                '$marker No defects observed in mounting points',
              );
              await h.fill(
                h.field('Work performed and results'),
                '$marker Verified torque and documented each mounting',
              );
              await h.screenshot('internal014-report');
              await h.tap(
                find.widgetWithText(FilledButton, 'Submit for review'),
              );
              expect(
                (await repository().jobs(jobId: order)).single.status,
                'pending_review',
              );
            },
          );
          await h.step(
            'manager approves the internal order without an invoice or repair requirement',
            () async {
              await h.login('paradise@vortice.dev');
              await h.go('/maintenance/jobs/$order');
              await h.tap(
                find.widgetWithText(FilledButton, 'Approve & complete'),
              );
              expect(
                find.text(
                  'Completes this work order. Asset availability and fault resolution are reviewed separately.',
                ),
                findsOneWidget,
              );
              await h.tap(find.widgetWithText(FilledButton, 'Confirm'));
              final saved = (await repository().jobs(jobId: order)).single;
              expect(saved.status, 'closed');
              expect(saved.workType, WorkOrderJobType.inspection);
              expect(saved.report['repair'], contains('Verified torque'));
              expect(saved.data['service_applied_at'], isNull);
              await h.screenshot('internal014-approved');
            },
          );
          await h.step(
            'another company cannot discover or edit the internal order',
            () async {
              await h.login('client@vortice.dev');
              expect(await repository().jobs(assetId: asset), isEmpty);
              await expectLater(
                repository()
                    .change(order!, 0, const Uuid().v4(), 'edit_details', {
                      'title': 'Cross-company attempt',
                      'job_type': 'general',
                      'priority': 'normal',
                      'note': 'Unauthorized scope edit',
                    }),
                throwsA(isA<Exception>()),
              );
              expect(
                (await h.container.read(planningRepositoryProvider).load(asset))
                    .jobs,
                isEmpty,
              );
              await h.go('/maintenance/jobs/$order');
              expect(
                find.text('This work order is unavailable to your account.'),
                findsOneWidget,
              );
            },
          );
        } finally {
          FlutterError.onError = originalError;
          await h.close();
        }
        expect(h.issues, isEmpty, reason: 'See the connected audit output');
      });
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}
