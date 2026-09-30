import 'dart:io';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/device_authority.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/local_sync.dart';
import 'package:maintenance_local/model.dart';
import 'package:maintenance_local/office_backup.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';
import 'support/recovery_process_harness.dart';

void main() {
  setUpAll(() async {
    await RustLib.init(
      externalLibrary: ExternalLibrary.open(
        File('rust/target/debug/librust_lib_sync_lab.so').absolute.path,
      ),
    );
  });
  late Directory root;
  late LabStore office;
  late OfficeIdentity identity;
  late String activeToken, revokedToken;
  final children = <RecoveryProcess>[];
  Directory path(String name) => Directory('${root.path}/$name');

  setUp(() async {
    root = await Directory.systemTemp.createTemp('vortice-interruption-');
    office = await LabStore.open(path('office'), office: true);
    await office.createWorkspace();
    identity = await OfficeIdentity.load(office);
    await office.update({
      'notes': 'Synthetic committed inspection',
      'fluid': 'pass',
      'guards': 'pass',
      'meter': 125.5,
    });
    await office.attach([1, 2, 3, 4]);
    final submission = await office.submit();
    await office.decide(submission['id'] as String, approve: true);
    activeToken = secret();
    revokedToken = secret();
    final authority = DeviceAuthority(office);
    for (final entry in {
      'active': activeToken,
      'revoked': revokedToken,
    }.entries) {
      authority.request({
        'device': entry.key,
        'label': 'Synthetic ${entry.key}',
        'token': entry.value,
        'invitation': authority.invite(),
      });
      authority.confirm(entry.key);
    }
    authority.revoke('revoked');
    authority.invite();
  });

  tearDown(() async {
    for (final child in children) {
      await child.stop();
    }
    children.clear();
    await office.close();
    await root.delete(recursive: true);
  });

  Future<RecoveryProcess> child(
    String operation,
    String name, {
    String? boundary,
  }) async {
    final args = operation == 'create'
        ? [
            'test/support/recovery_process_child.dart',
            office.root.path,
            path(name).path,
          ]
        : [
            'tool/office_recovery.dart',
            'restore',
            path('backup').path,
            path(name).path,
            identity.fingerprint,
          ];
    final result = await RecoveryProcess.start(
      path('control-${children.length}'),
      args,
      boundary: boundary,
    );
    children.add(result);
    return result;
  }

  Future<List<Directory>> stages() async => (await root.list().toList())
      .whereType<Directory>()
      .where(
        (item) => item.uri.pathSegments
            .where((p) => p.isNotEmpty)
            .last
            .startsWith('.office-recovery-'),
      )
      .toList();

  Future<void> verifyBackup(String name) async {
    final summary = await OfficeBackup.inspect(path(name));
    expect(summary.device, office.device);
    expect(summary.fingerprint, identity.fingerprint);
    expect(summary.submissions, 1);
    expect(summary.receipts, 1);
    expect(summary.evidenceFiles, 1);
    // Never open an immutable backup as a writable workspace: initialization
    // can change its database and invalidate the inventory being tested.
    for (final item in await office.evidence.manifest()) {
      final hash = item['hash'] as String;
      expect(
        await File('${path(name).path}/evidence/$hash').readAsBytes(),
        await office.evidence.file(hash).readAsBytes(),
      );
    }
    expect(
      digest(await File('${path(name).path}/office-key.pem').readAsBytes()),
      digest(await File('${office.root.path}/office-key.pem').readAsBytes()),
    );
  }

  Future<void> verifyRestore(String name) async {
    final copy = await LabStore.open(path(name), office: true);
    try {
      expect(copy.device, office.device);
      expect(
        (await OfficeIdentity.load(copy)).fingerprint,
        identity.fingerprint,
      );
      expect(await copy.fields(), await office.fields());
      expect(copy.submissions, office.submissions);
      expect(copy.receipts, office.receipts);
      expect(await copy.evidence.manifest(), await office.evidence.manifest());
      final authority = DeviceAuthority(copy);
      expect(authority.phones.map((p) => p['status']), ['pending', 'revoked']);
      for (final token in [activeToken, revokedToken]) {
        expect(() => authority.authenticate('Bearer $token'), throwsStateError);
      }
      expect(copy.db.select('SELECT * FROM invites'), isEmpty);
      expect((copy.setting('officeRestore') as Json)['phonesToReconfirm'], 1);
    } finally {
      await copy.close();
    }
  }

  for (final operation in ['create', 'restore']) {
    for (final boundary in ['copy-staged', 'before-publish', 'after-publish']) {
      test(
        '$operation SIGKILL $boundary preserves a coherent retry',
        () async {
          if (operation == 'restore') {
            await OfficeBackup.create(office, path('backup'));
          }
          final original = canonical({
            'fields': await office.fields(),
            'submissions': office.submissions,
            'receipts': office.receipts,
            'evidence': await office.evidence.manifest(),
            'identity': digest(
              await File('${office.root.path}/office-key.pem').readAsBytes(),
            ),
          });
          final interrupted = await child(
            operation,
            'destination',
            boundary: boundary,
          );
          await interrupted.ready();
          await interrupted.stop();
          expect(
            canonical({
              'fields': await office.fields(),
              'submissions': office.submissions,
              'receipts': office.receipts,
              'evidence': await office.evidence.manifest(),
              'identity': digest(
                await File('${office.root.path}/office-key.pem').readAsBytes(),
              ),
            }),
            original,
          );
          expect(
            await path('destination').exists(),
            boundary == 'after-publish',
          );
          if (boundary != 'after-publish') {
            // A complete or partial private stage is not an automatic backup.
            expect(await stages(), hasLength(1));
            if (boundary == 'copy-staged') {
              final stage = (await stages()).single;
              expect((await stage.stat()).mode & 0x3f, 0);
              expect(
                await File('${stage.path}/manifest.json').exists(),
                isFalse,
              );
              await expectLater(OfficeBackup.inspect(stage), throwsStateError);
              if (operation == 'restore') await verifyBackup('backup');
            }
            final retry = await child(operation, 'destination');
            expect(await retry.finish(), 0, reason: await retry.errors);
            expect(await stages(), hasLength(1));
          } else {
            expect(await stages(), isEmpty);
            final retry = await child(operation, 'destination');
            expect(await retry.finish(), 1);
            expect(
              await retry.errors,
              contains(
                operation == 'create'
                    ? 'backup could not be confirmed'
                    : 'restore failed',
              ),
            );
          }
          if (operation == 'create') {
            await verifyBackup('destination');
            await OfficeBackup.restore(path('destination'), path('checked'));
            await verifyRestore('checked');
          } else {
            await verifyRestore('destination');
            await verifyBackup('backup');
          }
        },
        timeout: const Timeout(Duration(seconds: 60)),
      );
    }

    test(
      '$operation publication race retains even an empty destination',
      () async {
        if (operation == 'restore') {
          await OfficeBackup.create(office, path('backup'));
        }
        final racing = await child(operation, 'destination', boundary: 'race');
        await racing.ready();
        await path('destination').create();
        final before = await path('destination').stat();
        await racing.release();
        expect(await racing.finish(), 1);
        expect(await path('destination').list().toList(), isEmpty);
        expect((await path('destination').stat()).modified, before.modified);
        expect(await stages(), isEmpty);
        await path('destination').delete();
        final retry = await child(operation, 'destination');
        expect(await retry.finish(), 0, reason: await retry.errors);
        if (operation == 'create') {
          await verifyBackup('destination');
        } else {
          await verifyRestore('destination');
        }
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );

    test(
      '$operation failed cleanup retains destination and permits fresh retry',
      () async {
        if (operation == 'restore') {
          await OfficeBackup.create(office, path('backup'));
        }
        final failing = await child(operation, 'destination', boundary: 'race');
        await failing.ready();
        final stage = (await stages()).single;
        await path('destination').create();
        final sentinel = File('${path('destination').path}/owner-data');
        await sentinel.writeAsString('synthetic existing destination');
        // Deny unlinking stage children after the no-clobber publication fails.
        // This changes only synthetic directories, and teardown restores access.
        final chmod = await Process.run('/usr/bin/chmod', ['500', stage.path]);
        expect(chmod.exitCode, 0);
        try {
          await failing.release();
          expect(await failing.finish(), 1);
          final failureMessage = await failing.errors;
          expect(failureMessage, contains('cleanup'));
          expect(failureMessage, isNot(contains('FileSystemException')));
          expect(failureMessage, isNot(contains('PathAccessException')));
          expect(
            await sentinel.readAsString(),
            'synthetic existing destination',
          );
          expect(await stage.exists(), isTrue);
          expect((await stage.stat()).mode & 0x3f, 0);
          final retry = await child(operation, 'fresh-destination');
          expect(await retry.finish(), 0, reason: await retry.errors);
          if (operation == 'create') {
            await verifyBackup('fresh-destination');
          } else {
            await verifyRestore('fresh-destination');
            await verifyBackup('backup');
          }
          expect(
            await sentinel.readAsString(),
            'synthetic existing destination',
          );
        } finally {
          await Process.run('/usr/bin/chmod', ['700', stage.path]);
        }
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );
  }
}
