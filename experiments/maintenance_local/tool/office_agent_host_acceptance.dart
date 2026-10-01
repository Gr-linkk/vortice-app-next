import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:maintenance_local/agent_service/access_models.dart';
import 'package:maintenance_local/agent_service/agent_host.dart';
import 'package:maintenance_local/agent_service/proposal_store.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/model.dart';
import 'package:maintenance_local/procedure_library_store.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';

class _AcceptanceFailure implements Exception {
  const _AcceptanceFailure();
}

/// Opt-in acceptance of the normal host and unchanged Node CLI. No workspace,
/// socket or credential destination can be supplied: all are newly created
/// beneath this process's private temporary directory and removed on exit.
Future<void> main(List<String> args) async {
  Directory? root;
  LabStore? store;
  OfficeAgentHost? host;
  var initialized = false;
  var passed = false;
  var checks = 0;
  var cliCalls = 0;
  const privateDraft = 'SYNTHETIC_HOST_PRIVATE_DRAFT_LF005';

  void check(bool condition) {
    if (!condition) throw const _AcceptanceFailure();
    checks++;
  }

  String sqlFingerprint(LabStore office) => contentHash({
    for (final row in office.db.select(
      "SELECT name FROM sqlite_schema WHERE type='table' "
      "AND name NOT LIKE 'sqlite_%' ORDER BY name",
    ))
      row['name'] as String: office.db
          .select('SELECT * FROM "${row['name']}" ORDER BY rowid')
          .map((value) => Map<String, dynamic>.from(value))
          .toList(),
  });

  try {
    // Validate opt-in and the explicit native library before any mutation or
    // native initialization. Existing workspace paths are never accepted.
    check(
      Platform.isLinux &&
          args.length == 3 &&
          args[0] == '--synthetic-fixture' &&
          args[1] == '--native-library',
    );
    final library = File(args[2]);
    check(
      library.path == library.absolute.path &&
          FileSystemEntity.typeSync(library.path, followLinks: false) ==
              FileSystemEntityType.file,
    );
    final cli = File.fromUri(
      Platform.script.resolve('../../../tools/local-agent-cli/cli.mjs'),
    );
    check(
      FileSystemEntity.typeSync(cli.path, followLinks: false) ==
          FileSystemEntityType.file,
    );
    final node = await Process.run('/usr/bin/node', ['--version']);
    final major = int.tryParse(
      (node.stdout as String).trim().replaceFirst('v', '').split('.').first,
    );
    check(node.exitCode == 0 && major != null && major >= 22);
    root = await Directory.systemTemp.createTemp('vortice-host-check-');
    check(
      root.resolveSymbolicLinksSync() == root.absolute.path &&
          FileSystemEntity.typeSync(root.path, followLinks: false) ==
              FileSystemEntityType.directory,
    );
    // Dart's temporary-directory mode follows the current umask. Tighten only
    // this newly created directory; callers cannot supply an existing path.
    final secured = await Process.run('/usr/bin/chmod', [
      '700',
      '--',
      root.path,
    ]);
    check(secured.exitCode == 0 && (root.statSync().mode & 0xfff) == 0x1c0);
    await RustLib.init(externalLibrary: ExternalLibrary.open(library.path));
    initialized = true;
    store = await LabStore.open(
      Directory('${root.path}/office'),
      office: true,
      maintenanceOnly: true,
    );
    await store.createCompany('Synthetic host acceptance company');
    final publication = await store.publishChecklist(
      title: 'Synthetic host inspection',
      items: [
        {'id': 'guard', 'label': 'Inspect guard', 'input_type': 'check'},
      ],
    );
    final equipment = <Json>[];
    final jobs = <Json>[];
    for (var i = 1; i <= 2; i++) {
      final asset = await store.addEquipment(
        name: 'Synthetic host equipment $i',
        meterUnit: 'none',
      );
      equipment.add(asset);
      jobs.add(
        await store.prepareWork(
          equipmentId: asset['id'] as String,
          templateId: publication['id'] as String,
          title: 'Synthetic host job $i',
        ),
      );
    }
    final job = jobs.first['id'] as String;
    final selectedEquipment = equipment.first['id'] as String;
    final copied = await store.copyProcedureDraft(
      publication['id'] as String,
      operationId: 'host-private-copy',
    );
    await store.saveProcedureDraft(
      draftId: copied['id'] as String,
      expectedRevision: 1,
      title: privateDraft,
      items: [
        {
          ...Map<String, dynamic>.from((copied['items'] as List).single as Map),
          'label': '',
        },
      ],
      operationId: 'host-private-save',
    );
    await store.update({
      'answer:guard': {'result': 'pass', 'value': ''},
      'notes': 'Synthetic approved inspection observation',
    }, jobId: job);
    await store.attach([1, 2, 3, 4], jobId: job);
    final submission = await store.submit(jobId: job);
    await store.decide(submission['id'] as String, approve: true);
    host = OfficeAgentHost(
      store: store,
      runtimeDirectory: Directory('${root.path}/r'),
    );
    check(host.snapshot.enabled == false && host.snapshot.socketPath == null);
    await host.initialize();
    check(
      host.snapshot.state == OfficeAgentHostState.disabled &&
          !host.snapshot.enabled &&
          host.grants.isEmpty,
    );
    await host.enable();
    check(
      host.snapshot.state == OfficeAgentHostState.listening &&
          host.snapshot.enabled &&
          host.snapshot.socketPath != null,
    );
    final socket = host.snapshot.socketPath!;
    final scope = host.scope!;
    final expiry = DateTime.now().toUtc().add(const Duration(hours: 1));
    final readonly = await host.issue(
      AgentGrantRequest(
        label: 'Synthetic read-only agent',
        expiresAt: expiry,
        equipmentIds: {selectedEquipment},
        jobIds: {job},
      ),
    );
    final writer = await host.issue(
      AgentGrantRequest(
        label: 'Synthetic notes agent',
        expiresAt: expiry,
        equipmentIds: {selectedEquipment},
        jobIds: {job},
        allowNotes: true,
      ),
    );
    var mismatchedSelectionRefused = false;
    try {
      await host.issue(
        AgentGrantRequest(
          label: 'Synthetic invalid scope',
          expiresAt: expiry,
          equipmentIds: {selectedEquipment},
          jobIds: {jobs.last['id'] as String},
        ),
      );
    } catch (_) {
      mismatchedSelectionRefused = true;
    }
    check(mismatchedSelectionRefused && host.grants.length == 2);

    Future<Json> call(
      String token,
      List<String> command, {
      Json? input,
      int? expectedExit,
    }) async {
      cliCalls++;
      final process = await Process.start(
        '/usr/bin/node',
        [
          cli.path,
          ...command,
          '--socket',
          socket,
          '--workspace',
          scope.workspaceId,
          '--company',
          scope.companyId,
          '--device',
          scope.deviceId,
        ],
        environment: {'VORTICE_LOCAL_AGENT_TOKEN': token},
        includeParentEnvironment: false,
      );
      final output = process.stdout.transform(utf8.decoder).join();
      final errors = process.stderr.transform(utf8.decoder).join();
      if (input != null) process.stdin.write(canonical(input));
      await process.stdin.close();
      int resultCode;
      try {
        resultCode = await process.exitCode.timeout(
          const Duration(seconds: 10),
        );
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
        await process.exitCode;
        throw const _AcceptanceFailure();
      }
      final encoded = await output;
      check(await errors == '');
      check(encoded.length <= 1024 * 1024);
      check(
        !encoded.contains(readonly.token) &&
            !encoded.contains(writer.token) &&
            !encoded.contains(privateDraft) &&
            !encoded.contains(copied['id'] as String),
      );
      if (expectedExit != null) check(resultCode == expectedExit);
      final response = jsonDecode(encoded) as Json;
      check((response['ok'] == true) == (resultCode == 0));
      return response;
    }

    Json success(Json response) {
      check(response['ok'] == true);
      check(response['meta']['synced']['verified'] == false);
      return response['result'] as Json;
    }

    void denied(Json response, String code) {
      check(response['ok'] == false && response['error']['code'] == code);
    }

    final caps = success(await call(readonly.token, ['capabilities']));
    check(!(caps['commands'] as List).contains('proposals.create'));
    final status = success(await call(writer.token, ['workspace', 'status']));
    check(status['proposals_backup_included'] == false);
    check(status['local_work_count'] == 1);
    final work = success(await call(writer.token, ['work', 'list']));
    check(work['count'] == 1 && work['items'][0]['job_id'] == job);
    final beforeWork = success(
      await call(writer.token, ['work', 'show', '--id', job]),
    );
    final beforeHistory = success(
      await call(writer.token, ['history', 'list']),
    );
    check(beforeHistory['count'] == 1);
    final beforeSql = sqlFingerprint(store);
    final beforeDocument = digest(store.documentFor(job)!);
    final payload = <String, dynamic>{
      'type': 'inspection.notes',
      'job_id': job,
      'expected_document_hash': beforeWork['item']['draft']['document_hash'],
      'notes': 'Synthetic CLI suggestion retained for human review only.',
    };
    const operation = '22222222-2222-4222-8222-222222222222';
    const proposalCommand = [
      'proposals',
      'create',
      '--operation',
      operation,
      '--input',
      '-',
    ];
    denied(
      await call(
        readonly.token,
        proposalCommand,
        input: payload,
        expectedExit: 1,
      ),
      'permission_denied',
    );
    final created = success(
      await call(
        writer.token,
        proposalCommand,
        input: payload,
        expectedExit: 0,
      ),
    );
    check(
      created['item']['status'] == 'pending_human_review' &&
          created['item']['applied'] == false,
    );
    final replay = success(
      await call(
        writer.token,
        proposalCommand,
        input: payload,
        expectedExit: 0,
      ),
    );
    check(canonical(replay) == canonical(created));
    check(
      success(await call(writer.token, ['proposals', 'list']))['count'] == 1,
    );
    check((await AgentProposalStore(store.root).records()).length == 1);
    check(sqlFingerprint(store) == beforeSql);
    check(digest(store.documentFor(job)!) == beforeDocument);
    check(
      canonical(
            success(await call(writer.token, ['work', 'show', '--id', job])),
          ) ==
          canonical(beforeWork),
    );
    check(
      canonical(success(await call(writer.token, ['history', 'list']))) ==
          canonical(beforeHistory),
    );
    await host.revoke(writer.summary.grant.id);
    // The normal host immediately denies a revoked token. Its persisted grant
    // provider also retains revocation; the CLI never opens private state.
    denied(
      await call(writer.token, ['work', 'list'], expectedExit: 1),
      'grant_revoked',
    );
    success(await call(readonly.token, ['work', 'list'], expectedExit: 0));
    await host.disable();
    check(
      host.snapshot.state == OfficeAgentHostState.disabled &&
          !host.snapshot.enabled &&
          host.snapshot.socketPath == null,
    );
    denied(
      await call(readonly.token, ['work', 'list'], expectedExit: 1),
      'service_unavailable',
    );
    check(sqlFingerprint(store) == beforeSql);
    passed = true;
  } catch (_) {
    // Never print native/process errors, request bodies, paths or credentials.
    passed = false;
  } finally {
    for (final cleanup in <FutureOr<void> Function()>[
      () async => host?.close(),
      () async => store?.close(),
      () {
        if (initialized) RustLib.dispose();
      },
      () async {
        if (root != null) await root.delete(recursive: true);
      },
    ]) {
      try {
        await cleanup();
      } catch (_) {
        passed = false;
      }
    }
  }
  stdout.writeln(
    canonical({
      'synthetic_fixture': true,
      'protocol_version': 1,
      'ok': passed,
      'checks': checks,
      'cli_calls': cliCalls,
      'pending_proposals': passed ? 1 : 0,
      'temporary_workspace_removed': root == null || !root.existsSync(),
    }),
  );
  if (!passed) exitCode = 1;
}
