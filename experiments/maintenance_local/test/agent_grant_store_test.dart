import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/agent_service/access_models.dart';
import 'package:maintenance_local/agent_service/access_scope.dart';
import 'package:maintenance_local/agent_service/grant_store.dart';

const _scope = AgentAccessScope(
  workspaceId: 'ws-synthetic',
  companyId: 'company-synthetic',
  deviceId: 'office-synthetic',
);

void main() {
  late Directory workspace;
  late DateTime now;
  OfficeAgentGrantStore? store;
  File state() => File('${workspace.path}/agent-access-v1/state.json');
  Directory sidecar() => Directory('${workspace.path}/agent-access-v1');
  Future<OfficeAgentGrantStore> open({AgentAccessScope scope = _scope}) async =>
      OfficeAgentGrantStore.open(
        workspaceRoot: workspace,
        scope: scope,
        now: () => now,
      );
  AgentGrantRequest request({
    Set<String>? jobs,
    bool notes = false,
    DateTime? expiry,
    String label = 'Synthetic reader',
  }) => AgentGrantRequest(
    label: label,
    expiresAt: expiry ?? now.add(const Duration(hours: 1)),
    equipmentIds: {'equipment-b', 'equipment-a'},
    jobIds: jobs ?? {'job-a'},
    allowNotes: notes,
  );
  Future<void> chmod(String path, String mode) async {
    final result = await Process.run('/usr/bin/chmod', [mode, '--', path]);
    expect(result.exitCode, 0);
  }

  Future<void> rewrite(Map<String, dynamic> value) =>
      state().writeAsString(jsonEncode(value));

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('agent-grant-synthetic-');
    now = DateTime.utc(2026, 10, 1, 12);
    store = null;
  });
  tearDown(() async {
    await store?.close();
    await workspace.delete(recursive: true);
  });

  test(
    'fresh config is disabled, private and contains no credential',
    () async {
      store = await open();
      expect(await store!.enabled(), false);
      expect(await store!.list(), isEmpty);
      expect(await store!.resolve('x' * 43), isNull);
      expect(sidecar().statSync().mode & 0xfff, 0x1c0);
      expect(state().statSync().mode & 0xfff, 0x180);
      expect(
        File('${sidecar().path}/writer.lock').statSync().mode & 0xfff,
        0x180,
      );
      expect(jsonDecode(await state().readAsString()), {
        'format': 'agent-access-v1',
        'scope': _scope.toJson(),
        'enabled': false,
        'grants': [],
      });
      await expectLater(store!.issue(request()), throwsStateError);
    },
  );

  test(
    'token has 256 random bits, digest only and immutable pinned scope',
    () async {
      store = await open();
      await store!.setEnabled(true);
      final jobs = <String>{};
      final equipment = {'equipment-a'};
      final req = AgentGrantRequest(
        label: '  Synthetic notes  ',
        expiresAt: now.add(const Duration(days: 7)),
        equipmentIds: equipment,
        jobIds: jobs,
        allowNotes: true,
      );
      jobs.add('future-job');
      equipment.add('future-equipment');
      final issued = await store!.issue(req);
      expect(base64Url.decode('${issued.token}=').length, 32);
      final persisted = await state().readAsString();
      expect(persisted, isNot(contains(issued.token)));
      expect(
        persisted,
        contains(sha256.convert(utf8.encode(issued.token)).toString()),
      );
      final grant = (await store!.resolve(issued.token))!;
      expect(grant.workspaceId, _scope.workspaceId);
      expect(grant.companyId, _scope.companyId);
      expect(grant.deviceId, _scope.deviceId);
      expect(grant.equipmentIds, {'equipment-a'});
      expect(grant.jobIds, isEmpty);
      expect(grant.commands, contains('proposals.create'));
      expect(grant.commands, isNot(contains('proposals.apply')));
      expect(() => grant.equipmentIds!.add('new'), throwsUnsupportedError);
      expect(() => grant.jobIds!.add('new'), throwsUnsupportedError);
      expect(() => grant.commands.add('new'), throwsUnsupportedError);
      expect(() => (store!.list()), returnsNormally);
      expect(issued.summary.label, 'Synthetic notes');
      expect(await store!.resolve('${issued.token.substring(1)}x'), isNull);
    },
  );

  test('enable, revocation and explicit zero jobs survive restart', () async {
    store = await open();
    await store!.setEnabled(true);
    final issued = await store!.issue(request(jobs: {}));
    final original = issued.summary.grant;
    await store!.close();
    store = await open();
    expect(await store!.enabled(), true);
    expect((await store!.resolve(issued.token))!.jobIds, isEmpty);
    now = now.add(const Duration(minutes: 3));
    await store!.revoke(original.id);
    await store!.revoke(original.id);
    expect((await store!.resolve(issued.token))!.revoked, true);
    expect(original.revoked, false);
    await store!.close();
    store = await open();
    final revoked = (await store!.list()).single;
    expect(revoked.revokedAt, now);
    expect(revoked.grant.revoked, true);
    await store!.setEnabled(false);
    expect(await store!.resolve(issued.token), isNull);
    await store!.close();
    store = await open();
    expect(await store!.enabled(), false);
    expect((await store!.list()).single.grant.revoked, true);
  });

  test(
    'expired and revoked grants preserve v1 authorization evidence',
    () async {
      store = await open();
      await store!.setEnabled(true);
      final issued = await store!.issue(request());
      now = issued.summary.grant.expiresAt;
      final expired = (await store!.resolve(issued.token))!;
      expect(expired.expiresAt.isAfter(now), false);
      expect(expired.revoked, false);
      await store!.revoke(expired.id);
      expect((await store!.resolve(issued.token))!.revoked, true);
    },
  );

  test(
    'concurrent issuance is serialized with unique identities and tokens',
    () async {
      store = await open();
      await store!.setEnabled(true);
      final issued = await Future.wait(
        List.generate(24, (_) => store!.issue(request())),
      );
      expect(issued.map((g) => g.summary.grant.id).toSet(), hasLength(24));
      expect(issued.map((g) => g.summary.grant.actorId).toSet(), hasLength(24));
      expect(issued.map((g) => g.token).toSet(), hasLength(24));
      expect(await store!.list(), hasLength(24));
      for (final grant in issued) {
        final resolved = (await store!.resolve(grant.token))!;
        expect(resolved.commands, isNot(contains('proposals.create')));
        expect(resolved.jobIds, {'job-a'});
      }
    },
  );

  test(
    'requests reject invalid expiry and allowlist without altering state',
    () async {
      store = await open();
      await store!.setEnabled(true);
      final before = await state().readAsBytes();
      for (final req in [
        request(expiry: now),
        request(expiry: now.add(const Duration(days: 7, microseconds: 1))),
        request(label: '\n'),
        request(label: 'x' * 81),
        request(jobs: {'../../bad'}),
        AgentGrantRequest(
          label: 'Empty equipment',
          expiresAt: now.add(const Duration(hours: 1)),
          equipmentIds: {},
          jobIds: {},
        ),
      ]) {
        await expectLater(store!.issue(req), throwsArgumentError);
      }
      expect(await state().readAsBytes(), before);
      await store!.revoke('grant-${'0' * 32}');
      expect(await store!.list(), isEmpty);
    },
  );

  test(
    'same-process second writer refuses and later close releases lease',
    () async {
      store = await open();
      final before = await state().readAsBytes();
      await expectLater(open(), throwsStateError);
      expect(await state().readAsBytes(), before);
      await store!.close();
      await store!.close();
      expect(await store!.resolve('x' * 43), isNull);
      await expectLater(store!.enabled(), throwsStateError);
      store = await open();
      expect(await store!.enabled(), false);
    },
  );

  test('foreign canonical scope is refused and preserved', () async {
    store = await open();
    await store!.close();
    final before = await state().readAsBytes();
    await expectLater(
      open(
        scope: const AgentAccessScope(
          workspaceId: 'ws-foreign',
          companyId: 'company-synthetic',
          deviceId: 'office-synthetic',
        ),
      ),
      throwsStateError,
    );
    expect(await state().readAsBytes(), before);
    store = await open();
  });

  test(
    'fresh reads deny corruption and never replace damaged authority',
    () async {
      store = await open();
      await store!.setEnabled(true);
      final issued = await store!.issue(request());
      await state().writeAsString('{broken');
      final before = await state().readAsBytes();
      expect(await store!.resolve(issued.token), isNull);
      await expectLater(store!.setEnabled(false), throwsStateError);
      await expectLater(
        store!.revoke(issued.summary.grant.id),
        throwsStateError,
      );
      expect(await state().readAsBytes(), before);
      await store!.close();
      await expectLater(open(), throwsStateError);
      expect(await state().readAsBytes(), before);
    },
  );

  test(
    'duplicate JSON keys, broad scope and bad records fail closed',
    () async {
      store = await open();
      await store!.setEnabled(true);
      final issued = await store!.issue(request());
      final original = await state().readAsString();
      final cases = <String>[
        original.replaceFirst(
          '"enabled":true',
          '"enabled":true,"enabled":true',
        ),
        ' $original',
      ];
      for (final mutation in <void Function(Map<String, dynamic>)>[
        (v) => v['scope']['workspace_id'] = 'ws-foreign',
        (v) => v['grants'][0]['job_ids'] = null,
        (v) => v['grants'][0]['equipment_ids'] = [],
        (v) => v['grants'][0]['token_sha256'] = issued.token,
        (v) => v['grants'][0]['expires_at'] = now
            .add(const Duration(days: 8))
            .toIso8601String(),
        (v) => v['grants'][0]['extra'] = 'unrecognized',
        (v) => v['grants'].add(Map<String, dynamic>.of(v['grants'][0])),
        (v) => v['grants'][0]['job_ids'] = ['job-a', 'job-a'],
        (v) => v['grants'][0]['allow_notes'] = 'true',
      ]) {
        final value = jsonDecode(original) as Map<String, dynamic>;
        mutation(value);
        cases.add(jsonEncode(value));
      }
      for (final text in cases) {
        await state().writeAsString(text);
        expect(await store!.resolve(issued.token), isNull);
        await expectLater(store!.setEnabled(false), throwsStateError);
        expect(await state().readAsString(), text);
      }
    },
  );

  test('unsafe modes are refused without chmod or state repair', () async {
    store = await open();
    await store!.setEnabled(true);
    final issued = await store!.issue(request());
    final bytes = await state().readAsBytes();
    for (final entry in [
      state().path,
      sidecar().path,
      '${sidecar().path}/writer.lock',
    ]) {
      await chmod(entry, entry == sidecar().path ? '755' : '644');
      expect(await store!.resolve(issued.token), isNull);
      await expectLater(store!.setEnabled(false), throwsStateError);
      expect(await state().readAsBytes(), bytes);
      expect(
        File(entry).statSync().mode & 0xfff,
        entry == sidecar().path ? 0x1ed : 0x1a4,
      );
      await chmod(entry, entry == sidecar().path ? '700' : '600');
    }
    expect((await store!.resolve(issued.token))!.id, issued.summary.grant.id);
  });

  test(
    'symlink and hardlink state are refused without touching their target',
    () async {
      store = await open();
      await store!.setEnabled(true);
      final issued = await store!.issue(request());
      final outside = File('${workspace.path}/outside.json');
      await outside.writeAsBytes(await state().readAsBytes());
      await chmod(outside.path, '600');
      final target = await outside.readAsBytes();
      await state().delete();
      await Link(state().path).create(outside.path);
      expect(await store!.resolve(issued.token), isNull);
      await expectLater(store!.setEnabled(false), throwsStateError);
      expect(await outside.readAsBytes(), target);
      expect(Link(state().path).existsSync(), true);
      await Link(state().path).delete();
      final linked = await Process.run('/usr/bin/ln', [
        '--',
        outside.path,
        state().path,
      ]);
      expect(linked.exitCode, 0);
      expect(await store!.resolve(issued.token), isNull);
      await expectLater(store!.setEnabled(false), throwsStateError);
      expect(await outside.readAsBytes(), target);
    },
  );

  test(
    'sidecar symlink and partial pre-existing state are never initialized',
    () async {
      final other = await Directory('${workspace.path}/other').create();
      await chmod(other.path, '700');
      await Link(sidecar().path).create(other.path);
      await expectLater(open(), throwsStateError);
      expect(other.listSync(), isEmpty);
      await Link(sidecar().path).delete();
      await sidecar().create();
      await chmod(sidecar().path, '700');
      await expectLater(open(), throwsStateError);
      expect(sidecar().listSync(), isEmpty);
    },
  );

  test('oversized state and inventory are bounded and preserved', () async {
    store = await open();
    await state().writeAsBytes(List<int>.filled(4 * 1024 * 1024 + 1, 32));
    await expectLater(store!.enabled(), throwsStateError);
    expect(state().lengthSync(), 4 * 1024 * 1024 + 1);
    await rewrite({
      'format': 'agent-access-v1',
      'scope': _scope.toJson(),
      'enabled': false,
      'grants': [],
    });
    for (var i = 0; i < 63; i++) {
      final pending = File(
        '${sidecar().path}/.pending-${i.toRadixString(16).padLeft(32, '0')}',
      );
      await pending.writeAsString('');
      await chmod(pending.path, '600');
    }
    await expectLater(store!.enabled(), throwsStateError);
    expect(sidecar().listSync(), hasLength(65));
  });

  test('a replaced writer inode denies requests and writes', () async {
    store = await open();
    await store!.setEnabled(true);
    final issued = await store!.issue(request());
    final lock = File('${sidecar().path}/writer.lock');
    await lock.rename('${workspace.path}/old-lock');
    await lock.writeAsString('');
    await chmod(lock.path, '600');
    final before = await state().readAsBytes();
    expect(await store!.resolve(issued.token), isNull);
    await expectLater(store!.setEnabled(false), throwsStateError);
    expect(await state().readAsBytes(), before);
  });

  test(
    'subprocess lease rejects another process and releases after SIGKILL',
    () async {
      final dart = _dartExecutable();
      final childArgs = [
        '--packages=${Directory.current.path}/.dart_tool/package_config.json',
        '${Directory.current.path}/test/agent_grant_store_process_child.dart',
        workspace.path,
      ];
      final child = await Process.start(dart, [...childArgs, 'hold']);
      final errors = child.stderr.transform(utf8.decoder).join();
      addTearDown(() async {
        child.kill(ProcessSignal.sigkill);
        await child.exitCode;
      });
      final first = await child.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 30));
      expect(first, 'ready', reason: first == 'ready' ? null : await errors);
      await expectLater(open(), throwsStateError);
      final refused = await Process.run(dart, [...childArgs, 'check']);
      expect(refused.exitCode, 3, reason: refused.stderr.toString());
      expect(refused.stdout.toString().trim(), 'refused');
      expect(child.kill(ProcessSignal.sigkill), true);
      await child.exitCode;
      store = await open();
      expect(await store!.enabled(), false);
      await store!.close();
      final reopened = await Process.run(dart, [...childArgs, 'check']);
      expect(reopened.exitCode, 0, reason: reopened.stderr.toString());
      expect(reopened.stdout.toString().trim(), 'opened');
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );
}

String _dartExecutable() {
  var ancestor = File(Platform.resolvedExecutable).parent;
  while (true) {
    for (final relative in [
      'dart',
      'dart-sdk/bin/dart',
      'bin/cache/dart-sdk/bin/dart',
    ]) {
      final file = File('${ancestor.path}/$relative');
      if (file.existsSync()) return file.path;
    }
    final parent = ancestor.parent;
    if (parent.path == ancestor.path) {
      throw StateError('Dart SDK was not found.');
    }
    ancestor = parent;
  }
}
