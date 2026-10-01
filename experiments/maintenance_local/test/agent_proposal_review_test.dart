import 'dart:convert';
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/agent_service/agent_service.dart';
import 'package:maintenance_local/agent_service/grants.dart';
import 'package:maintenance_local/agent_service/proposal_review.dart';
import 'package:maintenance_local/agent_service/proposal_store.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/local_sync.dart';
import 'package:maintenance_local/model.dart';
import 'package:maintenance_local/office_backup.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';
import 'package:sqlite3/sqlite3.dart';

import 'support/recovery_process_harness.dart';

// The child uses the production review command and pauses only after commit.
// It emits no command response, so SIGKILL models a lost response to the human.
const _committedReviewChild = r'''
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:maintenance_local/agent_service/proposal_review.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/model.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';
Future<void> main(List<String> args) async {
  final control = Directory(args.single);
  final config = jsonDecode(await File('${control.path}/config.json').readAsString()) as Json;
  await RustLib.init(externalLibrary: ExternalLibrary.open(config['library'] as String));
  final store = await LabStore.open(Directory(config['workspace'] as String), office: true, maintenanceOnly: true);
  final reviewer = AgentProposalReviewer(store: store, workspaceId: 'workspace', serviceDeviceId: store.device);
  final view = await reviewer.show(config['proposal_id'] as String);
  await reviewer.decide(view, operationId: config['operation_id'] as String, accept: true);
  final keepAlive = ReceivePort();
  try {
    await File('${control.path}/ready').writeAsString(canonical({'pid': pid, 'phase': 'committed-no-response'}), flush: true);
    await Completer<void>().future;
  } finally {keepAlive.close();}
}
''';

// Every identity, company, native database, sidecar and backup below is freshly
// created under a synthetic temp root. No runtime grants or live data are used.
class _SyntheticGrants implements GrantProvider {
  AgentGrant? grant;
  @override
  Future<AgentGrant?> resolve(String token) async =>
      token == 'synthetic-review-token' ? grant : null;
}

