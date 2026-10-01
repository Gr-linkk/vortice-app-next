import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/agent_service/agent_service.dart';
import 'package:maintenance_local/agent_service/grants.dart';
import 'package:maintenance_local/agent_service/read_snapshot.dart';
import 'package:maintenance_local/corrective_planning.dart';
import 'package:maintenance_local/corrective_planning_store.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/manual_fault_intake.dart';
import 'package:maintenance_local/manual_fault_intake_store.dart';
import 'package:maintenance_local/model.dart';

import 'inspection_editor_coherence_support.dart';

const _workspace = 'synthetic-planning-read-workspace';
const _device = 'synthetic-planning-read-device';
const _token = 'synthetic-planning-read-token';
const _create = '11111111-1111-4111-8111-111111111111';
const _edit = '22222222-2222-4222-8222-222222222222';
const _link = '33333333-3333-4333-8333-333333333333';
const _firstFault = '77777777-7777-4777-8777-777777777777';
const _secondFault = '88888888-8888-4888-8888-888888888888';

const _readCommands = {
  'workspace.status',
  'equipment.list',
  'equipment.show',
  'work.list',
  'work.show',
  'procedures.list',
  'procedures.show',
  'history.list',
};

/// Ordinary read authority exists only for this temporary synthetic fixture.
class _SyntheticReadGrant implements GrantProvider {
  _SyntheticReadGrant(this.grant);
  final AgentGrant grant;

  @override
  Future<AgentGrant?> resolve(String token) async =>
      token == _token ? grant : null;
}

Future<ManualFaultRecord> _reportFault(
  LabStore store,
  String equipmentId,
  String commandId,
) async {
  final intake = ManualFaultIntakeStore(store);
  final command = await intake.freeze(
    equipmentId: equipmentId,
    description: 'Synthetic observation for corrective planning $commandId',
    severity: ManualFaultSeverity.normal,
    commandId: commandId,
  );
  return (await intake.record(command)).record;
}

Json _result(Map<String, Json> replies, String command) =>
    replies[command]!['result'] as Json;

List<Json> _items(Map<String, Json> replies, String command) =>
    (_result(replies, command)['items'] as List).cast<Json>();

Future<Json> _inspectionSnapshot(LabStore store) async {
  final captured = await readAgentSnapshot(store);
  return {
    'source_fingerprint': captured.sourceFingerprint,
    'progress_token': captured.progress.token,
    'catalog': captured.catalog,
    'evidence_identities': captured.evidenceIdentities,
    'jobs': {
      for (final entry in captured.progress.jobs.entries)
        entry.key: {
          'document_hash': entry.value.documentHash,
          'history': [
            for (final version in entry.value.history)
              {'submission': version.submission, 'receipt': version.receipt},
          ],
        },
    },
    'undecided_ids': captured.progress.undecided.map((v) => v.id).toList(),
    'reviewed_ids': captured.progress.reviewed.map((v) => v.id).toList(),
  };
}

