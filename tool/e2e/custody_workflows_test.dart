// Connected current custody -> generated inspection work -> approved certificate.
// The evidence upload uses a fixed test file; physical picker acceptance is separate.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/features/assurance/assurance_repository.dart';
import 'package:vortice_app/features/maintenance/maintenance_repository.dart';
import 'audit_output.dart';
import 'connected_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'custody and generated inspection work retain reviewed evidence',
    (tester) async {
      await tester.runAsync(() async {
        final h = ConnectedHarness(tester, report: 'custody010');
        await h.start();
        final asset = const Uuid().v4();
        final marker = 'E2E-010-${asset.substring(0, 8)}';
        final manifest = <String, dynamic>{
          'asset': asset,
          'asset_name': '$marker Inspection crane',
          'marker': marker,
        };
        void record() => File(
          auditOutputPath('NOW-010-fixture-$marker.json'),
        ).writeAsStringSync(jsonEncode(manifest));
        record();
        AssuranceRepository assurance() =>
            h.container.read(assuranceRepositoryProvider);
        MaintenanceRepository maintenance() =>
            h.container.read(maintenanceRepositoryProvider);
        Future<void> field(String key, String value) =>
            h.fill(find.byKey(ValueKey(key)), value);
        String? job, evidence;
        final photo = File('tool/e2e/fixtures/evidence.png').readAsBytesSync();
        try {
          await h.login('paradise@vortice.dev');
          final workspace = await maintenance().workspace();
          await maintenance().setup(const Uuid().v4(), 'asset', asset, 0, {
            'name': manifest['asset_name'],
            'location': '$marker Initial dock',
            'asset_type_id': (workspace['asset_types'] as List).first['id'],
          });
          await h.step(
            'custody transfer persists and reopens from equipment',
            () async {
              await h.go('/assurance/assets/$asset');
              await h.tap(find.text('Update location & responsibility'));
              await field('site', '$marker North workshop');
              final people =
                  (await assurance().context(asset))['people'] as List;
              await h.select(
                'Responsible person',
                people.first['name'] as String,
              );
              await field('reason', '$marker Move for annual inspection');
              await h.tap(find.widgetWithText(FilledButton, 'Save changes'));
              expect(
                (await assurance().context(asset))['custody']['site'],
                '$marker North workshop',
              );
              await h.tap(find.text('Update location & responsibility'));
              expect(
                tester
                    .widget<TextFormField>(find.byKey(const ValueKey('site')))
                    .controller!
                    .text,
                '$marker North workshop',
              );
              await h.tap(find.byType(BackButton));
              await h.screenshot('custody010-transfer');
            },
          );
          await h.step(
            'inspection registration opens generated work and accepts assignment',
            () async {
              await h.tap(find.text('Add inspection'));
              await field('title', '$marker Annual lifting certificate');
              await h.tap(find.widgetWithText(FilledButton, 'Add inspection'));
              final inspection = (await assurance().inspections(asset)).single;
              manifest['inspection'] = inspection['id'];
              record();
              await h.tap(find.text('Open inspection work'));
              final jobs = await maintenance().jobs(assetId: asset);
              expect(jobs, hasLength(1));
              job = jobs.single.id;
              manifest['maintenance_job'] = job;
              record();
              await h.waitFor(find.text('Assign work order'));
              await h.tap(find.text('Assign work order'));
              final catalog = await maintenance().assetContext(asset);
              final mechanic = (catalog['assignees'] as List).firstWhere(
                (p) =>
                    p['role'] == 'client_mechanic' &&
                    (h.executorId == null || p['id'] == h.executorId),
              );
              await h.select('Assigned to', mechanic['name'] as String);
              await h.tap(find.widgetWithText(FilledButton, 'Confirm'));
              expect(
                (await maintenance().jobs(jobId: job)).single.status,
                'assigned',
              );
            },
          );
          await h.step(
            'mechanic submits inspection results and private certificate through the work report',
            () async {
              await h.login('client_mechanic@vortice.dev');
              await h.go('/maintenance/jobs/$job');
              await h.tap(find.widgetWithText(FilledButton, 'Start work'));
              await h.tap(find.widgetWithText(TextButton, 'Pause'));
              // Headless evidence fixture, uploaded with the mechanic's real scoped session.
              evidence =
                  '$job/${supabase.auth.currentUser!.id}/${const Uuid().v4()}.png';
              await maintenance().uploadEvidence(evidence!, photo, 'image/png');
              final current = (await maintenance().jobs(jobId: job)).single;
              await maintenance().change(
                job!,
                current.revision,
                const Uuid().v4(),
                'save_report',
                {
                  'evidence_paths': [evidence],
                  'inspection': <String, dynamic>{},
                },
              );
              await h.go('/client/dashboard');
              await h.go('/maintenance/jobs/$job');
              await h.tap(
                find.textContaining(
                  RegExp(r'^(Create|Continue) service report$'),
                ),
              );
              await h.fill(h.field('Findings'), '$marker Annual inspection');
              await h.fill(
                h.field('Work performed and results'),
                '$marker Completed load test',
              );
              await h.fill(h.field('Inspection date'), '2026-09-24');
              await h.fill(h.field('Next expiry date'), '2027-09-24');
              await h.fill(
                h.field('Procedure performed'),
                '$marker Load test procedure',
              );
              await h.fill(
                h.field('Result and certification'),
                '$marker Load test passed',
              );
              await h.select('Certificate photo', 'Photo 1');
              await h.screenshot('custody010-inspection-report');
              await h.tap(
                find.widgetWithText(FilledButton, 'Submit for review'),
              );
              final inspection = (await assurance().inspections(asset)).single;
              expect(inspection['approved'], isNull);
              expect(
                inspection['pending']['result_notes'],
                '$marker Load test passed',
              );
              expect(
                await supabase.storage
                    .from('maintenance-evidence')
                    .download(evidence!),
                photo,
              );
            },
          );
          await h.step(
            'return and correction preserve versions; approval publishes the certificate',
            () async {
              await h.login('paradise@vortice.dev');
              await h.go('/maintenance/jobs/$job');
              await h.tap(find.text('Return for changes'));
              await h.fill(
                h.field('Reason / note'),
                '$marker Include test pressure',
              );
              await h.tap(find.widgetWithText(FilledButton, 'Confirm'));
              expect(
                (await assurance().inspections(asset)).single['approved'],
                isNull,
              );
              await h.login('client_mechanic@vortice.dev');
              await h.go('/maintenance/jobs/$job');
              await h.tap(
                find.textContaining(
                  RegExp(r'^(Create|Continue) service report$'),
                ),
              );
              await h.fill(
                h.field('Result and certification'),
                '$marker Verified 100 psi',
              );
              await h.tap(
                find.widgetWithText(FilledButton, 'Submit for review'),
              );
              await h.login('paradise@vortice.dev');
              await h.go('/maintenance/jobs/$job');
              await h.tap(find.text('Approve & complete'));
              await h.fill(
                h.field('Reason / note'),
                '$marker Evidence verified',
              );
              await h.tap(find.widgetWithText(FilledButton, 'Confirm'));
              final inspection = (await assurance().inspections(asset)).single;
              expect(inspection['approved']['expires_on'], '2027-09-24');
              expect(
                inspection['approved']['result_notes'],
                '$marker Verified 100 psi',
              );
              expect(inspection['versions'], hasLength(2));
              expect(inspection['pending'], isNull);
              await h.go('/assurance/assets/$asset');
              await h.screenshot('custody010-approved');
            },
          );
          await h.step(
            'operator can read; other company cannot read records or private evidence',
            () async {
              await h.login('operator@vortice.dev');
              await h.go('/assurance/assets/$asset');
              expect(
                find.text('Update location & responsibility'),
                findsNothing,
              );
              expect((await assurance().inspections(asset)), hasLength(1));
              await h.login('client@vortice.dev');
              expect(await assurance().inspections(asset), isEmpty);
              await expectLater(
                assurance().context(asset),
                throwsA(isA<PostgrestException>()),
              );
              await expectLater(
                supabase.storage
                    .from('maintenance-evidence')
                    .download(evidence!),
                throwsA(isA<StorageException>()),
              );
            },
          );
          expect(h.issues, isEmpty);
          manifest['passed'] = true;
          record();
        } finally {
          await h.close();
        }
      });
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
