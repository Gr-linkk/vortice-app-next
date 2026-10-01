import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/model.dart';

import 'support/corrective_planning_legacy_backup_case.dart' as legacy;

void main() {
  test(
    'Exact LF009 reader retains refused schema3 data and keeps schema2 recovery',
    () async {
      final app = Directory.current.absolute;
      final repository = app.parent.parent;
      final temp = await Directory.systemTemp.createTemp('corrective-compat-');
      final oldRoot = Directory(
        '${repository.path}/work/${temp.uri.pathSegments.where((s) => s.isNotEmpty).last}',
      );
      Future<ProcessResult> command(
        List<String> args, {
        String? cwd,
        Map<String, String>? env,
      }) async {
        final result = await Process.run(
          args.first,
          args.skip(1).toList(),
          workingDirectory: cwd,
          environment: env,
        );
        expect(
          result.exitCode,
          0,
          reason: '${args.first}: ${result.stdout}\n${result.stderr}',
        );
        return result;
      }

      try {
        await command([
          'git',
          'clone',
          '--no-hardlinks',
          '--no-checkout',
          repository.path,
          oldRoot.path,
        ]);
        await command([
          'git',
          '-C',
          oldRoot.path,
          'checkout',
          '--detach',
          legacy.legacyRevision,
        ]);
        final oldApp = Directory(
          '${oldRoot.path}/experiments/maintenance_local',
        );
        final oldWork = Directory(
          '${oldRoot.path}/work/manual-fault-toolchain',
        );
        await oldWork.create(recursive: true);
        for (final name in ['flutter', 'pub']) {
          await command([
            'cp',
            '-R',
            '${repository.path}/work/manual-fault-toolchain/$name',
            '${oldWork.path}/$name',
          ]);
        }
        const helper =
            'test/support/corrective_planning_legacy_backup_case.dart';
        await File('${app.path}/$helper').copy('${oldApp.path}/$helper');
        final env = {
          ...Platform.environment,
          'PATH': '${oldWork.path}/flutter/bin:/usr/local/bin:/usr/bin:/bin',
          'HOME': '${oldWork.path}/home',
          'PUB_CACHE': '${oldWork.path}/pub',
          'FLUTTER_ROOT': '${oldWork.path}/flutter',
          'CI': 'true',
          'FLUTTER_SUPPRESS_ANALYTICS': 'true',
          'DART_SUPPRESS_ANALYTICS': 'true',
        };
        await Directory(env['HOME']!).create(recursive: true);
        await command(
          [
            '${oldWork.path}/flutter/bin/flutter',
            'pub',
            'get',
            '--offline',
            '--enforce-lockfile',
          ],
          cwd: oldApp.path,
          env: env,
        );
        const sqliteCache =
            '.dart_tool/hooks_runner/shared/sqlite3/build/download-2219febf/libsqlite3.so';
        const sqliteHash =
            '2219febf70a5ed39a39db1bc46e00d3df0b3bb881ad36a67e2e5a0cd91ebd3a5';
        final sourceSqlite = File('${app.path}/$sqliteCache');
        expect(digest(await sourceSqlite.readAsBytes()), sqliteHash);
        final oldSqlite = File('${oldApp.path}/$sqliteCache');
        await oldSqlite.parent.create(recursive: true);
        await sourceSqlite.copy(oldSqlite.path);
        expect(digest(await oldSqlite.readAsBytes()), sqliteHash);
        final sourceInode = (await command([
          'stat',
          '-c',
          '%d:%i',
          sourceSqlite.path,
        ])).stdout.toString().trim();
        final oldInode = (await command([
          'stat',
          '-c',
          '%d:%i',
          oldSqlite.path,
        ])).stdout.toString().trim();
        expect(oldInode, isNot(sourceInode));
        await command(
          [
            '${oldWork.path}/flutter/bin/flutter',
            'test',
            '--no-pub',
            '--concurrency=1',
            helper,
          ],
          cwd: oldApp.path,
          env: env,
        );
        final proof =
            jsonDecode(
                  await File(
                    '${oldRoot.path}/outputs/corrective-planning/legacy-format-fence-proof.json',
                  ).readAsString(),
                )
                as Json;
        expect(proof['sourceRevision'], legacy.legacyRevision);
        expect(proof['labStoreSha256'], legacy.legacyStoreHash);
        expect(proof['officeBackupSha256'], legacy.legacyBackupHash);
        expect(proof['nativeSha256'], legacy.acceptedNativeHash);
        expect(proof['productionImplementationUnchanged'], isTrue);
        final checks = proof['checks'] as Json;
        expect(
          checks['schema2Control']['openedCreatedInspectedRestoredAndReopened'],
          isTrue,
        );
        expect(
          checks['schema3WorkspaceRefused']['allFileBytesRetained'],
          isTrue,
        );
        for (final version in [2, 3]) {
          final result = checks['manifest${version}Schema3Refused'] as Json;
          expect(result['inspectRefused'], isTrue);
          expect(result['restoreRefused'], isTrue);
          expect(result['allBackupFileBytesRetained'], isTrue);
          expect(result['destinationNotPublished'], isTrue);
        }
        proof['privateCopiedSqliteCache'] = {
          'sourceSha256': sqliteHash,
          'destinationSha256': digest(await oldSqlite.readAsBytes()),
          'sourceDeviceAndInode': sourceInode,
          'destinationDeviceAndInode': oldInode,
          'distinctFiles': true,
        };
        final output = Directory(
          '${repository.path}/outputs/corrective-planning',
        );
        await output.create(recursive: true);
        // Preserve the first, pre-implementation compatibility proof separately.
        await File(
          '${output.path}/legacy-format-fence-regression-proof.json',
        ).writeAsString(canonical(proof), flush: true);
      } finally {
        if (await oldRoot.exists()) await oldRoot.delete(recursive: true);
        await temp.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