void main() {
  final now = DateTime.utc(2026, 10, 1, 16);
  const createKey = '11111111-1111-4111-8111-111111111111';
  const secondCreateKey = '22222222-2222-4222-8222-222222222222';
  const reviewKey = '33333333-3333-4333-8333-333333333333';
  const secondReviewKey = '44444444-4444-4444-8444-444444444444';
  const suggestion =
      'Suggested replacement: inspect the synthetic guard again.';
  late Directory root;
  late LabStore store;
  late String job, equipment, procedure;
  late _SyntheticGrants grants;
  late AgentService service;
  late AgentProposalReviewer reviewer;
  late Directory childScripts;
  late File childScript;
  final extraStores = <LabStore>[];

  AgentGrant grant() => AgentGrant(
    id: 'synthetic-review-grant',
    actorId: 'synthetic-review-agent',
    workspaceId: 'workspace',
    companyId: store.catalog!['companyId'] as String,
    deviceId: store.device,
    expiresAt: now.add(const Duration(hours: 1)),
    commands: AgentService.commands,
  );
  void bind() {
    grants = _SyntheticGrants()..grant = grant();
    service = AgentService(
      store: store,
      workspaceId: 'workspace',
      serviceDeviceId: store.device,
      grants: grants,
      now: () => now,
    );
    reviewer = AgentProposalReviewer(
      store: store,
      workspaceId: 'workspace',
      serviceDeviceId: store.device,
    );
  }

  Json request(Json args) => {
    'protocol_version': 1,
    'request_id': 'synthetic-review-request',
    'scope': {
      'workspace_id': 'workspace',
      'company_id': store.catalog!['companyId'],
      'device_id': store.device,
    },
    'credential': {'token': 'synthetic-review-token'},
    'command': 'proposals.create',
    'args': args,
  };
  Json payload({String key = createKey, String notes = suggestion}) => {
    'type': 'inspection.notes',
    'job_id': job,
    'expected_document_hash': digest(store.documentFor(job)!),
    'notes': notes,
    'idempotency_key': key,
  };
  Future<NotesProposalView> propose({
    String key = createKey,
    String notes = suggestion,
  }) async {
    final response = await service.handle(
      request(payload(key: key, notes: notes)),
    );
    expect(response['ok'], true, reason: canonical(response));
    return reviewer.show(response['result']['item']['proposal_id'] as String);
  }

  Future<void> failure(Future<Json> Function() action, String code) =>
      expectLater(
        Future<Json>.sync(action),
        throwsA(
          isA<ProposalReviewFailure>().having((e) => e.code, 'code', code),
        ),
      );
  String tables([LabStore? source]) {
    final s = source ?? store;
    return canonical({
      for (final table in [
        'settings',
        'documents',
        'submissions',
        'receipts',
        'events',
        'phones',
        'invites',
      ])
        table: s.db
            .select('SELECT * FROM $table ORDER BY rowid')
            .map((row) => Map<String, dynamic>.from(row))
            .toList(),
    });
  }

  Future<String> sidecars() async => canonical({
    for (final entity in await service.proposals.root.list().toList())
      if (entity is File)
        entity.uri.pathSegments.last: digest(await entity.readAsBytes()),
  });
  Future<void> reopen() async {
    final path = store.root;
    await store.close();
    store = await LabStore.open(
      path,
      office: true,
      maintenanceOnly: true,
      now: () => now,
    );
    bind();
  }

  Future<void> crashAfterCommit(NotesProposalView view) async {
    final control = await Directory('${root.path}/commit-crash').create();
    final workspace = store.root;
    await File('${control.path}/config.json').writeAsString(
      canonical({
        'library': Platform.environment['MAINTENANCE_NATIVE_LIBRARY'],
        'workspace': workspace.path,
        'proposal_id': view.proposal.id,
        'operation_id': reviewKey,
      }),
      flush: true,
    );
    await store.close();
    Process? child;
    try {
      child = await Process.start(RecoveryProcess.dart, [
        '--suppress-analytics',
        'run',
        childScript.path,
        control.path,
      ]);
      final output = child.stdout.transform(utf8.decoder).join();
      final errors = child.stderr.transform(utf8.decoder).join();
      int? exited;
      child.exitCode.then((code) => exited = code);
      final ready = File('${control.path}/ready');
      final deadline = DateTime.now().add(const Duration(seconds: 25));
      while (!await ready.exists() &&
          exited == null &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      if (!await ready.exists()) {
        child.kill(ProcessSignal.sigkill);
        await child.exitCode.timeout(const Duration(seconds: 5));
        fail(
          'Synthetic child did not reach its committed gate: ${await errors}',
        );
      }
      final gate = jsonDecode(await ready.readAsString()) as Json;
      expect(
        gate['pid'],
        child.pid,
        reason: 'Kill the exact VM that committed the synthetic review.',
      );
      expect(gate['phase'], 'committed-no-response');
      expect(child.kill(ProcessSignal.sigkill), true);
      expect(await child.exitCode.timeout(const Duration(seconds: 5)), -9);
      expect(await output, isEmpty);
      expect(
        (await errors).replaceAll('Running build hooks...', '').trim(),
        isEmpty,
      );
      expect(await Directory('/proc/${child.pid}').exists(), false);
    } finally {
      if (child != null) {
        child.kill(ProcessSignal.sigkill);
        await child.exitCode.timeout(const Duration(seconds: 5));
      }
      store = await LabStore.open(
        workspace,
        office: true,
        maintenanceOnly: true,
        now: () => now,
      );
      bind();
    }
  }

  Json rehashed(Json value) {
    final clean = Map<String, dynamic>.from(
      jsonDecode(canonical(value)) as Json,
    )..remove('hash');
    return {...clean, 'hash': contentHash(clean)};
  }

  NotesProposal duplicateCreation(NotesProposal original) {
    final record = original.record;
    record['result']['proposal_id'] = '55555555-5555-4555-8555-555555555555';
    return NotesProposal.fromRecord(rehashed(record));
  }

  setUpAll(() async {
    await RustLib.init(
      externalLibrary: ExternalLibrary.open(
        Platform.environment['MAINTENANCE_NATIVE_LIBRARY']!,
      ),
    );
    childScripts = await Directory(
      '.dart_tool',
    ).createTemp('agent-review-crash-');
    childScript = await File(
      '${childScripts.absolute.path}/committed_review.dart',
    ).writeAsString(_committedReviewChild, flush: true);
  });
  tearDownAll(() => childScripts.delete(recursive: true));
  setUp(() async {
    root = await Directory.systemTemp.createTemp('agent-human-review-test-');
    store = await LabStore.open(
      Directory('${root.path}/office'),
      office: true,
      maintenanceOnly: true,
      now: () => now,
    );
    await store.createCompany('Synthetic human review company');
    equipment =
        (await store.addEquipment(
              name: 'Synthetic compressor',
              meterUnit: 'hours',
            ))['id']
            as String;
    procedure =
        (await store.publishChecklist(
              title: 'Synthetic published procedure',
              items: [
                {
                  'id': 'guard',
                  'label': 'Inspect synthetic guard',
                  'input_type': 'check',
                },
              ],
            ))['id']
            as String;
    job =
        (await store.prepareWork(
              equipmentId: equipment,
              templateId: procedure,
              title: 'Synthetic prepared inspection',
            ))['id']
            as String;
    await store.update({
      'notes': 'Original human note',
      'meter': 12.5,
      'answer:guard': {'result': 'pass', 'value': ''},
    }, jobId: job);
    await store.attach([1, 2, 3, 4], jobId: job);
    bind();
  });
  tearDown(() async {
    for (final extra in extraStores) {
      await extra.close();
    }
    extraStores.clear();
    await store.close();
    await root.delete(recursive: true);
  });

  test(
    'real service proposal is human-applied to notes only; create replay remains frozen',
    () async {
      final args = payload();
      final created = await service.handle(request(args));
      expect(created['ok'], true);
      final frozenResult = canonical(created['result']);
      final id = created['result']['item']['proposal_id'] as String;
      final view = await reviewer.show(id);
      final beforeFields = await store.fields(jobId: job);
      final beforeCatalog = canonical(store.catalog);
      final beforeSubmissions = canonical(store.submissions),
          beforeApprovals = canonical(store.receipts);
      final beforeSelection = store.activeJobId, beforeFiles = await sidecars();
      expect(view.stale, false);
      expect((await reviewer.pending()).map((p) => p.id), [id]);
      final receipt = await reviewer.decide(
        view,
        operationId: reviewKey,
        accept: true,
      );
      final after = await store.fields(jobId: job);
      expect(after['notes'], [suggestion]);
      expect({...after}..remove('notes'), {...beforeFields}..remove('notes'));
      expect(canonical(store.catalog), beforeCatalog);
      expect(canonical(store.submissions), beforeSubmissions);
      expect(canonical(store.receipts), beforeApprovals);
      expect(store.activeJobId, beforeSelection);
      expect(receipt['decision'], 'applied');
      expect(receipt['beforeDocumentHash'], view.currentHash);
      expect(receipt['afterDocumentHash'], digest(store.documentFor(job)!));
      expect(await reviewer.pending(), isEmpty);
      expect(await reviewer.history(), [receipt]);
      expect(await sidecars(), beforeFiles);
      final replay = await service.handle(request(args));
      expect(replay['ok'], true);
      expect(canonical(replay['result']), frozenResult);
      expect(replay['result']['item']['status'], 'pending_human_review');
      expect(replay['result']['item']['applied'], false);
    },
  );

  test(
    'SIGKILL after committed review preserves exact replay through later edit and reopen',
    () async {
      final view = await propose();
      await crashAfterCommit(view);
      final receipt = (await reviewer.history()).single;
      expect(receipt['decision'], 'applied');
      expect((await store.fields(jobId: job))['notes'], [suggestion]);
      await store.update({'notes': 'Later independent human edit'}, jobId: job);
      await reopen();
      final before = tables();
      expect(
        await reviewer.decide(view, operationId: reviewKey, accept: true),
        receipt,
      );
      expect(tables(), before);
      await failure(
        () => reviewer.decide(
          view,
          operationId: reviewKey,
          accept: false,
          reason: 'Changed decision',
        ),
        'idempotency_conflict',
      );
      final fresh = await reviewer.show(view.proposal.id);
      await failure(
        () => reviewer.decide(fresh, operationId: reviewKey, accept: true),
        'idempotency_conflict',
      );
      expect(tables(), before);
      expect((await store.fields(jobId: job))['notes'], [
        'Later independent human edit',
      ]);
    },
  );

  test(
    'stale acceptance never mutates; refreshed stale suggestion can be rejected with a reason',
    () async {
      final original = await propose();
      await store.update({'notes': 'Human edit after suggestion'}, jobId: job);
      final before = tables(), beforeFiles = await sidecars();
      await failure(
        () => reviewer.decide(original, operationId: reviewKey, accept: true),
        'stale_context',
      );
      final refreshed = await reviewer.show(original.proposal.id);
      expect(refreshed.stale, true);
      await failure(
        () => reviewer.decide(refreshed, operationId: reviewKey, accept: true),
        'stale_context',
      );
      expect(tables(), before);
      expect(await sidecars(), beforeFiles);
      final receipt = await reviewer.decide(
        refreshed,
        operationId: reviewKey,
        accept: false,
        reason: 'Human notes already updated.',
      );
      expect(receipt['decision'], 'rejected');
      expect(receipt['beforeDocumentHash'], receipt['afterDocumentHash']);
      expect((await store.fields(jobId: job))['notes'], [
        'Human edit after suggestion',
      ]);
      expect(store.submissions, isEmpty);
      expect(store.receipts, isEmpty);
      expect(await reviewer.pending(), isEmpty);
    },
  );

  test(
    'rejection requires a reason, exact replay survives editing, and changed reasons conflict',
    () async {
      final view = await propose();
      final before = tables();
      await failure(
        () => reviewer.decide(
          view,
          operationId: reviewKey,
          accept: false,
          reason: '   ',
        ),
        'invalid_request',
      );
      await failure(
        () => reviewer.decide(view, operationId: 'not-a-uuid', accept: true),
        'invalid_request',
      );
      await failure(
        () => reviewer.decide(
          view,
          operationId: reviewKey,
          accept: true,
          reason: 'Unexpected reason',
        ),
        'invalid_request',
      );
      expect(tables(), before);
      final receipt = await reviewer.decide(
        view,
        operationId: reviewKey,
        accept: false,
        reason: 'Unhelpful suggestion.',
      );
      final document = digest(store.documentFor(job)!);
      expect(document, view.currentHash);
      await store.update({'notes': 'Later human notes'}, jobId: job);
      await reopen();
      final after = tables();
      expect(
        await reviewer.decide(
          view,
          operationId: reviewKey,
          accept: false,
          reason: 'Unhelpful suggestion.',
        ),
        receipt,
      );
      await failure(
        () => reviewer.decide(
          view,
          operationId: reviewKey,
          accept: false,
          reason: 'Different reason.',
        ),
        'idempotency_conflict',
      );
      expect(tables(), after);
    },
  );

  test(
    'one terminal decision per proposal and creation key; different operation cannot decide twice',
    () async {
      final view = await propose();
      await reviewer.decide(
        view,
        operationId: reviewKey,
        accept: false,
        reason: 'Rejected once.',
      );
      final before = tables();
      await failure(
        () => reviewer.decide(
          view,
          operationId: secondReviewKey,
          accept: false,
          reason: 'Rejected again.',
        ),
        'already_decided',
      );
      final duplicate = duplicateCreation(view.proposal);
      final duplicateView = NotesProposalView(
        proposal: duplicate,
        currentHash: view.currentHash,
        currentNotes: view.currentNotes,
        receipt: null,
      );
      await failure(
        () => reviewer.decide(
          duplicateView,
          operationId: secondReviewKey,
          accept: false,
          reason: 'Same creation under new ID.',
        ),
        'already_decided',
      );
      expect(tables(), before);
      expect(await reviewer.history(), hasLength(1));
    },
  );

  test(
    'SQL failure rolls back notes, saved state and receipt atomically; same operation can retry',
    () async {
      final view = await propose();
      store.db.execute(
        "CREATE TRIGGER synthetic_review_failure BEFORE INSERT ON events WHEN NEW.kind = 'agent_notes_reviewed_v1' BEGIN SELECT RAISE(ABORT, 'synthetic rollback'); END",
      );
      final before = tables(), beforeFiles = await sidecars();
      await expectLater(
        reviewer.decide(view, operationId: reviewKey, accept: true),
        throwsA(isA<SqliteException>()),
      );
      expect(tables(), before);
      expect(await sidecars(), beforeFiles);
      expect(await reviewer.history(), isEmpty);
      expect((await store.fields(jobId: job))['notes'], [
        'Original human note',
      ]);
      store.db.execute('DROP TRIGGER synthetic_review_failure');
      final receipt = await reviewer.decide(
        view,
        operationId: reviewKey,
        accept: true,
      );
      expect(receipt['decision'], 'applied');
      expect(await reviewer.history(), hasLength(1));
      expect((await store.fields(jobId: job))['notes'], [suggestion]);
    },
  );

  test(
    'phone, wrong workspace and wrong service device cannot review or mutate',
    () async {
      final view = await propose();
      final before = tables();
      final wrongWorkspace = AgentProposalReviewer(
        store: store,
        workspaceId: 'other-workspace',
        serviceDeviceId: store.device,
      );
      expect(await wrongWorkspace.pending(), isEmpty);
      await expectLater(
        wrongWorkspace.show(view.proposal.id),
        throwsA(
          isA<ProposalReviewFailure>().having(
            (e) => e.code,
            'code',
            'not_found',
          ),
        ),
      );
      await failure(
        () => wrongWorkspace.decide(view, operationId: reviewKey, accept: true),
        'scope_mismatch',
      );
      final wrongDevice = AgentProposalReviewer(
        store: store,
        workspaceId: 'workspace',
        serviceDeviceId: 'other-service-device',
      );
      await expectLater(
        wrongDevice.pending(),
        throwsA(
          isA<ProposalReviewFailure>().having(
            (e) => e.code,
            'code',
            'scope_mismatch',
          ),
        ),
      );
      await failure(
        () => wrongDevice.decide(view, operationId: reviewKey, accept: true),
        'scope_mismatch',
      );
      final phone = await LabStore.open(
        Directory('${root.path}/phone'),
        office: false,
        maintenanceOnly: true,
        now: () => now,
      );
      extraStores.add(phone);
      await phone.importOfficeBundle(await store.publicBundle());
      final phoneBefore = tables(phone);
      final phoneReviewer = AgentProposalReviewer(
        store: phone,
        workspaceId: 'workspace',
        serviceDeviceId: phone.device,
      );
      await expectLater(phoneReviewer.pending(), throwsStateError);
      await expectLater(
        Future<Json>.sync(
          () =>
              phoneReviewer.decide(view, operationId: reviewKey, accept: true),
        ),
        throwsStateError,
      );
      expect(tables(phone), phoneBefore);
      expect(tables(), before);
    },
  );

  test(
    'other company cannot consume or decide a legitimate saved proposal',
    () async {
      final view = await propose();
      final other = await LabStore.open(
        Directory('${root.path}/other-company'),
        office: true,
        maintenanceOnly: true,
        now: () => now,
      );
      extraStores.add(other);
      await other.createCompany('Other synthetic company');
      final otherReviewer = AgentProposalReviewer(
        store: other,
        workspaceId: 'workspace',
        serviceDeviceId: other.device,
        proposals: service.proposals,
      );
      final before = tables(), otherBefore = tables(other);
      expect(await otherReviewer.pending(), isEmpty);
      await expectLater(
        otherReviewer.show(view.proposal.id),
        throwsA(
          isA<ProposalReviewFailure>().having(
            (e) => e.code,
            'code',
            'not_found',
          ),
        ),
      );
      await failure(
        () => otherReviewer.decide(view, operationId: reviewKey, accept: true),
        'scope_mismatch',
      );
      expect(tables(), before);
      expect(tables(other), otherBefore);
    },
  );

  test(
    'strict maintenance backup restores terminal review history without pending sidecars',
    () async {
      final original = await propose();
      final receipt = await reviewer.decide(
        original,
        operationId: reviewKey,
        accept: true,
      );
      final second = await propose(
        key: secondCreateKey,
        notes: 'Unreviewed synthetic suggestion.',
      );
      final identity = await OfficeIdentity.load(store);
      final backup = Directory('${root.path}/backup');
      await OfficeBackup.create(store, backup);
      await OfficeBackup.inspect(
        backup,
        requiredFormat: OfficeBackupFormat.maintenance,
      );
      expect(
        await Directory('${backup.path}/agent-proposals-v1').exists(),
        false,
      );
      final restoredPath = Directory('${root.path}/restored');
      await OfficeBackup.restore(
        backup,
        restoredPath,
        requiredFormat: OfficeBackupFormat.maintenance,
        expectedFingerprint: identity.fingerprint,
      );
      final restored = await LabStore.open(
        restoredPath,
        office: true,
        maintenanceOnly: true,
        now: () => now,
      );
      extraStores.add(restored);
      final restoredReviewer = AgentProposalReviewer(
        store: restored,
        workspaceId: 'workspace',
        serviceDeviceId: restored.device,
      );
      expect(restored.device, store.device);
      expect(await AgentProposalStore(restored.root).records(), isEmpty);
      expect(await restoredReviewer.pending(), isEmpty);
      expect(await restoredReviewer.history(), [receipt]);
      expect(
        (await restoredReviewer.history())
            .single['proposal']['result']['notes'],
        suggestion,
      );
      expect((await restored.fields(jobId: job))['notes'], [suggestion]);
      expect(restored.submissions, isEmpty);
      expect(restored.receipts, isEmpty);
      final restoredBefore = tables(restored);
      expect(
        await restoredReviewer.decide(
          original,
          operationId: reviewKey,
          accept: true,
        ),
        receipt,
      );
      expect(tables(restored), restoredBefore);
      await expectLater(
        restoredReviewer.show(second.proposal.id),
        throwsA(
          isA<ProposalReviewFailure>().having(
            (e) => e.code,
            'code',
            'not_found',
          ),
        ),
      );
    },
  );

  test(
    'restored rejection fences a recreated pending ID with the same grant and creation key',
    () async {
      final args = payload();
      final original = await propose();
      final receipt = await reviewer.decide(
        original,
        operationId: reviewKey,
        accept: false,
        reason: 'Keep the original human notes.',
      );
      await OfficeIdentity.load(store);
      final backup = Directory('${root.path}/rejected-backup');
      await OfficeBackup.create(store, backup);
      final restoredPath = Directory('${root.path}/rejected-restored');
      await OfficeBackup.restore(
        backup,
        restoredPath,
        requiredFormat: OfficeBackupFormat.maintenance,
      );
      final restored = await LabStore.open(
        restoredPath,
        office: true,
        maintenanceOnly: true,
        now: () => now,
      );
      extraStores.add(restored);
      final restoredService = AgentService(
        store: restored,
        workspaceId: 'workspace',
        serviceDeviceId: restored.device,
        grants: grants,
        now: () => now,
      );
      final restoredReviewer = AgentProposalReviewer(
        store: restored,
        workspaceId: 'workspace',
        serviceDeviceId: restored.device,
      );
      expect(await AgentProposalStore(restored.root).records(), isEmpty);
      final recreated = await restoredService.handle(request(args));
      expect(recreated['ok'], true, reason: canonical(recreated));
      final newId = recreated['result']['item']['proposal_id'] as String;
      expect(newId, isNot(original.proposal.id));
      expect(await restoredReviewer.pending(), isEmpty);
      final view = await restoredReviewer.show(newId);
      expect(view.receipt, receipt);
      final before = tables(restored);
      await failure(
        () => restoredReviewer.decide(
          view,
          operationId: secondReviewKey,
          accept: true,
        ),
        'already_decided',
      );
      expect(tables(restored), before);
      expect((await restored.fields(jobId: job))['notes'], [
        'Original human note',
      ]);
      expect(restored.submissions, isEmpty);
      expect(restored.receipts, isEmpty);
    },
  );

  test(
    'history rejects duplicate terminal proposal and duplicate creation keys even after rehashing',
    () async {
      final view = await propose();
      final receipt = await reviewer.decide(
        view,
        operationId: reviewKey,
        accept: false,
        reason: 'Synthetic rejection.',
      );
      Json duplicateReceipt(NotesProposal proposal) => rehashed({
        ...receipt,
        'operationId': secondReviewKey,
        'proposal': proposal.record,
        'requestHash': notesReviewRequestHash(
          proposal,
          operationId: secondReviewKey,
          accept: false,
          reason: receipt['reason'] as String,
          reviewedHash: receipt['reviewedDocumentHash'] as String,
        ),
      });
      for (final duplicate in [
        duplicateReceipt(view.proposal),
        duplicateReceipt(duplicateCreation(view.proposal)),
      ]) {
        expect(
          () => validateNotesReviewHistory([
            receipt,
            duplicate,
          ], companyId: store.catalog!['companyId'] as String),
          throwsA(
            isA<ProposalReviewFailure>().having(
              (e) => e.code,
              'code',
              'invalid_history',
            ),
          ),
        );
      }
    },
  );

  test(
    'rehashed malformed, foreign-authority and duplicate review events cannot inspect or restore',
    () async {
      final view = await propose();
      await reviewer.decide(view, operationId: reviewKey, accept: true);
      await OfficeIdentity.load(store);
      for (final scenario in [
        'extra-event-field',
        'malformed-nested-proposal',
        'different-office-authority',
        'duplicate-terminal-creation',
      ]) {
        final backup = Directory('${root.path}/backup-$scenario');
        await OfficeBackup.create(store, backup);
        final databaseFile = File('${backup.path}/workspace.sqlite');
        final database = sqlite3.open(databaseFile.path);
        try {
          final row = database.select(
            'SELECT id,payload FROM events WHERE kind=?',
            [notesReviewEvent],
          ).single;
          final receipt = jsonDecode(row['payload'] as String) as Json;
          if (scenario == 'extra-event-field') {
            receipt['approved'] = true;
          } else if (scenario == 'malformed-nested-proposal') {
            final proposal = receipt['proposal'] as Json;
            proposal['result']['requires_human_review'] = false;
            receipt['proposal'] = rehashed(proposal);
            // Deliberately match all cryptographic integrity hashes so the
            // production reader must reject the invalid nested semantics.
            receipt['requestHash'] = contentHash({
              'operationId': receipt['operationId'],
              'proposalHash': receipt['proposal']['hash'],
              'accept': true,
              'reason': '',
              'reviewedHash': receipt['reviewedDocumentHash'],
            });
          } else {
            var proposal = NotesProposal.fromRecord(
              receipt['proposal'] as Json,
            );
            if (scenario == 'different-office-authority') {
              final record = proposal.record;
              record['scope']['device_id'] =
                  '66666666-6666-4666-8666-666666666666';
              proposal = NotesProposal.fromRecord(rehashed(record));
              receipt['reviewerDevice'] = record['scope']['device_id'];
            } else {
              proposal = duplicateCreation(proposal);
              receipt['operationId'] = secondReviewKey;
            }
            receipt['proposal'] = proposal.record;
            receipt['requestHash'] = notesReviewRequestHash(
              proposal,
              operationId: receipt['operationId'] as String,
              accept: true,
              reason: '',
              reviewedHash: receipt['reviewedDocumentHash'] as String,
            );
          }
          if (scenario == 'duplicate-terminal-creation') {
            database.execute('INSERT INTO events(kind,payload) VALUES (?,?)', [
              notesReviewEvent,
              canonical(rehashed(receipt)),
            ]);
          } else {
            database.execute('UPDATE events SET payload=? WHERE id=?', [
              canonical(rehashed(receipt)),
              row['id'],
            ]);
          }
        } finally {
          database.close();
        }
        final manifestFile = File('${backup.path}/manifest.json');
        final manifest = jsonDecode(await manifestFile.readAsString()) as Json;
        final bytes = await databaseFile.readAsBytes();
        (manifest['files'] as Json)['workspace.sqlite'] = {
          'hash': digest(bytes),
          'size': bytes.length,
        };
        await manifestFile.writeAsString(canonical(manifest), flush: true);
        await expectLater(
          OfficeBackup.inspect(
            backup,
            requiredFormat: OfficeBackupFormat.maintenance,
          ),
          throwsA(anything),
          reason: scenario,
        );
        final destination = Directory('${root.path}/invalid-restore-$scenario');
        await expectLater(
          OfficeBackup.restore(
            backup,
            destination,
            requiredFormat: OfficeBackupFormat.maintenance,
          ),
          throwsA(anything),
          reason: scenario,
        );
        expect(await destination.exists(), false, reason: scenario);
        expect(await databaseFile.exists(), true, reason: scenario);
      }
    },
  );
}