void main() {
  setUpAll(initializeEditorNative);

  test(
    'ordinary scoped inspection reads retain truthful payloads and revisions '
    'across corrective create, edit and link',
    () async {
      final fixture = await EditorFixture.create();
      addTearDown(fixture.close);
      final store = fixture.store;
      final equipment = store.equipment.single;
      final equipmentId = equipment['id'] as String;
      final procedure = store.templates.single;
      final procedureId = procedure['id'] as String;
      final submission = await store.submit(jobId: fixture.job);
      final decision = await store.decide(
        submission['id'] as String,
        approve: true,
      );
      final firstFault = await _reportFault(store, equipmentId, _firstFault);
      final secondFault = await _reportFault(store, equipmentId, _secondFault);
      final clock = DateTime.utc(2026, 10, 1, 12);
      final scope = <String, dynamic>{
        'workspace_id': _workspace,
        'company_id': store.catalog!['companyId'],
        'device_id': _device,
      };
      final service = AgentService(
        store: store,
        workspaceId: _workspace,
        serviceDeviceId: _device,
        now: () => clock,
        grants: _SyntheticReadGrant(
          AgentGrant(
            id: 'synthetic-planning-read-grant',
            actorId: 'synthetic-planning-reader',
            workspaceId: _workspace,
            companyId: store.catalog!['companyId'] as String,
            deviceId: _device,
            expiresAt: clock.add(const Duration(hours: 1)),
            commands: _readCommands,
            jobIds: {fixture.job},
            equipmentIds: {equipmentId},
          ),
        ),
      );
      final args = <String, Json>{
        'equipment.show': {'equipment_id': equipmentId},
        'work.show': {'job_id': fixture.job},
        'procedures.show': {'procedure_id': procedureId},
        'history.list': {'job_id': fixture.job},
      };
      Future<Map<String, Json>> readAll() async {
        final replies = <String, Json>{};
        for (final command in _readCommands) {
          final reply = await service.handle({
            'protocol_version': 1,
            'request_id': 'synthetic-${command.replaceAll('.', '-')}',
            'scope': scope,
            'credential': {'token': _token},
            'command': command,
            'args': args[command] ?? <String, dynamic>{},
          });
          expect(reply['ok'], isTrue, reason: '$command: ${canonical(reply)}');
          expect(reply['scope'], scope);
          final meta = reply['meta'] as Json;
          expect(meta['source'], 'local');
          expect(meta['freshness'], 'local_snapshot');
          expect(meta['complete'], isTrue);
          expect(meta['synced'], {
            'verified': false,
            'reason': 'no_fresh_transfer_proof',
          });
          final result = reply['result'] as Json;
          if (command.endsWith('.list')) {
            expect(result['count'], 1, reason: command);
            expect(result['next_cursor'], isNull);
            expect(meta['local_revision'], contentHash(result['items']));
          } else if (command.endsWith('.show')) {
            expect(meta['local_revision'], contentHash(result['item']));
          }
          replies[command] = reply;
        }
        return replies;
      }

      final before = await readAll();
      final beforeSnapshot = await _inspectionSnapshot(store);
      expect(_items(before, 'equipment.list').single, equipment);
      expect(_result(before, 'equipment.show')['item'], equipment);
      expect(_items(before, 'procedures.list').single, procedure);
      expect(_result(before, 'procedures.show')['item'], procedure);
      final work = _items(before, 'work.list').single;
      expect(_result(before, 'work.show')['item'], work);
      expect(work['job_id'], fixture.job);
      expect(work['context']['equipmentId'], equipmentId);
      expect(work['context']['checklistSnapshot']['id'], procedureId);
      expect(
        work['draft']['document_hash'],
        digest(store.documentFor(fixture.job)!),
      );
      expect(work['draft']['phase'], 'ready');
      expect(work['draft']['required_answered'], 3);
      expect(work['draft']['required_total'], 3);
      expect(work['draft']['photo_state'], 'complete');
      final history = _items(before, 'history.list').single;
      expect(history['submission_id'], submission['id']);
      expect(history['job_id'], fixture.job);
      expect(history['document_hash'], submission['documentHash']);
      final inspectionValues = <String, dynamic>{
        'answer:guard': {'result': 'pass', 'value': ''},
        'answer:pressure': {'result': 'pass', 'value': '19'},
        'answer:condition': {'result': 'pass', 'value': 'Condition 1'},
        'meter': 101,
        'notes': 'Guard inspected.',
        'photo': digest(EditorFixture.png),
        'unit': 'hours',
      };
      expect(history['values'], inspectionValues);
      expect(history['photo_state'], 'complete');
      expect(history['known_decision'], {
        ...decision,
        'values': inspectionValues,
      });
      expect(history['known_decision']['decision'], 'approved');
      final status = _result(before, 'workspace.status');
      expect(status['local_work_count'], 1);
      expect(status['local_equipment_count'], 1);
      expect(status['known_version_count'], 1);
      expect(status['known_decisions_are_historical'], isTrue);
      expect(status['pending_proposal_count'], 0);
      expect(
        before['workspace.status']!['meta']['local_revision'],
        contentHash([
          status,
          _items(before, 'work.list'),
          _items(before, 'equipment.list'),
          _items(before, 'history.list'),
          <Json>[],
        ]),
      );
      expect(
        beforeSnapshot['source_fingerprint'],
        agentSourceFingerprint(store),
      );
      expect(beforeSnapshot['reviewed_ids'], [submission['id']]);
      expect(beforeSnapshot['undecided_ids'], isEmpty);
      expect((beforeSnapshot['jobs'] as Map).keys, [fixture.job]);
      expect(beforeSnapshot['evidence_identities'], {
        submission['values']['photo']: submission['values']['photo'],
      });

      Future<void> expectUnchanged(String stage) async {
        expect(canonical(await readAll()), canonical(before), reason: stage);
        expect(
          canonical(await _inspectionSnapshot(store)),
          canonical(beforeSnapshot),
          reason: '$stage read snapshot',
        );
      }

      final planning = CorrectivePlanningStore(store);
      final create = await planning.freezeCreate(
        equipmentId: equipmentId,
        title: 'Inspect the source of the synthetic leak',
        description: 'Diagnose the cause before planning a repair.',
        faultIds: [firstFault.id],
        commandId: _create,
      );
      await expectUnchanged('pending corrective create');
      final created = await planning.apply(create);
      await expectUnchanged('accepted corrective create');
      final edit = await planning.freezeEdit(
        draftId: created.draft.id,
        expectedRevision: created.draft.revision,
        expectedDraftHash: created.draft.hash,
        title: 'Inspect the synthetic leak and related observation',
        description: 'Compare both observations before planning a repair.',
        commandId: _edit,
      );
      await expectUnchanged('pending corrective edit');
      final edited = await planning.apply(edit);
      await expectUnchanged('accepted corrective edit');
      final link = await planning.freezeLink(
        draftId: edited.draft.id,
        expectedRevision: edited.draft.revision,
        expectedDraftHash: edited.draft.hash,
        faultIds: [secondFault.id],
        commandId: _link,
      );
      await expectUnchanged('pending corrective link');
      final linked = await planning.apply(link);
      await expectUnchanged('accepted corrective link');

      final drafts = await planning.listDrafts();
      expect(drafts.single.id, linked.draft.id);
      expect(drafts.single.kind, 'corrective');
      expect(drafts.single.state, 'draft');
      expect(drafts.single.revision, 3);
      expect(drafts.single.faults.map((ref) => ref.faultId).toSet(), {
        firstFault.id,
        secondFault.id,
      });
      expect(await planning.pendingCommands(), isEmpty);
      expect(
        store.db.select('SELECT id FROM events WHERE kind=?', [
          correctivePlanningRecordedEvent,
        ]),
        hasLength(3),
      );
      expect(store.db.select('PRAGMA user_version').single.values.single, 3);
    },
  );
}
