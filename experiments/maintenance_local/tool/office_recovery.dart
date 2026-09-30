import 'dart:io';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:maintenance_local/model.dart';
import 'package:maintenance_local/office_backup.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';

/// Local owner-operated recovery. Never overwrites an existing destination.
Future<void> main(List<String> args) async {
  if (!Platform.isLinux ||
      args.isEmpty ||
      !{'verify', 'restore'}.contains(args.first) ||
      (args.first == 'verify' && args.length != 2) ||
      (args.first == 'restore' && args.length != 4)) {
    stderr.writeln(
      'Usage: recovery verify BACKUP_FOLDER\n       recovery restore BACKUP_FOLDER NEW_WORKSPACE EXPECTED_TLS_FINGERPRINT',
    );
    exitCode = 64;
    return;
  }
  try {
    await RustLib.init(
      externalLibrary: ExternalLibrary.open(
        File('rust/target/debug/librust_lib_sync_lab.so').absolute.path,
      ),
    );
    final summary = args.first == 'verify'
        ? await OfficeBackup.inspect(
            Directory(args[1]),
            requiredFormat: OfficeBackupFormat.maintenance,
          )
        : (await OfficeBackup.restore(
            Directory(args[1]),
            Directory(args[2]),
            expectedFingerprint: args[3],
            requiredFormat: OfficeBackupFormat.maintenance,
          )).backup;
    stdout.writeln(
      canonical({
        'verified': true,
        'fingerprint': summary.fingerprint,
        'createdAt': summary.createdAt,
        'submittedVersions': summary.submissions,
        'decisions': summary.receipts,
        'photos': summary.evidenceFiles,
        'phonesToReconfirm': summary.phonesToReconfirm,
        'revokedPhones': summary.revokedPhones,
        if (args.first == 'restore')
          'restoredWorkspace': Directory(args[2]).absolute.path,
      }),
    );
    if (args.first == 'restore') {
      stdout.writeln(
        'Restored the same office identity. Invitations were invalidated. Create fresh invitations and reconfirm retained phones before reconnecting. Work after this backup is not included.',
      );
    }
  } catch (error) {
    stderr.writeln(error.toString().replaceFirst('Bad state: ', ''));
    exitCode = 1;
  } finally {
    RustLib.dispose();
  }
}
