import 'dart:convert';
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/agent_service/access_models.dart';
import 'package:maintenance_local/agent_service/access_scope.dart';
import 'package:maintenance_local/agent_service/agent_host.dart';
import 'package:maintenance_local/agent_service/agent_service.dart';
import 'package:maintenance_local/agent_service/grant_store.dart';
import 'package:maintenance_local/agent_service/proposal_store.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/local_sync.dart';
import 'package:maintenance_local/model.dart';
import 'package:maintenance_local/office_backup.dart';
import 'package:maintenance_local/procedure_library_store.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';

const _privateDraft = 'SYNTHETIC_PRIVATE_OFFICE_DRAFT_LF005';

// These fixtures create fresh private directories only. The grants below are
// real temporary capabilities issued by the new store, never fixed mock tokens.
void main() {
  final clock = DateTime.utc(2026, 10, 1, 12);
  late Directory root;
  late LabStore office;
  late AgentAccessScope scope;
  late OfficeAgentGrantStore access;
  late AgentService service;
  late String equipment, otherEquipment, job, otherJob, procedure;
  final stores = <LabStore>[];
  final accessStores = <OfficeAgentGrantStore>[];
  final hosts = <OfficeAgentHost>[];
  var requestId = 0;

  setUpAll(() async {
    await RustLib.init(
      externalLibrary: ExternalLibrary.open(
        File(
          Platform.environment['MAINTENANCE_NATIVE_LIBRARY'] ??
              'rust/target/debug/librust_lib_sync_lab.so',
        ).absolute.path,
      ),
    );
  });
  tearDownAll(RustLib.dispose);

  Future<LabStore> open(String name, {bool isOffice = true}) async {
    final store = await LabStore.open(
      Directory('${root.path}/$name'),
      office: isOffice,
      maintenanceOnly: true,
      now: () => clock,
    );
    stores.add(store);
    return store;
  }

  Future<OfficeAgentGrantStore> openAccess(
    LabStore store,
    AgentAccessScope identity,
  ) async {
    final grants = await OfficeAgentGrantStore.open(
      workspaceRoot: store.root,
      scope: identity,
      now: () => clock,
    );
    accessStores.add(grants);
    return grants;
  }

  AgentGrantRequest grantRequest({
    Set<String>? jobs,
    Set<String>? assets,
    bool allowNotes = false,
  }) => AgentGrantRequest(
    label: 'Synthetic boundary agent',
    expiresAt: clock.add(const Duration(hours: 2)),
    jobIds: jobs ?? {job},
    equipmentIds: assets ?? {equipment},
    allowNotes: allowNotes,
  );

  Json request(String token, String command, [Json? arguments]) => {
    'protocol_version': 1,
    'request_id': 'boundary-${++requestId}',
    'scope': scope.toJson(),
    'credential': {'token': token},
    'command': command,
    'args': arguments ?? <String, dynamic>{},
  };

  Future<Json> call(String token, String command, [Json? arguments]) async {
    final response = await service.handle(request(token, command, arguments));
    // Boolean comparisons keep credentials out of failure diagnostics too.
    expect(canonical(response).contains(token), false);
    return response;
  }

  Json successful(Json response) {
    expect(response['ok'], true);
    expect(response['scope'], scope.toJson());
    expect(response['meta']['synced']['verified'], false);
    return response['result'] as Json;
  }

  String? error(Json response) => response['error']?['code'] as String?;

  Json notes({String operation = '11111111-1111-4111-8111-111111111111'}) => {
    'idempotency_key': operation,
    'type': 'inspection.notes',
    'job_id': job,
    'expected_document_hash': digest(office.documentFor(job)!),
    'notes': 'Synthetic pending note; inspection remains unchanged.',
  };

  String sqlFingerprint(LabStore store) {
    final schema = store.db.select(
      "SELECT name,sql FROM sqlite_schema WHERE type='table' "
      "AND name NOT LIKE 'sqlite_%' ORDER BY name",
    );
    return contentHash({
      'schema': schema.map((row) => Map<String, dynamic>.from(row)).toList(),
      'tables': {
        for (final row in schema)
          row['name'] as String: store.db
              .select('SELECT * FROM "${row['name']}" ORDER BY rowid')
              .map((value) => Map<String, dynamic>.from(value))
              .toList(),
      },
    });
  }

  Future<Json> evidenceInventory(LabStore store) async => {
    if (await store.evidence.root.exists())
      for (final entity in await store.evidence.root.list().toList())
        if (entity is File)
          entity.uri.pathSegments.last: digest(await entity.readAsBytes()),
  };

  Future<Json> privateDraft() async {
    final copy = await office.copyProcedureDraft(
      procedure,
      operationId: 'lf005-private-copy',
    );
    return office.saveProcedureDraft(
      draftId: copy['id'] as String,
      expectedRevision: 1,
      title: _privateDraft,
      items: [
        {
          ...Map<String, dynamic>.from((copy['items'] as List).single as Map),
          'label': '',
        },
      ],
      operationId: 'lf005-private-save',
    );
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('lf005-boundary-');
    office = await open('office');
    await office.createCompany('Synthetic agent boundary company');
    equipment =
        (await office.addEquipment(
              name: 'Selected synthetic equipment',
              meterUnit: 'none',
            ))['id']
            as String;
    otherEquipment =
        (await office.addEquipment(
              name: 'Unselected synthetic equipment',
              meterUnit: 'none',
            ))['id']
            as String;
    procedure =
        (await office.publishChecklist(
              title: 'Synthetic boundary inspection',
              items: [
                {
                  'id': 'guard',
                  'label': 'Inspect guard',
                  'input_type': 'check',
                },
              ],
            ))['id']
            as String;
    job =
        (await office.prepareWork(
              equipmentId: equipment,
              templateId: procedure,
              title: 'Selected synthetic job',
            ))['id']
            as String;
    otherJob =
        (await office.prepareWork(
              equipmentId: otherEquipment,
              templateId: procedure,
              title: 'Unselected synthetic job',
            ))['id']
            as String;
    scope = AgentAccessScope.forOffice(office)!;
    access = await openAccess(office, scope);
    await access.setEnabled(true);
    service = AgentService(
      store: office,
      workspaceId: scope.workspaceId,
      serviceDeviceId: scope.deviceId,
      grants: access,
      now: () => clock,
    );
  });

  tearDown(() async {
    for (final host in hosts.reversed) {
      await host.close();
    }
    hosts.clear();
    for (final grants in accessStores.reversed) {
      await grants.close();
    }
    accessStores.clear();
    for (final store in stores.reversed) {
      await store.close();
    }
    stores.clear();
    await root.delete(recursive: true);
  });

  test(
    'phones and unprepared offices have no agent scope or constructor IO',
    () async {
      final unprepared = await open('unprepared');
      final phone = await open('phone', isOffice: false);
      expect(AgentAccessScope.forOffice(unprepared), isNull);
      expect(AgentAccessScope.forOffice(phone), isNull);
      final host = OfficeAgentHost(
        store: unprepared,
        runtimeDirectory: Directory('${root.path}/unprepared-runtime'),
        now: () => clock,
      );
      hosts.add(host);
      expect(host.scope, isNull);
      expect(host.snapshot.enabled, false);
      expect(host.snapshot.socketPath, isNull);
      expect(
        await Directory('${unprepared.root.path}/agent-access-v1').exists(),
        false,
      );
      await host.initialize();
      expect(host.scope, isNull);
      expect(host.snapshot.state, OfficeAgentHostState.disabled);
      expect(
        await Directory('${unprepared.root.path}/agent-access-v1').exists(),
        false,
      );
      expect(
        await Directory('${root.path}/unprepared-runtime').exists(),
        false,
      );
    },
  );

  test(
    'coherent recovery preserves scope but excludes credentials and pending sidecars',
    () async {
      await privateDraft();
      final issued = await access.issue(grantRequest(allowNotes: true));
      successful(await call(issued.token, 'proposals.create', notes()));
      expect(
        await Directory('${office.root.path}/agent-access-v1').exists(),
        true,
      );
      expect(
        await Directory('${office.root.path}/agent-proposals-v1').exists(),
        true,
      );
      final identity = await OfficeIdentity.load(office);
      final documentHash = digest(office.documentFor(job)!);
      final sourceDrafts = contentHash(office.procedureDrafts);
      final backup = Directory('${root.path}/backup');
      await OfficeBackup.create(office, backup);
      final manifest =
          jsonDecode(await File('${backup.path}/manifest.json').readAsString())
              as Json;
      final names = (manifest['files'] as Map).keys.cast<String>();
      expect(names.any((name) => name.startsWith('agent-access-v1')), false);
      expect(names.any((name) => name.startsWith('agent-proposals-v1')), false);
      expect(await Directory('${backup.path}/agent-access-v1').exists(), false);
      expect(
        await Directory('${backup.path}/agent-proposals-v1').exists(),
        false,
      );

      final restoredPath = Directory('${root.path}/restored');
      await OfficeBackup.restore(
        backup,
        restoredPath,
        expectedFingerprint: identity.fingerprint,
        requiredFormat: OfficeBackupFormat.maintenance,
      );
      expect(
        await Directory('${restoredPath.path}/agent-access-v1').exists(),
        false,
      );
      expect(
        await Directory('${restoredPath.path}/agent-proposals-v1').exists(),
        false,
      );
      final restored = await open('restored');
      final restoredScope = AgentAccessScope.forOffice(restored)!;
      expect(restoredScope.toJson(), scope.toJson());
      expect(restoredScope.workspaceId, startsWith('ws-'));
      expect(digest(restored.documentFor(job)!), documentHash);
      expect(contentHash(restored.procedureDrafts), sourceDrafts);
      final host = OfficeAgentHost(
        store: restored,
        runtimeDirectory: Directory('${root.path}/restored-runtime'),
        now: () => clock,
      );
      hosts.add(host);
      // Constructing the restored host must not recreate any private sidecar.
      expect(
        await Directory('${restoredPath.path}/agent-access-v1').exists(),
        false,
      );
      await host.initialize();
      expect(host.scope!.toJson(), scope.toJson());
      expect(host.snapshot.state, OfficeAgentHostState.disabled);
      expect(host.snapshot.enabled, false);
      expect(host.snapshot.socketPath, isNull);
      expect(host.grants, isEmpty);
      expect(await Directory('${root.path}/restored-runtime').exists(), false);
      expect(
        await Directory('${restoredPath.path}/agent-proposals-v1').exists(),
        false,
      );
      await host.close();
      hosts.remove(host);

      final restoredAccess = await openAccess(restored, restoredScope);
      expect(await restoredAccess.enabled(), false);
      expect(await restoredAccess.resolve(issued.token), isNull);
      await restoredAccess.setEnabled(true);
      expect(await restoredAccess.resolve(issued.token), isNull);
      final restoredService = AgentService(
        store: restored,
        workspaceId: restoredScope.workspaceId,
        serviceDeviceId: restoredScope.deviceId,
        grants: restoredAccess,
        now: () => clock,
      );
      expect(
        error(await restoredService.handle(request(issued.token, 'work.list'))),
        'unauthorized',
      );
      expect(await AgentProposalStore(restored.root).records(), isEmpty);
    },
  );

  test('issued record sets never broaden to new jobs or equipment', () async {
    final issued = await access.issue(grantRequest());
    final resolved = (await access.resolve(issued.token))!;
    expect(resolved.jobIds, {job});
    expect(resolved.equipmentIds, {equipment});
    final laterJob =
        (await office.prepareWork(
              equipmentId: equipment,
              templateId: procedure,
              title: 'Later synthetic job on selected equipment',
            ))['id']
            as String;
    final laterEquipment =
        (await office.addEquipment(name: 'Later synthetic equipment'))['id']
            as String;
    final work = successful(await call(issued.token, 'work.list'));
    expect(work['count'], 1);
    expect((work['items'] as List).single['job_id'], job);
    final assets = successful(await call(issued.token, 'equipment.list'));
    expect(assets['count'], 1);
    expect((assets['items'] as List).single['id'], equipment);
    for (final hidden in [otherJob, laterJob]) {
      expect(
        error(await call(issued.token, 'work.show', {'job_id': hidden})),
        'not_found',
      );
    }
    for (final hidden in [otherEquipment, laterEquipment]) {
      expect(
        error(
          await call(issued.token, 'equipment.show', {'equipment_id': hidden}),
        ),
        'not_found',
      );
    }
    expect((await access.resolve(issued.token))!.jobIds, {job});
    expect((await access.resolve(issued.token))!.equipmentIds, {equipment});
  });

  test('explicit empty job selection exposes no job-derived records', () async {
    final issued = await access.issue(grantRequest(jobs: {}));
    expect((await access.resolve(issued.token))!.jobIds, isEmpty);
    expect((await access.resolve(issued.token))!.equipmentIds, {equipment});
    for (final command in [
      'work.list',
      'equipment.list',
      'procedures.list',
      'history.list',
      'proposals.list',
    ]) {
      final result = successful(await call(issued.token, command));
      expect(result['count'], 0, reason: command);
      expect(result['items'], isEmpty, reason: command);
    }
    expect(
      error(await call(issued.token, 'work.show', {'job_id': job})),
      'not_found',
    );
    final status = successful(await call(issued.token, 'workspace.status'));
    expect(status['local_work_count'], 0);
    expect(status['local_equipment_count'], 0);
  });

  test('read-only issued grant cannot create a pending note', () async {
    final issued = await access.issue(grantRequest());
    final before = sqlFingerprint(office);
    final capabilities = successful(await call(issued.token, 'capabilities'));
    expect(capabilities['commands'], isNot(contains('proposals.create')));
    expect(capabilities['proposal_types'], isEmpty);
    expect(
      error(await call(issued.token, 'proposals.create', notes())),
      'permission_denied',
    );
    expect(sqlFingerprint(office), before);
    expect(
      await Directory('${office.root.path}/agent-proposals-v1').exists(),
      false,
    );
  });

  test(
    'pending notes and exact retries preserve every SQL row, document and approved history',
    () async {
      await privateDraft();
      await office.update({
        'answer:guard': {'result': 'pass', 'value': ''},
        'notes': 'Synthetic approved observation',
      }, jobId: job);
      await office.attach([1, 2, 3, 4], jobId: job);
      final submission = await office.submit(jobId: job);
      await office.decide(submission['id'] as String, approve: true);
      final issued = await access.issue(grantRequest(allowNotes: true));
      final sql = sqlFingerprint(office);
      final document = digest(office.documentFor(job)!);
      final evidence = await evidenceInventory(office);
      final beforeWork = successful(
        await call(issued.token, 'work.show', {'job_id': job}),
      );
      final beforeHistory = successful(
        await call(issued.token, 'history.list'),
      );
      expect(beforeHistory['count'], 1);
      final payload = notes();
      final created = successful(
        await call(issued.token, 'proposals.create', payload),
      );
      expect(created['item']['status'], 'pending_human_review');
      expect(created['item']['applied'], false);
      final replay = successful(
        await call(issued.token, 'proposals.create', payload),
      );
      expect(replay, created);
      expect(
        successful(await call(issued.token, 'proposals.list'))['count'],
        1,
      );
      expect((await AgentProposalStore(office.root).records()).length, 1);
      expect(sqlFingerprint(office), sql);
      expect(digest(office.documentFor(job)!), document);
      expect(await evidenceInventory(office), evidence);
      expect(
        successful(await call(issued.token, 'work.show', {'job_id': job})),
        beforeWork,
      );
      expect(
        successful(await call(issued.token, 'history.list')),
        beforeHistory,
      );
    },
  );

  test(
    'issued grants expose frozen publications but never private office drafts',
    () async {
      final draft = await privateDraft();
      final issued = await access.issue(grantRequest(allowNotes: true));
      for (final command in AgentService.commands.where(
        (value) => !value.endsWith('.show') && value != 'proposals.create',
      )) {
        final response = await call(issued.token, command);
        successful(response);
        expect(
          canonical(response).contains(_privateDraft),
          false,
          reason: command,
        );
        expect(
          canonical(response).contains(draft['id'] as String),
          false,
          reason: command,
        );
      }
      final publication = successful(
        await call(issued.token, 'procedures.show', {
          'procedure_id': procedure,
        }),
      );
      expect(publication['item']['id'], procedure);
      expect(
        error(
          await call(issued.token, 'procedures.show', {
            'procedure_id': draft['id'],
          }),
        ),
        'not_found',
      );
      expect(office.procedureDrafts.single['title'], _privateDraft);
    },
  );
}
