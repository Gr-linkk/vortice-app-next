import 'dart:convert';
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/agent_service/agent_service.dart';
import 'package:maintenance_local/agent_service/grants.dart';
import 'package:maintenance_local/agent_service/proposal_review.dart';
import 'package:maintenance_local/agent_service/unix_transport.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/model.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';

class _SyntheticGrants implements GrantProvider {
  _SyntheticGrants(this.grant);
  AgentGrant grant;
  @override
  Future<AgentGrant?> resolve(String token) async =>
      token == 'synthetic-cli-human-review-token' ? grant : null;
}

void main() {
  setUpAll(
    () => RustLib.init(
      externalLibrary: ExternalLibrary.open(
        Platform.environment['MAINTENANCE_NATIVE_LIBRARY']!,
      ),
    ),
  );

  test(
    'actual CLI proposes over Unix transport; human applies; reads and retries stay scoped',
    () async {
      // The short private socket path is separate from the native fixture root.
      final root = await Directory.systemTemp.createTemp('agent-review-cli-');
      final runtime = await Directory('/tmp').createTemp('vrc-');
      await Process.run('/usr/bin/chmod', ['700', runtime.path]);
      final store = await LabStore.open(
        Directory('${root.path}/office'),
        office: true,
        maintenanceOnly: true,
      );
      UnixAgentTransport? transport;
      try {
        await store.createCompany('Synthetic CLI human review company');
        final equipment = await store.addEquipment(
          name: 'Synthetic CLI generator',
          meterUnit: 'none',
        );
        final procedure = await store.publishChecklist(
          title: 'Synthetic CLI procedure',
          items: [
            {
              'id': 'guard',
              'label': 'Inspect synthetic guard',
              'input_type': 'check',
            },
          ],
        );
        final work = await store.prepareWork(
          equipmentId: equipment['id'] as String,
          templateId: procedure['id'] as String,
          title: 'Synthetic CLI inspection',
        );
        final job = work['id'] as String;
        await store.update({'notes': 'Human original notes'}, jobId: job);
        final clock = DateTime.utc(2026, 10, 1, 16);
        AgentGrant grant({bool revoked = false}) => AgentGrant(
          id: 'synthetic-cli-grant',
          actorId: 'synthetic-cli-agent',
          workspaceId: 'synthetic-cli-workspace',
          companyId: store.catalog!['companyId'] as String,
          deviceId: store.device,
          expiresAt: clock.add(const Duration(hours: 1)),
          revoked: revoked,
          commands: AgentService.commands,
          jobIds: {job},
          equipmentIds: {equipment['id'] as String},
        );
        final grants = _SyntheticGrants(grant());
        final service = AgentService(
          store: store,
          workspaceId: 'synthetic-cli-workspace',
          serviceDeviceId: store.device,
          grants: grants,
          now: () => clock,
        );
        transport = await UnixAgentTransport.start(
          socketPath: '${runtime.path}/agent.sock',
          handler: service.handle,
        );
        final cliPath = File(
          '${Directory.current.parent.parent.path}/tools/local-agent-cli/cli.mjs',
        ).absolute.path;
        Future<Json> cli(
          List<String> command, {
          Json? input,
          int exit = 0,
        }) async {
          final process = await Process.start(
            'node',
            [
              cliPath,
              ...command,
              '--socket',
              transport!.socketPath,
              '--workspace',
              'synthetic-cli-workspace',
              '--company',
              store.catalog!['companyId'] as String,
              '--device',
              store.device,
            ],
            environment: {
              'VORTICE_LOCAL_AGENT_TOKEN': 'synthetic-cli-human-review-token',
            },
          );
          final stdout = process.stdout.transform(utf8.decoder).join();
          final stderr = process.stderr.transform(utf8.decoder).join();
          if (input != null) process.stdin.write(canonical(input));
          await process.stdin.close();
          final status = await process.exitCode.timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              process.kill(ProcessSignal.sigkill);
              throw StateError('Synthetic CLI subprocess did not finish.');
            },
          );
          expect(status, exit);
          expect(await stderr, isEmpty);
          final text = await stdout;
          expect(text, isNot(contains('synthetic-cli-human-review-token')));
          return jsonDecode(text) as Json;
        }

        final before = await cli(['work', 'show', '--id', job]);
        final beforeHash =
            before['result']['item']['draft']['document_hash'] as String;
        final proposal = {
          'type': 'inspection.notes',
          'job_id': job,
          'expected_document_hash': beforeHash,
          'notes': 'Agent suggested replacement notes',
        };
        const createOperation = '11111111-1111-4111-8111-111111111111';
        final created = await cli([
          'proposals',
          'create',
          '--input',
          '-',
          '--operation',
          createOperation,
        ], input: proposal);
        expect(created['result']['item']['applied'], false);
        expect((await store.fields(jobId: job))['notes'], [
          'Human original notes',
        ]);

        final reviewer = AgentProposalReviewer(
          store: store,
          workspaceId: 'synthetic-cli-workspace',
          serviceDeviceId: store.device,
        );
        final view = await reviewer.show(
          created['result']['item']['proposal_id'] as String,
        );
        final receipt = await reviewer.decide(
          view,
          operationId: '22222222-2222-4222-8222-222222222222',
          accept: true,
        );
        expect(receipt['decision'], 'applied');
        expect((await store.fields(jobId: job))['notes'], [
          'Agent suggested replacement notes',
        ]);
        expect(store.submissions, isEmpty);
        expect(store.receipts, isEmpty);
        expect(await reviewer.pending(), isEmpty);

        final after = await cli(['work', 'show', '--id', job]);
        expect(
          after['result']['item']['draft']['document_hash'],
          receipt['afterDocumentHash'],
        );
        expect(
          after['result']['item']['draft']['document_hash'],
          isNot(beforeHash),
        );
        final retry = await cli([
          'proposals',
          'create',
          '--input',
          '-',
          '--operation',
          createOperation,
        ], input: proposal);
        expect(canonical(retry['result']), canonical(created['result']));
        // The immutable v1 pending receipt is intentionally not decision proof.
        expect(retry['result']['item']['status'], 'pending_human_review');
        final invalid = await cli([
          'proposals',
          'apply',
          '--id',
          view.proposal.id,
        ], exit: 2);
        expect(invalid['error']['code'], 'invalid_input');
        grants.grant = grant(revoked: true);
        final denied = await cli(['work', 'show', '--id', job], exit: 1);
        expect(denied['error']['code'], 'grant_revoked');
        expect(await reviewer.history(), [receipt]);
      } finally {
        await transport?.close();
        await store.close();
        await runtime.delete(recursive: true);
        await root.delete(recursive: true);
      }
    },
  );
}
