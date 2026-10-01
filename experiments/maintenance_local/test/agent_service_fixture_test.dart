import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/model.dart';

const _dart =
    '/home/garrett/Documents/Codex/2026-09-30/task-8/maintenance-progress/work/offline-bin/dart';
void main() {
  late Directory parent;
  final library = Platform.environment['MAINTENANCE_NATIVE_LIBRARY']!;
  setUp(() async {
    parent = await Directory('/tmp').createTemp('agent-fixture-');
    await Process.run('/usr/bin/chmod', ['700', '--', parent.path]);
  });
  tearDown(() async {
    await parent.delete(recursive: true);
  });
  List<String> launchArgs(String workspace, {bool explicit = true}) => [
    'run',
    'tool/local_agent_service_fixture.dart',
    if (explicit) '--synthetic-fixture',
    '--workspace',
    workspace,
    '--socket',
    '${parent.path}/service.sock',
    '--ready',
    '${parent.path}/ready.json',
    '--native-library',
    library,
  ];
  test(
    'fixture refuses implicit mode and every preexisting workspace before mutation',
    () async {
      final workspace = Directory('${parent.path}/workspace');
      final implicit = await Process.run(
        _dart,
        launchArgs(workspace.path, explicit: false),
      );
      expect(implicit.exitCode, 1);
      expect(await workspace.exists(), false);
      await workspace.create();
      final empty = await Process.run(_dart, launchArgs(workspace.path));
      expect(empty.exitCode, 1);
      expect(await workspace.list().isEmpty, true);
      final retained = File('${workspace.path}/retained.txt');
      await retained.writeAsString('Retain me');
      final nonempty = await Process.run(_dart, launchArgs(workspace.path));
      expect(nonempty.exitCode, 1);
      expect(await retained.readAsString(), 'Retain me');
      expect(await File('${workspace.path}/workspace.sqlite').exists(), false);
      expect(await File('${parent.path}/ready.json').exists(), false);
    },
  );
  test(
    'actual guarded launcher exposes only synthetic metadata and cleanly stops',
    () async {
      final workspace = '${parent.path}/new-workspace';
      final ready = File('${parent.path}/ready.json');
      final process = await Process.start(_dart, launchArgs(workspace));
      final stderr = process.stderr.transform(utf8.decoder).join();
      final stdout = process.stdout.transform(utf8.decoder).join();
      var exited = false;
      unawaited(
        process.exitCode.then((_) {
          exited = true;
        }),
      );
      try {
        final deadline = DateTime.now().add(const Duration(seconds: 30));
        while (!ready.existsSync() &&
            !exited &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
        expect(exited, false, reason: exited ? await stderr : null);
        expect(ready.existsSync(), true);
        final metadata = jsonDecode(await ready.readAsString()) as Json;
        expect(metadata['synthetic_fixture'], true);
        expect(metadata['protocol_version'], 1);
        expect(metadata['job_ids'], hasLength(2));
        expect(metadata['equipment_ids'], hasLength(2));
        expect(
          metadata.keys,
          unorderedEquals([
            'synthetic_fixture',
            'protocol_version',
            'workspace_id',
            'company_id',
            'device_id',
            'equipment_ids',
            'job_ids',
            'procedure_ids',
          ]),
        );
        expect(canonical(metadata), isNot(contains('token')));
        expect(canonical(metadata), isNot(contains(parent.path)));
        final socket = await Socket.connect(
          InternetAddress(
            '${parent.path}/service.sock',
            type: InternetAddressType.unix,
          ),
          0,
        );
        final lines = StreamIterator(
          socket
              .cast<List<int>>()
              .transform(utf8.decoder)
              .transform(const LineSplitter()),
        );
        final scope = {
          for (final key in ['workspace_id', 'company_id', 'device_id'])
            key: metadata[key],
        };
        socket.writeln(
          canonical({
            'protocol_version': 1,
            'request_id': 'fixture-read',
            'scope': scope,
            'credential': {'token': 'synthetic-agent-token'},
            'command': 'work.list',
            'args': {},
          }),
        );
        await socket.flush();
        expect(await lines.moveNext(), true);
        final response = jsonDecode(lines.current) as Json;
        expect(response['ok'], true);
        expect(response['scope'], scope);
        expect(response['result']['count'], 2);
        expect(response['meta']['synced']['verified'], false);
        socket.destroy();
        await lines.cancel();
        process.kill(ProcessSignal.sigterm);
        expect(await process.exitCode.timeout(const Duration(seconds: 5)), 0);
        expect(await stdout, '');
        expect(
          (await stderr).replaceAll('Running build hooks...', '').trim(),
          '',
        );
        expect(await File('${parent.path}/service.sock').exists(), false);
        expect(
          await File('$workspace/maintenance-local-owner.json').exists(),
          true,
        );
      } finally {
        if (!exited) {
          process.kill(ProcessSignal.sigterm);
          try {
            await process.exitCode.timeout(const Duration(seconds: 5));
          } on TimeoutException {
            process.kill(ProcessSignal.sigkill);
            await process.exitCode;
          }
        }
      }
    },
  );
}
