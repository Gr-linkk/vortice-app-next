import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/agent_service/agent_service.dart';
import 'package:maintenance_local/agent_service/grants.dart';
import 'package:maintenance_local/agent_service/proposal_store.dart';
import 'package:maintenance_local/evidence_store.dart';
import 'package:maintenance_local/agent_service/unix_transport.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/local_sync.dart';
import 'package:maintenance_local/model.dart';
import 'package:maintenance_local/office_backup.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';

class _Grants implements GrantProvider {
  AgentGrant? grant;
  final tokens = <String>{'synthetic-token'};
  int calls = 0;
  Future<void> Function(int)? onResolve;
  @override
  Future<AgentGrant?> resolve(String token) async {
    calls++;
    await onResolve?.call(calls);
    return tokens.contains(token) ? grant : null;
  }
}

void main() {
  setUpAll(
    () => RustLib.init(
      externalLibrary: ExternalLibrary.open(
        Platform.environment['MAINTENANCE_NATIVE_LIBRARY']!,
      ),
    ),
  );
  late Directory root;
  late LabStore store;
  late _Grants grants;
  late AgentService service;
  late String first, second, equipment1, equipment2, procedure;
  final clock = DateTime.utc(2026, 10, 1, 12);
  AgentGrant authority({
    Set<String>? jobs,
    Set<String>? equipment,
    Set<String>? commands,
    bool revoked = false,
    bool expired = false,
    String actor = 'external-agent',
  }) => AgentGrant(
    id: 'grant',
    actorId: actor,
    workspaceId: 'workspace',
    companyId: store.catalog!['companyId'] as String,
    deviceId: 'service-device',
    expiresAt: clock.add(Duration(hours: expired ? -1 : 1)),
    commands: commands ?? AgentService.commands,
    revoked: revoked,
    jobIds: jobs,
    equipmentIds: equipment,
  );
  Json request(String command, [Json? args]) => {
    'protocol_version': 1,
    'request_id': 'req-1',
    'scope': {
      'workspace_id': 'workspace',
      'company_id': store.catalog!['companyId'],
      'device_id': 'service-device',
    },
    'credential': {'token': 'synthetic-token'},
    'command': command,
    'args': args ?? <String, dynamic>{},
  };
  Json notes(
    String job, {
    String key = '11111111-1111-4111-8111-111111111111',
    String text = 'Suggested note',
  }) => {
    'idempotency_key': key,
    'type': 'inspection.notes',
    'job_id': job,
    'expected_document_hash': digest(store.documentFor(job)!),
    'notes': text,
  };
  String? code(Json response) => response['error']?['code'] as String?;
  String tables() => canonical({
    for (final table in [
      'settings',
      'documents',
      'submissions',
      'receipts',
      'invites',
      'phones',
      'events',
    ])
      table: store.db
          .select('SELECT * FROM $table')
          .map((row) => Map<String, dynamic>.from(row))
          .toList(),
  });
  Future<String> files() async => canonical({
    for (final entry in await store.evidence.root.list().toList())
      if (entry is File)
        entry.uri.pathSegments.last: digest(await entry.readAsBytes()),
  });
  setUp(() async {
    root = await Directory.systemTemp.createTemp('agent-service-test-');
    store = await LabStore.open(
      Directory('${root.path}/office'),
      office: true,
      maintenanceOnly: true,
    );
    await store.createCompany('Synthetic service company');
    equipment1 =
        (await store.addEquipment(
              name: 'Visible equipment',
              meterUnit: 'none',
            ))['id']
            as String;
    equipment2 =
        (await store.addEquipment(
              name: 'Hidden equipment',
              meterUnit: 'none',
            ))['id']
            as String;
    procedure =
        (await store.publishChecklist(
              title: 'Referenced procedure',
              items: [
                {
                  'id': 'guard',
                  'label': 'Inspect guard',
                  'input_type': 'check',
                },
              ],
            ))['id']
            as String;
    first =
        (await store.prepareWork(
              equipmentId: equipment1,
              templateId: procedure,
              title: 'Visible job',
            ))['id']
            as String;
    second =
        (await store.prepareWork(
              equipmentId: equipment2,
              templateId: procedure,
              title: 'Hidden job',
            ))['id']
            as String;
    grants = _Grants()..grant = authority();
    service = AgentService(
      store: store,
      workspaceId: 'workspace',
      serviceDeviceId: 'service-device',
      grants: grants,
      now: () => clock,
    );
  });
  tearDown(() async {
    await store.close();
    await root.delete(recursive: true);
  });

  test('default deny, invalid scope and grant authority fail closed', () async {
    final deny = AgentService(
      store: store,
      workspaceId: 'workspace',
      serviceDeviceId: 'service-device',
    );
    expect(code(await deny.handle(request('work.list'))), 'unauthorized');
    grants.grant = authority(expired: true);
    expect(code(await service.handle(request('work.list'))), 'grant_expired');
    grants.grant = authority(revoked: true);
    expect(code(await service.handle(request('work.list'))), 'grant_revoked');
    grants.grant = authority(commands: {'capabilities'});
    expect(
      code(await service.handle(request('work.list'))),
      'permission_denied',
    );
    grants.grant = authority();
    final wrong = request('work.list');
    wrong['scope']['company_id'] = 'other-company';
    expect(code(await service.handle(wrong)), 'scope_mismatch');
  });
  test(
    'strict envelope, unknown commands and unsupported writes never mutate',
    () async {
      final before = tables();
      final invalid = request('proposals.create', notes(first))
        ..['extra'] = 'secret-path';
      final response = await service.handle(invalid);
      expect(code(response), 'invalid_request');
      expect(response['scope'], isNull);
      final version = request('work.list')..['protocol_version'] = 2;
      expect(code(await service.handle(version)), 'unsupported_version');
      expect(
        code(await service.handle(request('inspection.submit'))),
        'unsupported_command',
      );
      expect(
        code(await service.handle(request('work.list', {'limit': 0}))),
        'invalid_request',
      );
      final unsupported = notes(first)..['type'] = 'inspection.apply';
      expect(
        code(await service.handle(request('proposals.create', unsupported))),
        'unsupported_proposal',
      );
      expect(tables(), before);
      expect(await service.proposals.records(), isEmpty);
    },
  );
  test(
    'job and equipment intersections apply to details, procedures and counts',
    () async {
      grants.grant = authority(jobs: {first});
      final work = await service.handle(request('work.list'));
      expect(work['result']['count'], 1);
      expect(work['result']['items'][0]['job_id'], first);
      final equipment = await service.handle(request('equipment.list'));
      expect(equipment['result']['count'], 1);
      expect(equipment['result']['items'][0]['id'], equipment1);
      expect(
        code(await service.handle(request('work.show', {'job_id': second}))),
        'not_found',
      );
      expect(
        code(
          await service.handle(
            request('equipment.show', {'equipment_id': equipment2}),
          ),
        ),
        'not_found',
      );
      expect(
        (await service.handle(request('procedures.list')))['result']['count'],
        1,
      );
      expect(
        (await service.handle(
          request('workspace.status'),
        ))['result']['local_work_count'],
        1,
      );
      grants.grant = authority(jobs: {first}, equipment: {equipment2});
      expect(
        (await service.handle(request('work.list')))['result']['count'],
        0,
      );
      expect(
        (await service.handle(request('procedures.list')))['result']['count'],
        0,
      );
      expect(
        code(await service.handle(request('proposals.create', notes(first)))),
        'not_found',
      );
      grants.grant = authority(jobs: {});
      expect(
        (await service.handle(request('equipment.list')))['result']['count'],
        0,
      );
    },
  );
  test(
    'pagination is visible-revision bound and hidden work does not change revision',
    () async {
      final page = await service.handle(request('work.list', {'limit': 1}));
      expect(page['result']['count'], 1);
      expect(page['meta']['complete'], false);
      final cursor = page['result']['next_cursor'] as String;
      final next = await service.handle(
        request('work.list', {'limit': 1, 'cursor': cursor}),
      );
      expect(next['result']['count'], 1);
      expect(next['result']['next_cursor'], isNull);
      await store.update({'notes': 'Changed visible data'}, jobId: first);
      expect(
        code(await service.handle(request('work.list', {'cursor': cursor}))),
        'stale_context',
      );
      grants.grant = authority(jobs: {first});
      final visible = await service.handle(request('work.list'));
      await store.update({'notes': 'Hidden edit'}, jobId: second);
      final unchanged = await service.handle(request('work.list'));
      expect(
        unchanged['meta']['local_revision'],
        visible['meta']['local_revision'],
      );
    },
  );
  test('all scoped reads retain every SQL table and evidence bytes', () async {
    final photo = await store.attach([1, 2, 3], jobId: first);
    final partial = File('${store.evidence.root.path}/${'a' * 64}.part');
    await partial.writeAsBytes([4, 5]);
    final before = tables(), inventory = await files();
    for (final command in [
      'workspace.status',
      'work.list',
      'equipment.list',
      'procedures.list',
      'history.list',
      'proposals.list',
    ]) {
      final reply = await service.handle(request(command));
      expect(reply['ok'], true);
      expect(reply['meta']['synced']['verified'], false);
      expect(tables(), before);
      expect(await files(), inventory);
    }
    final reply = await service.handle(request('work.show', {'job_id': first}));
    expect(reply['result']['item']['draft']['photo_state'], 'complete');
    expect(await store.evidence.complete(photo), true);
  });
  test(
    'new proposals pin exact hash, persist privately and leave store unchanged',
    () async {
      final before = tables();
      final payload = notes(first);
      final result = await service.handle(request('proposals.create', payload));
      expect(result['ok'], true);
      final item = result['result']['item'] as Json;
      expect(item['status'], 'pending_human_review');
      expect(item['applied'], false);
      expect(item['backup_included'], false);
      expect(item['human_review_available'], false);
      expect(tables(), before);
      final records = await service.proposals.records();
      expect(records, hasLength(1));
      expect(records.single['context']['jobId'], first);
      expect(records.single['actor_id'], 'external-agent');
      expect((service.proposals.root.statSync().mode & 0xfff), 0x1c0);
      final file =
          (await service.proposals.root.list().toList()).single as File;
      expect((file.statSync().mode & 0xfff), 0x180);
    },
  );
  test(
    'exact retry survives restart and later edits, changed same key rejects',
    () async {
      final payload = notes(first);
      final original = await service.handle(
        request('proposals.create', payload),
      );
      await store.update({'notes': 'Later draft edit'}, jobId: first);
      await store.close();
      store = await LabStore.open(
        Directory('${root.path}/office'),
        office: true,
        maintenanceOnly: true,
      );
      service = AgentService(
        store: store,
        workspaceId: 'workspace',
        serviceDeviceId: 'service-device',
        grants: grants,
        now: () => clock,
      );
      final retry = await service.handle(request('proposals.create', payload));
      expect(retry['result'], original['result']);
      expect(await service.proposals.records(), hasLength(1));
      final changed = Map<String, dynamic>.from(payload)
        ..['notes'] = 'Different suggestion';
      expect(
        code(await service.handle(request('proposals.create', changed))),
        'idempotency_conflict',
      );
      final stale = Map<String, dynamic>.from(payload)
        ..['idempotency_key'] = '22222222-2222-4222-8222-222222222222';
      expect(
        code(await service.handle(request('proposals.create', stale))),
        'stale_context',
      );
      expect(await service.proposals.records(), hasLength(1));
    },
  );
  test('concurrent duplicate proposals publish once', () async {
    final payload = notes(first);
    final replies = await Future.wait(
      List.generate(
        8,
        (_) => service.handle(request('proposals.create', payload)),
      ),
    );
    expect(replies.every((reply) => reply['ok'] == true), true);
    expect(
      replies.map((reply) => reply['result']['item']['proposal_id']).toSet(),
      hasLength(1),
    );
    expect(await service.proposals.records(), hasLength(1));
  });
  test(
    'post-publication flush failure stays unknown, retains the target and exact authorized retry',
    () async {
      var flushCalls = 0;
      final proposalStore = AgentProposalStore.forSyntheticTest(
        store.root,
        flushDirectory: (directory) {
          flushCalls++;
          expect(directory.path, service.proposals.root.path);
          return 1;
        },
      );
      final uncertainService = AgentService(
        store: store,
        workspaceId: 'workspace',
        serviceDeviceId: 'service-device',
        grants: grants,
        now: () => clock,
        proposals: proposalStore,
      );
      final before = tables(), payload = notes(first);
      final failure = await uncertainService.handle(
        request('proposals.create', payload),
      );
      expect(code(failure), 'internal_error');
      expect(failure['error']['outcome'], 'unknown');
      expect(failure.containsKey('result'), false);
      expect(flushCalls, 1);
      final record = (await proposalStore.records()).single;
      final saved = record['result'] as Json;
      final files = await proposalStore.root
          .list()
          .where((entry) => entry is File)
          .cast<File>()
          .toList();
      expect(files, hasLength(1));
      final bytes = await files.single.readAsBytes();
      final retry = request('proposals.create', payload)
        ..['request_id'] = 'retry-after-unknown';
      final accepted = await service.handle(retry);
      expect(accepted['ok'], true);
      expect(accepted['result']['item'], saved);
      expect(accepted['request_id'], 'retry-after-unknown');
      expect(await files.single.readAsBytes(), bytes);
      expect(await proposalStore.records(), hasLength(1));
      expect(tables(), before);
      grants.grant = authority(revoked: true);
      expect(code(await service.handle(retry)), 'grant_revoked');
      expect(await files.single.readAsBytes(), bytes);
    },
  );
  test(
    'scoped durable fingerprint ignores fresh credential and request ID but binds service scope',
    () async {
      final payload = notes(first);
      final original = await service.handle(
        request('proposals.create', payload),
      );
      final retry = request('proposals.create', payload)
        ..['request_id'] = 'fresh-request';
      grants.tokens.add('rotated-synthetic-token');
      retry['credential']['token'] = 'rotated-synthetic-token';
      retry['args'] = Map<String, dynamic>.fromEntries(
        payload.entries.toList().reversed,
      );
      expect((await service.handle(retry))['result'], original['result']);
      final record = (await service.proposals.records()).single;
      expect(record['version'], 2);
      expect(record['scope'], retry['scope']);
      expect(record['command'], 'proposals.create');
      expect(record.keys, isNot(contains('credential')));
      grants.grant = AgentGrant(
        id: 'grant',
        actorId: 'external-agent',
        workspaceId: 'new-workspace',
        companyId: store.catalog!['companyId'] as String,
        deviceId: 'new-service-device',
        expiresAt: clock.add(const Duration(hours: 1)),
        commands: AgentService.commands,
      );
      final other = AgentService(
        store: store,
        workspaceId: 'new-workspace',
        serviceDeviceId: 'new-service-device',
        grants: grants,
        now: () => clock,
      );
      final changed = request('proposals.create', payload);
      changed['scope']['workspace_id'] = 'new-workspace';
      changed['scope']['device_id'] = 'new-service-device';
      expect(code(await other.handle(changed)), 'idempotency_conflict');
      Json otherRequest(String command, [Json? args]) {
        final input = request(command, args);
        input['scope'] = Map<String, dynamic>.from(changed['scope'] as Json);
        return input;
      }

      expect(
        (await other.handle(otherRequest('proposals.list')))['result']['count'],
        0,
      );
      expect(
        (await other.handle(
          otherRequest('workspace.status'),
        ))['result']['pending_proposal_count'],
        0,
      );
      expect(
        code(
          await other.handle(
            otherRequest('proposals.show', {
              'proposal_id': original['result']['item']['proposal_id'],
            }),
          ),
        ),
        'not_found',
      );
      expect(await service.proposals.records(), hasLength(1));
    },
  );
  test(
    'UUID operation keys are case-preserving exact strings, with no silent normalization',
    () async {
      const lower = 'abcdefab-abcd-4abc-8abc-abcdefabcdef';
      final upper = lower.toUpperCase();
      final firstReply = await service.handle(
        request('proposals.create', notes(first, key: lower)),
      );
      final secondReply = await service.handle(
        request('proposals.create', notes(first, key: upper)),
      );
      expect(firstReply['ok'], true);
      expect(secondReply['ok'], true);
      expect(firstReply['result']['item']['idempotency_key'], lower);
      expect(secondReply['result']['item']['idempotency_key'], upper);
      expect(
        firstReply['result']['item']['proposal_id'],
        isNot(secondReply['result']['item']['proposal_id']),
      );
      expect(
        (await service.handle(
          request('proposals.create', notes(first, key: upper)),
        ))['result'],
        secondReply['result'],
      );
      expect(await service.proposals.records(), hasLength(2));
    },
  );
  test(
    'bounded referenced evidence never follows links or reads oversized orphan files',
    () async {
      final hash = await store.attach([40, 50, 60], jobId: first);
      final photo = File('${store.evidence.root.path}/$hash');
      final orphan = File('${store.evidence.root.path}/${'b' * 64}');
      final orphanHandle = await orphan.open(mode: FileMode.write);
      await orphanHandle.truncate(EvidenceStore.maxBytes + 1);
      await orphanHandle.close();
      final before = tables();
      expect(
        (await service.handle(
          request('work.show', {'job_id': first}),
        ))['result']['item']['draft']['photo_state'],
        'complete',
      );
      final handle = await photo.open(mode: FileMode.write);
      await handle.truncate(EvidenceStore.maxBytes + 1);
      await handle.close();
      expect(
        (await service.handle(
          request('work.show', {'job_id': first}),
        ))['result']['item']['draft']['photo_state'],
        'missingOrPartial',
      );
      await photo.delete();
      final foreign = File('${root.path}/foreign-photo');
      await foreign.writeAsBytes([40, 50, 60]);
      await Link(photo.path).create(foreign.path);
      expect(
        (await service.handle(
          request('work.show', {'job_id': first}),
        ))['result']['item']['draft']['photo_state'],
        'missingOrPartial',
      );
      expect((await service.handle(request('capabilities')))['ok'], true);
      expect(tables(), before);
      expect(await foreign.readAsBytes(), [40, 50, 60]);
      expect(await orphan.length(), EvidenceStore.maxBytes + 1);
    },
  );
  test(
    'valid large checklist keeps compact work, full procedure, bounded pages and replayable proposals',
    () async {
      final items = <Json>[
        for (var i = 0; i < 200; i++)
          {'id': 'step-$i', 'label': '界' * 1000, 'input_type': 'text'},
      ];
      final prepared = <Json>[];
      final templates = <Json>[];
      for (var i = 0; i < 2; i++) {
        final template = await store.publishChecklist(
          title: 'Large procedure $i',
          items: items,
        );
        templates.add(template);
        prepared.add(
          await store.prepareWork(
            equipmentId: equipment1,
            templateId: template['id'] as String,
            title: 'Large job $i',
          ),
        );
      }
      final job = prepared.first['id'] as String;
      final work = await service.handle(request('work.show', {'job_id': job}));
      expect(work['ok'], true);
      expect(utf8.encode(canonical(work)).length, lessThan(10000));
      expect(
        work['result']['item']['context']['checklistSnapshot']['item_count'],
        200,
      );
      expect(
        work['result']['item']['context']['checklistSnapshot']['items_included'],
        false,
      );
      final full = await service.handle(
        request('procedures.show', {'procedure_id': templates.first['id']}),
      );
      expect(full['result']['item']['items'], hasLength(200));
      expect(
        utf8.encode(canonical(full)).length,
        lessThanOrEqualTo(AgentService.maxResponseBytes),
      );
      final page = await service.handle(
        request('procedures.list', {'limit': 100}),
      );
      expect(page['ok'], true);
      expect(page['result']['count'], lessThan(3));
      expect(page['meta']['complete'], false);
      expect(page['result']['next_cursor'], isNotNull);
      expect(
        utf8.encode(canonical(page)).length,
        lessThanOrEqualTo(AgentService.maxResponseBytes),
      );
      final payload = notes(job);
      final created = await service.handle(
        request('proposals.create', payload),
      );
      expect(created['ok'], true);
      final files = await service.proposals.root
          .list()
          .where((item) => item is File)
          .cast<File>()
          .toList();
      expect(await files.single.length(), greaterThan(256 * 1024));
      expect(
        await files.single.length(),
        lessThanOrEqualTo(AgentProposalStore.maxRecordBytes),
      );
      final restarted = AgentService(
        store: store,
        workspaceId: 'workspace',
        serviceDeviceId: 'service-device',
        grants: grants,
        now: () => clock,
      );
      expect(
        (await restarted.handle(
          request('proposals.create', payload),
        ))['result'],
        created['result'],
      );
    },
  );
  test(
    'oversized immutable history detail refuses explicitly without dropping it or mutating',
    () async {
      final template = await store.publishChecklist(
        title: 'Long text answers',
        items: [
          for (var i = 0; i < 200; i++)
            {'id': 'step-$i', 'label': 'Text finding $i', 'input_type': 'text'},
        ],
      );
      final job =
          (await store.prepareWork(
                equipmentId: equipment1,
                templateId: template['id'] as String,
                title: 'Long history',
              ))['id']
              as String;
      await store.update({
        'notes': 'Inspection recorded',
        for (var i = 0; i < 200; i++)
          'answer:step-$i': {'result': 'pass', 'value': '界' * 2000},
      }, jobId: job);
      await store.attach([91, 92, 93], jobId: job);
      await store.submit(jobId: job);
      final before = tables();
      final history = await service.handle(
        request('history.list', {'job_id': job}),
      );
      expect(code(history), 'internal_error');
      expect(history['error']['outcome'], 'rejected');
      expect(history['error']['message'], contains('too large for version 1'));
      expect(history.containsKey('result'), false);
      expect(history.containsKey('meta'), false);
      final work = await service.handle(request('work.show', {'job_id': job}));
      expect(work['ok'], true);
      expect(work['result']['item']['known_history'], hasLength(1));
      expect(
        work['result']['item']['known_history'][0]['inspection_values_included'],
        false,
      );
      expect(tables(), before);
    },
  );
  test(
    'first-item byte boundary never emits an empty continuation loop',
    () async {
      final template = await store.publishChecklist(
        title: 'Byte-boundary procedure',
        items: [
          for (var i = 0; i < 200; i++)
            {
              'id': 'step-$i',
              'label': 'Boundary text $i',
              'input_type': 'text',
            },
        ],
      );
      final job =
          (await store.prepareWork(
                equipmentId: equipment1,
                templateId: template['id'] as String,
                title: 'Boundary history',
              ))['id']
              as String;
      await store.update({
        'notes': 'Boundary recorded',
        for (var i = 0; i < 200; i++)
          'answer:step-$i': {'result': 'pass', 'value': 'x'},
      }, jobId: job);
      await store.attach([94, 95, 96], jobId: job);
      await store.submit(jobId: job);
      final small = await service.handle(
        request('history.list', {'job_id': job}),
      );
      final baseline = utf8
          .encode(canonical(small['result']['items'][0]))
          .length;
      final target = AgentService.maxResultBytes - 1024 - 65;
      var remaining = target - baseline;
      final patch = <String, dynamic>{};
      for (var i = 0; i < 200 && remaining > 0; i++) {
        final extra = remaining > 11991 ? 11991 : remaining;
        patch['answer:step-$i'] = {
          'result': 'pass',
          'value': 'x${'界' * (extra ~/ 3)}${'x' * (extra % 3)}',
        };
        remaining -= extra;
      }
      expect(remaining, 0);
      await store.update(patch, jobId: job);
      await store.submit(jobId: job);
      Json args = {'job_id': job, 'limit': 1};
      var refused = false;
      for (var i = 0; i < 2; i++) {
        final response = await service.handle(request('history.list', args));
        if (response['ok'] == false) {
          expect(code(response), 'internal_error');
          expect(response['error']['outcome'], 'rejected');
          refused = true;
          break;
        }
        expect(response['result']['items'], isNotEmpty);
        expect(response['result']['next_cursor'], isNotNull);
        args = {...args, 'cursor': response['result']['next_cursor']};
      }
      expect(refused, true);
    },
  );
  test(
    'structured local references are omitted consistently across shared snapshots',
    () async {
      for (final reference in [
        'file:///home/example/manual.pdf',
        ' /home/example/manual.pdf ',
        r'\\server\share\manual.pdf',
        r'C:\private\manual.pdf',
        '~/private/manual.pdf',
        'manuals/private.pdf',
      ]) {
        final template = await store.publishChecklist(
          title: 'Private reference',
          items: [
            {'id': 'guard', 'label': 'Inspect guard', 'input_type': 'check'},
          ],
          provenance: {'kind': 'manual-reference', 'reference': reference},
        );
        for (var i = 0; i < 2; i++) {
          await store.prepareWork(
            equipmentId: equipment1,
            templateId: template['id'] as String,
            title: 'Referenced job $i',
          );
        }
        final response = await service.handle(
          request('procedures.show', {'procedure_id': template['id']}),
        );
        expect(response['ok'], true);
        expect(response['result']['item']['provenance']['reference'], isNull);
      }
      final all = await service.handle(request('procedures.list'));
      expect(all['ok'], true);
      expect(all['result']['count'], 7);
      expect((await service.handle(request('work.list')))['ok'], true);
    },
  );
  test(
    'photo completion during final authorization rejects the captured stale read',
    () async {
      final hash = await store.attach([10, 20, 30], jobId: first);
      final finalFile = File('${store.evidence.root.path}/$hash');
      final partial = await finalFile.rename('${finalFile.path}.part');
      final before = tables();
      grants.onResolve = (calls) async {
        if (calls == 2) partial.renameSync(finalFile.path);
      };
      final response = await service.handle(
        request('work.show', {'job_id': first}),
      );
      expect(code(response), 'stale_context');
      expect(tables(), before);
      grants.onResolve = null;
      expect(
        (await service.handle(
          request('work.show', {'job_id': first}),
        ))['result']['item']['draft']['photo_state'],
        'complete',
      );
    },
  );
  test(
    'replay checks revoked, expired, filters and actor before lookup result',
    () async {
      final payload = notes(first);
      await service.handle(request('proposals.create', payload));
      for (final entry in [
        (authority(revoked: true), 'grant_revoked'),
        (authority(expired: true), 'grant_expired'),
        (authority(jobs: {second}), 'not_found'),
        (authority(actor: 'different-agent'), 'unauthorized'),
      ]) {
        grants.grant = entry.$1;
        expect(
          code(await service.handle(request('proposals.create', payload))),
          entry.$2,
        );
      }
      expect(await service.proposals.records(), hasLength(1));
    },
  );
  test(
    'revocation during final read and proposal staging maps safe error without publish',
    () async {
      grants.onResolve = (calls) async {
        if (calls == 2) grants.grant = authority(revoked: true);
      };
      final read = await service.handle(request('work.list'));
      expect(code(read), 'grant_revoked');
      expect(read['error']['outcome'], 'rejected');
      grants.calls = 0;
      grants.grant = authority();
      grants.onResolve = (calls) async {
        if (calls == 4) grants.grant = authority(revoked: true);
      };
      expect(
        code(await service.handle(request('proposals.create', notes(first)))),
        'grant_revoked',
      );
      expect(await service.proposals.records(), isEmpty);
    },
  );
  test(
    'saved semantic corruption and link roots cannot leak proposal fields',
    () async {
      final payload = notes(first);
      await service.handle(request('proposals.create', payload));
      final file =
          (await service.proposals.root.list().toList()).single as File;
      final record = jsonDecode(await file.readAsString()) as Json;
      record['result']['job_id'] = second;
      record.remove('hash');
      record['hash'] = contentHash(record);
      await file.writeAsString(canonical(record), flush: true);
      final response = await service.handle(
        request('proposals.create', payload),
      );
      expect(code(response), 'internal_error');
      expect(canonical(response), isNot(contains(second)));
      await service.proposals.root.delete(recursive: true);
      final foreign = await Directory('${root.path}/foreign').create();
      await Link(service.proposals.root.path).create(foreign.path);
      expect(
        code(await service.handle(request('proposals.list'))),
        'internal_error',
      );
      expect(await foreign.list().isEmpty, true);
    },
  );
  test(
    'known history is sanitized and existing backups exclude local proposals',
    () async {
      await OfficeIdentity.load(store);
      await store.update({
        'answer:guard': {'result': 'pass', 'value': ''},
        'notes': 'Recorded finding',
      }, jobId: first);
      await store.attach([7, 8, 9], jobId: first);
      final submission = await store.submit(jobId: first);
      await store.decide(
        submission['id'] as String,
        approve: false,
        reason: 'Needs another check',
      );
      await service.handle(request('proposals.create', notes(first)));
      final response = await service.handle(
        request('history.list', {'job_id': first}),
      );
      expect(response['result']['count'], 1);
      final item = response['result']['items'][0] as Json;
      expect(item['known_decision']['decision'], 'returned');
      expect(canonical(item), isNot(contains('"document":')));
      expect(canonical(item), isNot(contains('"_jobId":')));
      final backup = Directory('${root.path}/backup');
      await OfficeBackup.create(store, backup);
      expect(
        await Directory('${backup.path}/agent-proposals-v1').exists(),
        false,
      );
      expect(await service.proposals.records(), hasLength(1));
    },
  );
  test(
    'actual private Unix transport executes scoped native reads and proposals',
    () async {
      // Linux Unix sockaddr paths are bounded; the fixture workspace stays in
      // the scoped test TMPDIR while its private socket uses a short temp path.
      final socketDir = await Directory('/tmp').createTemp('agent-unix-');
      await Process.run('/usr/bin/chmod', ['700', socketDir.path]);
      final transport = await UnixAgentTransport.start(
        socketPath: '${socketDir.path}/service.sock',
        handler: service.handle,
      );
      try {
        final socket = await Socket.connect(
          InternetAddress(transport.socketPath, type: InternetAddressType.unix),
          0,
        );
        final lines = StreamIterator(
          socket
              .cast<List<int>>()
              .transform(utf8.decoder)
              .transform(const LineSplitter()),
        );
        socket.writeln(canonical(request('work.list')));
        await socket.flush();
        expect(await lines.moveNext(), true);
        final work = jsonDecode(lines.current) as Json;
        expect(work['ok'], true);
        expect(work['result']['count'], 2);
        socket.writeln(canonical(request('proposals.create', notes(first))));
        await socket.flush();
        expect(await lines.moveNext(), true);
        final proposal = jsonDecode(lines.current) as Json;
        expect(proposal['result']['item']['applied'], false);
        socket.destroy();
        await lines.cancel();
      } finally {
        await transport.close();
        await socketDir.delete(recursive: true);
      }
    },
  );
}
