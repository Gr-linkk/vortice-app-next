import 'dart:convert';
import 'dart:io';
import 'audit_output.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/features/checklist_builder/checklist_builder_repository.dart';
import 'package:vortice_app/features/maintenance/maintenance_repository.dart';
import 'package:vortice_app/features/fleet/fleet_repository.dart';
import 'package:vortice_app/features/fleet/fleet_models.dart';
import 'package:vortice_app/features/service_reports/service_report_media.dart';
import 'package:vortice_app/sync/field_work_provider.dart';
import 'connected_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'owner and client checklist authoring, versioned execution, evidence and corrective work',
    (tester) async {
      await tester.runAsync(() async {
        final h = ConnectedHarness(tester, report: 'builder015');
        await h.start();
        const uuid = Uuid();
        final marker = 'E2E-015-${uuid.v4().substring(0, 8)}';
        final asset = uuid.v4(),
            component = uuid.v4(),
            plan = uuid.v4(),
            pmProcedure = uuid.v4();
        final name = '$marker Checklist vessel';
        final manifest = <String, dynamic>{
          'marker': marker,
          'asset': asset,
          'asset_name': name,
          'procedures': [pmProcedure],
        };
        void save() => File(
          auditOutputPath('NOW-015-fixture-$marker.json'),
        ).writeAsStringSync(jsonEncode(manifest));
        void remember(String id) {
          (manifest['procedures'] as List).add(id);
          save();
        }

        save();
        final builder = ChecklistBuilderRepository();
        final maintenance = SupabaseMaintenanceRepository(supabase);
        final fleet = SupabaseFleetRepository(supabase);
        final photo = base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/l9sAAAAASUVORK5CYII=',
        );
        Map<String, dynamic>? starter, privateTemplate;
        String? privateProcedure, assignment, fault, repair, pmJob, pmPhoto;
        late Map mechanic;
        final originalError = FlutterError.onError;
        FlutterError.onError = (details) {
          h.issues.add(details.exceptionAsString());
          stdout.writeln('FRAMEWORK ${details.exceptionAsString()}');
        };
        try {
          await h.login('operator@vortice.dev');
          final operatorId = supabase.auth.currentUser!.id;
          await h.login('paradise@vortice.dev');
          final workspace = await maintenance.workspace();
          await maintenance.setup(uuid.v4(), 'asset', asset, 0, {
            'name': name,
            'location': '$marker Dock',
            'asset_type_id': (workspace['asset_types'] as List).first['id'],
          });
          await maintenance.setup(uuid.v4(), 'component', component, 0, {
            'asset_id': asset,
            'label': '$marker Generator',
            'current_hours': 240,
          });
          final context = await maintenance.assetContext(asset);
          mechanic =
              (context['assignees'] as List).firstWhere(
                    (p) => p['role'] == 'client_mechanic',
                  )
                  as Map;
          await h.step(
            'owner creates, previews and publishes a shared critical pre-operation starter through the native builder',
            () async {
              await h.login('owner@vortice.dev');
              await h.go('/checklist-library');
              await h.tap(find.text('Create checklist'));
              await h.fill(
                h.field('Checklist name'),
                '$marker Shared guard check',
              );
              await h.select('Purpose', 'Pre-operation check');
              await h.tap(find.text('Add step'));
              await h.fill(h.field('Instruction'), 'Inspect guard fasteners');
              await h.fill(
                h.field('How to check (optional)'),
                'Verify each guard is secure before starting.',
              );
              await h.tap(find.text('Critical step'));
              await h.tap(find.text('Save step'));
              await h.tap(find.text('Preview checklist'));
              expect(find.text('Inspect guard fasteners'), findsOneWidget);
              await h.screenshot('builder015-owner-preview');
              await tester.pageBack();
              await h.settle();
              await h.tap(find.text('Save draft'));
              final library = await builder.library();
              final procedure = checklistRows(library['procedures'])
                  .singleWhere(
                    (p) =>
                        (p['draft'] as Map)['name'] ==
                        '$marker Shared guard check',
                  );
              remember(procedure['id'] as String);
              await h.tap(find.text('Publish version'));
              starter = checklistRows(
                (await builder.library())['templates'],
              ).singleWhere((t) => t['procedure_id'] == procedure['id']);
              expect(starter!['client_id'], isNull);
              expect(starter!['version'], 1);
              await h.screenshot('builder015-owner-published');
              await tester.pageBack();
              await h.settle();
            },
          );
          await h.step(
            'client copies the starter, scopes a private publication to its equipment, and assigns it to an operator',
            () async {
              if (starter == null) {
                throw StateError('Starter was not published');
              }
              await h.login('paradise@vortice.dev');
              await h.go('/checklist-library');
              await h.tap(find.text('Published library'));
              await h.fill(
                h.field('Search checklists'),
                '$marker Shared guard check',
              );
              await h.tap(find.text('Make a copy'));
              await h.fill(
                h.field('Checklist name'),
                '$marker Private guard check',
              );
              await h.select('Specific equipment (optional)', name);
              await h.tap(find.text('Save draft'));
              final procedure =
                  checklistRows(
                    (await builder.library())['procedures'],
                  ).singleWhere(
                    (p) =>
                        (p['draft'] as Map)['name'] ==
                        '$marker Private guard check',
                  );
              privateProcedure = procedure['id'] as String;
              remember(privateProcedure!);
              expect(
                (procedure['draft'] as Map)['source_template_id'],
                starter!['id'],
              );
              await h.tap(find.text('Publish version'));
              privateTemplate = checklistRows(
                (await builder.library())['templates'],
              ).singleWhere((t) => t['procedure_id'] == privateProcedure);
              expect(
                privateTemplate!['client_id'],
                supabase.auth.currentUser!.id,
              );
              await tester.pageBack();
              await h.settle();
              await h.fill(
                h.field('Search checklists'),
                '$marker Private guard check',
              );
              await h.tap(find.text('Use checklist'));
              final people = checklistRows(
                (await builder.assignments(asset))['people'],
              );
              expect(people, isNotEmpty);
              await h.select(
                'Operator',
                people.singleWhere((p) => p['id'] == operatorId)['name']
                    as String,
              );
              await h.fill(
                h.field('Instructions for the operator'),
                '$marker Report any loose guard before operation.',
              );
              await h.tap(find.text('Assign pre-operation check'));
              final assignments = checklistRows(
                (await builder.assignments(asset))['assignments'],
              );
              assignment = assignments.single['id'] as String;
              manifest['assignment'] = assignment;
              save();
              expect(assignments.single['status'], 'pending');
            },
          );
          await h.step(
            'an operator resumes the assigned version and submits once after a newer publication',
            () async {
              if (privateTemplate == null || assignment == null) {
                throw StateError('No assignment');
              }
              final route =
                  '/operator/checklist?assetId=$asset&templateId=${privateTemplate!['id']}&assignmentId=$assignment';
              await h.login('operator@vortice.dev');
              await h.go(route);
              await h.tap(find.widgetWithText(ChoiceChip, 'Fail'));
              await h.fill(
                h.field('Describe the finding'),
                '$marker Guard fastener is loose',
              );
              await h.settle();
              await h.login('paradise@vortice.dev');
              final procedure = checklistRows(
                (await builder.library())['procedures'],
              ).singleWhere((p) => p['id'] == privateProcedure);
              final updated = Map<String, dynamic>.from(
                procedure['draft'] as Map,
              );
              updated['items'] = [
                {
                  'description_en': 'Inspect all replacement guard fasteners',
                  'definition': {'critical': true},
                },
              ];
              await builder.save(
                uuid.v4(),
                privateProcedure!,
                procedure['revision'] as int,
                'draft',
                updated,
              );
              await builder.save(
                uuid.v4(),
                privateProcedure!,
                (procedure['revision'] as int) + 1,
                'publish',
                {},
              );
              await h.login('operator@vortice.dev');
              await h.go(route);
              expect(find.text('Inspect guard fasteners'), findsOneWidget);
              expect(
                tester
                    .widget<TextField>(h.field('Describe the finding'))
                    .controller!
                    .text,
                '$marker Guard fastener is loose',
              );
              await h.tap(find.text('Complete Checklist'));
              final queue = h.container.read(fieldWorkQueueProvider)!;
              await queue.flush();
              final submission = (await queue.list()).singleWhere(
                (o) => o.kind == 'submit_operations_checklist',
              );
              expect(submission.synced, isTrue, reason: submission.error);
              await queue.send(submission);
              final runs = await supabase
                  .from('operator_checklist_runs')
                  .select()
                  .eq('assignment_id', assignment!);
              expect(runs, hasLength(1));
              expect(runs.single['template_id'], privateTemplate!['id']);
              final assigned = await supabase
                  .from('checklist_assignments')
                  .select()
                  .eq('id', assignment!)
                  .single();
              expect(assigned['status'], 'completed');
              final faults = await fleet.faults(assetId: asset);
              expect(faults, hasLength(1));
              expect(faults.single.urgent, isTrue);
              fault = faults.single.id;
              manifest['run'] = runs.single['id'];
              manifest['fault'] = fault;
              save();
              await h.go('/operator/assets/$asset/checklist-history');
              await h.tap(find.text('$marker Private guard check'));
              expect(find.text('View fault and follow-up'), findsOneWidget);
              await h.screenshot('builder015-operator-history');
            },
          );
          await h.step(
            'a critical checklist finding leads to corrective work and separate manager verification',
            () async {
              if (fault == null) throw StateError('No fault');
              await h.login('paradise@vortice.dev');
              await h.go('/fleet/faults/$fault');
              await h.tap(find.text('Create work order'));
              await h.select('Assigned to', mechanic['name'] as String);
              await h.tap(
                find.widgetWithText(FilledButton, 'Create & open work order'),
              );
              repair = (await fleet.faults(faultId: fault)).single.workOrderId;
              expect(repair, isNotNull);
              await h.login('client_mechanic@vortice.dev');
              await h.go('/maintenance/jobs/$repair');
              await h.tap(find.widgetWithText(FilledButton, 'Start work'));
              await h.tap(find.widgetWithText(TextButton, 'Pause'));
              await h.tap(find.text('Continue service report'));
              await h.fill(
                h.field('Findings'),
                '$marker Loose fastener confirmed',
              );
              await h.fill(
                h.field('Work performed and results'),
                '$marker Replaced fastener and verified torque',
              );
              await h.tap(
                find.widgetWithText(FilledButton, 'Submit for review'),
              );
              await h.login('paradise@vortice.dev');
              await h.go('/maintenance/jobs/$repair');
              await h.tap(find.text('Approve & complete'));
              await h.fill(h.field('Reason / note'), '$marker Repair checked');
              await h.tap(find.widgetWithText(FilledButton, 'Confirm'));
              expect(
                (await fleet.faults(faultId: fault)).single.status,
                FaultStatus.pendingReview,
              );
              await h.go('/fleet/faults/$fault');
              await h.tap(find.text('Verify & resolve'));
              await h.fill(
                h.field('Note / reason'),
                '$marker Guards secure during operational test',
              );
              await h.tap(find.byType(FilledButton).last);
              expect(
                (await fleet.faults(faultId: fault)).single.status,
                FaultStatus.resolved,
              );
              await h.screenshot('builder015-corrective-verification');
            },
          );
          await h.step(
            'rich PM publication freezes in a component plan job while the next version remains independent',
            () async {
              await h.login('paradise@vortice.dev');
              final pmDraft = <String, dynamic>{
                'name': '$marker Pressure service',
                'checklist_type': 'pm',
                'scope_asset_id': asset,
                'items': [
                  {
                    'description_en': 'Record stabilized pressure',
                    'requires_photo': true,
                    'definition': {
                      'input_type': 'number',
                      'unit': 'bar',
                      'min': 10,
                      'max': 50,
                      'allow_na': false,
                    },
                  },
                ],
              };
              await builder.save(uuid.v4(), pmProcedure, 0, 'draft', pmDraft);
              final pmTemplate = await builder.save(
                uuid.v4(),
                pmProcedure,
                1,
                'publish',
                {},
              );
              await maintenance.setup(uuid.v4(), 'plan', plan, 0, {
                'asset_id': asset,
                'engine_id': component,
                'interval_hours': 250,
                'last_service_hours': 0,
                'interval_label': '$marker Pressure service',
                'checklist_template_id': pmTemplate,
                'is_active': true,
              });
              pmJob = await maintenance.create(uuid.v4(), {
                'asset_id': asset,
                'title': '$marker Pressure service',
                'service_interval_id': plan,
                'assigned_to': mechanic['id'],
              });
              final saved = (await maintenance.jobs(jobId: pmJob)).single;
              expect((saved.checklist.single['definition'] as Map)['max'], 50);
              pmDraft['items'] = [
                {
                  'description_en': 'Record pressure under the new limits',
                  'definition': {'input_type': 'number', 'min': 10, 'max': 20},
                },
              ];
              await builder.save(uuid.v4(), pmProcedure, 2, 'draft', pmDraft);
              await builder.save(uuid.v4(), pmProcedure, 3, 'publish', {});
              expect(
                (await maintenance.jobs(
                  jobId: pmJob,
                )).single.checklist.single['description_en'],
                'Record stabilized pressure',
              );
              await h.login('client_mechanic@vortice.dev');
              await h.go('/maintenance/jobs/$pmJob');
              await h.tap(find.widgetWithText(FilledButton, 'Start work'));
              await h.tap(find.widgetWithText(TextButton, 'Pause'));
              final working = (await maintenance.jobs(jobId: pmJob)).single;
              pmPhoto =
                  '$pmJob/${supabase.auth.currentUser!.id}/${uuid.v4()}.png';
              await maintenance.uploadEvidence(pmPhoto!, photo, 'image/png');
              await maintenance.change(
                pmJob!,
                working.revision,
                uuid.v4(),
                'save_report',
                {
                  'diagnosis': '$marker Scheduled service',
                  'repair': '$marker Serviced and tested',
                  'completion_hours': 250,
                  'answers': {
                    working.checklist.single['id']: {
                      'result': 'pass',
                      'note': '30',
                      'photo_path': pmPhoto,
                    },
                  },
                  'evidence_paths': [pmPhoto],
                },
              );
              h.container.invalidate(maintenanceJobProvider(pmJob!));
              await h.go('/maintenance/jobs/$pmJob');
              await h.tap(find.text('Continue service report'));
              await h.fill(h.field('Reading'), '80');
              expect(
                find.text('Outside range · review required'),
                findsOneWidget,
              );
              await h.fill(h.field('Reading'), '30');
              await h.tap(
                find.widgetWithText(FilledButton, 'Submit for review'),
              );
              await h.settle(35);
              expect(
                (await maintenance.jobs(jobId: pmJob)).single.status,
                'pending_review',
              );
              await h.login('paradise@vortice.dev');
              await h.go('/maintenance/jobs/$pmJob');
              await h.tap(find.text('Approve & complete'));
              await h.tap(find.widgetWithText(FilledButton, 'Confirm'));
              final plans =
                  (await maintenance.assetContext(asset))['plans'] as List;
              expect(
                plans.singleWhere((p) => p['id'] == plan)['next_due_hours'],
                500,
              );
              expect(
                await supabase.storage
                    .from('maintenance-evidence')
                    .download(pmPhoto!),
                photo,
              );
              await h.screenshot('builder015-pm-approved');
            },
          );
          await h.step(
            'private PM checklist photos are readable by the company and denied to another company',
            () async {
              await h.login('paradise@vortice.dev');
              final path = 'checklists/asset_$asset/${uuid.v4()}_proof.png';
              await supabase.storage
                  .from('service-report-photos')
                  .uploadBinary(path, photo);
              expect(
                await supabase.storage
                    .from('service-report-photos')
                    .download(path),
                photo,
              );
              final signed = await resolveServiceReportMedia(
                supabase,
                'service-report-photos',
                supabase.storage
                    .from('service-report-photos')
                    .getPublicUrl(path),
              );
              expect(signed, contains('/object/sign/'));
              await h.login('client@vortice.dev');
              final library = await builder.library();
              expect(
                checklistRows(library['templates']).where(
                  (t) =>
                      t['procedure_id'] == privateProcedure ||
                      t['procedure_id'] == pmProcedure,
                ),
                isEmpty,
              );
              expect(
                checklistRows(library['procedures']).where(
                  (t) => (manifest['procedures'] as List).contains(t['id']),
                ),
                isEmpty,
              );
              await expectLater(
                supabase.storage.from('service-report-photos').download(path),
                throwsA(isA<Exception>()),
              );
              await expectLater(
                supabase.storage
                    .from('maintenance-evidence')
                    .download(pmPhoto!),
                throwsA(isA<Exception>()),
              );
              await expectLater(
                builder.save(uuid.v4(), privateProcedure!, 4, 'archive', {}),
                throwsA(isA<Exception>()),
              );
              await h.go('/checklist-library');
              expect(find.text('$marker Private guard check'), findsNothing);
            },
          );
        } finally {
          FlutterError.onError = originalError;
          await h.close();
        }
        expect(h.issues, isEmpty, reason: 'See the connected audit output');
      });
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
