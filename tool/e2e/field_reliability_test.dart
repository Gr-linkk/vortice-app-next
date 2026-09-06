import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:vortice_app/core/account_storage.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/db/database.dart';
import 'package:vortice_app/features/checklists/checklist_submission_orchestrator.dart';
import 'package:vortice_app/features/maintenance/maintenance_repository.dart';
import 'package:vortice_app/models/checklist_item.dart';
import 'package:vortice_app/models/checklist_template.dart';
import 'package:vortice_app/sync/field_work_provider.dart';
import 'package:vortice_app/sync/field_work_queue.dart';
import 'connected_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Next hosted field restart, replay and privacy',
    (tester) async {
      await tester.runAsync(() async {
        final h = ConnectedHarness(tester, report: 'field011');
        await h.start();
        final marker = 'E2E-011-${const Uuid().v4().substring(0, 8)}';
        final asset = const Uuid().v4(), name = '$marker Field vessel';
        final manifest = {'marker': marker, 'asset': asset, 'asset_name': name};
        void save() => File(
          'outputs/NOW-011-fixture-$marker.json',
        ).writeAsStringSync(jsonEncode(manifest));
        save();
        final photo = base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jWZkAAAAASUVORK5CYII=',
        );
        String? job, maintenancePath, operatorPath;
        final temp = await Directory.systemTemp.createTemp('next-field-');
        try {
          await h.login('paradise@vortice.dev');
          final templates = await supabase
              .from('checklist_templates')
              .select()
              .eq('checklist_type', 'operator_daily')
              .eq('is_active', true);
          final template = ChecklistTemplate.fromJson(templates.first);
          final items =
              (await supabase
                      .from('checklist_items')
                      .select()
                      .eq('template_id', template.id))
                  .map(ChecklistItem.fromJson)
                  .toList();
          expect(items, isNotEmpty);
          final manager = h.container.read(maintenanceRepositoryProvider);
          final workspace = await manager.workspace();
          await manager.setup(const Uuid().v4(), 'asset', asset, 0, {
            'name': name,
            'location': '$marker Dock',
            'asset_type_id':
                template.assetTypeId ??
                (workspace['asset_types'] as List).first['id'],
          });
          final context = await manager.assetContext(asset);
          final mechanic = (context['assignees'] as List).firstWhere(
            (p) => p['role'] == 'client_mechanic',
          );
          job = await manager.create(const Uuid().v4(), {
            'asset_id': asset,
            'title': '$marker Repair pump',
            'assigned_to': mechanic['id'],
            'description': '$marker Test field recovery',
            'priority': 'normal',
          });
          manifest['maintenance_job'] = job;
          save();
          await h.login('client_mechanic@vortice.dev');
          final account = supabase.auth.currentUser!.id;
          final sender = h.container.read(fieldWorkQueueProvider)!.send;
          final cache = AccountJsonCache(
            account,
            () => supabase.auth.currentUser?.id,
          );
          var db = AppDatabase.forAccount(
            account,
            executor: NativeDatabase(File('${temp.path}/mechanic.sqlite')),
          );
          var queue = FieldWorkQueue(
            db,
            account: account,
            currentAccount: () => supabase.auth.currentUser?.id,
            send: (_) async =>
                throw const SocketException('Simulated lost connection'),
          );
          await h.step(
            'offline mechanic photo and report survive SQLite restart and lost acknowledgement',
            () async {
              final repo = SupabaseMaintenanceRepository(
                supabase,
                cache: cache,
                queue: queue,
              );
              final initial = (await repo.jobs(jobId: job)).single;
              await repo.change(
                job!,
                initial.revision,
                const Uuid().v4(),
                'start',
                {},
              );
              await repo.change(
                job,
                initial.revision + 1,
                const Uuid().v4(),
                'pause',
                {},
              );
              maintenancePath = '$job/$account/${const Uuid().v4()}.png';
              await repo.uploadEvidence(maintenancePath!, photo, 'image/png');
              await repo.change(
                job,
                initial.revision + 2,
                const Uuid().v4(),
                'save_report',
                {
                  'diagnosis': '$marker Seal worn',
                  'repair': '$marker Seal replaced',
                  'notes': 'Restart and replay proof',
                  'evidence_paths': [maintenancePath],
                },
              );
              expect((await queue.list()).map((o) => o.status), [
                'pending',
                'pending',
                'pending',
                'pending',
              ]);
              expect(
                (await repo.jobs(jobId: job)).single.report['diagnosis'],
                '$marker Seal worn',
              );
              final cached = await cache.readThrough(
                'maintenance_jobs:${jsonEncode({'p_job': job})}',
                () async => throw const SocketException('Offline'),
              );
              expect((cached as List).single['id'], job);
              queue.close();
              await db.close();
              db = AppDatabase.forAccount(
                account,
                executor: NativeDatabase(File('${temp.path}/mechanic.sqlite')),
              );
              var lost = false;
              queue = FieldWorkQueue(
                db,
                account: account,
                currentAccount: () => supabase.auth.currentUser?.id,
                send: (o) async {
                  await sender(o);
                  if (o.payload['p_action'] == 'save_report' && !lost) {
                    lost = true;
                    throw const SocketException(
                      'Server accepted; acknowledgement lost',
                    );
                  }
                },
              );
              await queue.flush();
              expect(
                (await queue.list()).last.status,
                'pending',
                reason: (await queue.list()).last.error,
              );
              await queue.flush();
              expect((await queue.list()).every((o) => o.synced), isTrue);
              final saved = (await SupabaseMaintenanceRepository(
                supabase,
              ).jobs(jobId: job)).single;
              expect(saved.revision, initial.revision + 3);
              expect(saved.labour, hasLength(1));
              expect(saved.report['diagnosis'], '$marker Seal worn');
              expect(
                await supabase.storage
                    .from('maintenance-evidence')
                    .download(maintenancePath!),
                photo,
              );
            },
          );
          queue.close();
          await db.close();
          await h.step(
            'report Back navigation preserves the local draft',
            () async {
              await h.go('/maintenance/jobs/$job');
              await h.tap(find.text('Report & submit'));
              await h.fill(
                h.field('Diagnosis'),
                '$marker Unsaved local diagnosis',
              );
              await h.tap(find.byType(BackButton));
              await h.tap(find.text('Report & submit'));
              expect(
                tester.widget<TextField>(h.field('Diagnosis')).controller!.text,
                '$marker Unsaved local diagnosis',
              );
              await h.screenshot('011-report-restored');
            },
          );
          await h.login('operator@vortice.dev');
          await h.step(
            'operator photos, answers and history commit once after restart',
            () async {
              final actor = supabase.auth.currentUser!.id;
              final liveSender = h.container.read(fieldWorkQueueProvider)!.send;
              final file = File('${temp.path}/operator.sqlite');
              var operatorDb = AppDatabase.forAccount(
                actor,
                executor: NativeDatabase(file),
              );
              var operatorQueue = FieldWorkQueue(
                operatorDb,
                account: actor,
                currentAccount: () => supabase.auth.currentUser?.id,
                send: (_) async => throw const SocketException('Offline'),
              );
              final container = ProviderContainer(
                overrides: [
                  fieldWorkQueueProvider.overrideWithValue(operatorQueue),
                ],
              );
              final run = const Uuid().v4();
              try {
                await container
                    .read(operationsChecklistSubmissionProvider)
                    .submit(
                      assetId: asset,
                      assetClientId: null,
                      operatorId: actor,
                      submittedByRole: 'operator',
                      runType: 'pre_departure',
                      template: template,
                      items: items,
                      responses: {for (final i in items) i.id: 'pass'},
                      notes: {},
                      photos: {for (final i in items) i.id: photo},
                      operationId: run,
                      submittedAt: DateTime.now(),
                      currentHours: 42,
                      generalNotes: '$marker Restart proof',
                    );
                expect((await operatorQueue.list()).length, items.length + 1);
                operatorQueue.close();
                await operatorDb.close();
                operatorDb = AppDatabase.forAccount(
                  actor,
                  executor: NativeDatabase(file),
                );
                operatorQueue = FieldWorkQueue(
                  operatorDb,
                  account: actor,
                  currentAccount: () => supabase.auth.currentUser?.id,
                  send: liveSender,
                );
                await operatorQueue.flush();
                final operations = await operatorQueue.list();
                expect(
                  operations
                      .where((o) => !o.synced)
                      .map((o) => o.error)
                      .toList(),
                  isEmpty,
                );
                await liveSender(
                  operations.first,
                ); // Lost upload acknowledgement.
                await liveSender(
                  operations.last,
                ); // Lost transaction acknowledgement.
                expect(
                  await supabase
                      .from('operator_checklist_runs')
                      .select('id')
                      .eq('id', run),
                  hasLength(1),
                );
                expect(
                  await supabase
                      .from('operator_checklist_responses')
                      .select('id')
                      .eq('run_id', run),
                  hasLength(items.length),
                );
                expect(
                  await supabase
                      .from('saved_checklists')
                      .select('id')
                      .eq('id', run),
                  hasLength(1),
                );
                operatorPath = operations.first.payload['path'] as String;
                expect(
                  await supabase.storage
                      .from('operator-evidence')
                      .download(operatorPath!),
                  photo,
                );
              } finally {
                container.dispose();
                operatorQueue.close();
                await operatorDb.close();
              }
            },
          );
          await h.login('client@vortice.dev');
          await h.step(
            'another company cannot read field photos or use the prior account cache',
            () async {
              expect(
                () => cache.readThrough(
                  'maintenance_jobs:${jsonEncode({'p_job': job})}',
                  () async => throw const SocketException('Offline'),
                ),
                throwsA(isA<AccountChangedException>()),
              );
              if (maintenancePath == null || operatorPath == null) {
                throw StateError('Missing evidence fixture');
              }
              for (final pair in [
                ('maintenance-evidence', maintenancePath!),
                ('operator-evidence', operatorPath!),
              ]) {
                await expectLater(
                  supabase.storage.from(pair.$1).download(pair.$2),
                  throwsA(anything),
                );
              }
            },
          );
          expect(h.issues, isEmpty);
        } finally {
          await h.close();
          await temp.delete(recursive: true);
        }
      });
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
