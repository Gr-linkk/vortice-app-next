import 'dart:convert';
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/model.dart';
import 'package:maintenance_local/office_backup.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';
import 'package:sqlite3/sqlite3.dart';

// This new test helper runs with the package map of a disposable exact old
// checkout. The old implementation and original accepted checkout are unedited.
const legacyRevision = '98deb62cb3b790f3cc7f7197f9407209033877fd';
const legacyBackupHash =
    'f53eead83de01138cde19b3a3d4cd9aae542585ba8b920cfa7cb0dedf4588023';
const acceptedNativeHash =
    '582b0b00d645d9683512d4426729c633985302322232e3413fca4e7fe015d412';

String retainedState(Database db) => canonical({
  'settings': [
    for (final row in db.select(
      "SELECT * FROM settings WHERE key<>'officeRestore' ORDER BY key",
    ))
      {'key': row['key'], 'value': row['value']},
  ],
  'documents': [
    for (final row in db.select('SELECT * FROM documents ORDER BY id'))
      {'id': row['id'], 'bytes': base64Encode(row['bytes'] as List<int>)},
  ],
  'submissions': [
    for (final row in db.select('SELECT * FROM submissions ORDER BY id'))
      Map<String, dynamic>.from(row),
  ],
  'receipts': [
    for (final row in db.select('SELECT * FROM receipts ORDER BY id'))
      Map<String, dynamic>.from(row),
  ],
  'events': [
    for (final row in db.select(
      "SELECT * FROM events WHERE kind<>'office-restored' ORDER BY id",
    ))
      Map<String, dynamic>.from(row),
  ],
});

String savedState(Directory root) {
  final db = sqlite3.open(
    '${root.path}/workspace.sqlite',
    mode: OpenMode.readOnly,
  );
  try {
    return retainedState(db);
  } finally {
    db.close();
  }
}

void require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> main(List<String> args) async {
  if (args.length != 5) {
    throw ArgumentError('Expected source, backup, restored, pin and receipt.');
  }
  final revision = await Process.run('git', ['rev-parse', 'HEAD']);
  require(
    revision.exitCode == 0 &&
        revision.stdout.toString().trim() == legacyRevision,
    'Legacy runner requires the exact accepted source revision.',
  );
  final implementation = File('lib/office_backup.dart');
  require(
    digest(await implementation.readAsBytes()) == legacyBackupHash,
    'Legacy OfficeBackup implementation differs from accepted source.',
  );
  final native = Platform.environment['MAINTENANCE_NATIVE_LIBRARY'];
  if (native == null || native.isEmpty) {
    throw StateError('A private local native fixture library is required.');
  }
  require(
    digest(await File(native).readAsBytes()) == acceptedNativeHash,
    'Legacy runner requires the accepted028 native fixture.',
  );
  await RustLib.init(externalLibrary: ExternalLibrary.open(native));
  final source = Directory(args[0]),
      backup = Directory(args[1]),
      restored = Directory(args[2]);
  final before = savedState(source);
  final keyHash = digest(
    await File('${source.path}/office-key.pem').readAsBytes(),
  );
  final certHash = digest(
    await File('${source.path}/office-cert.pem').readAsBytes(),
  );
  final store = await LabStore.open(
    source,
    office: true,
    maintenanceOnly: true,
  );
  late OfficeBackupSummary created;
  try {
    created = await OfficeBackup.create(store, backup);
  } finally {
    // The synthetic original office is stopped before same-identity restore.
    await store.close();
  }
  require(savedState(source) == before, 'Legacy backup changed its source.');
  require(savedState(backup) == before, 'Legacy backup dropped saved records.');
  final inspected = await OfficeBackup.inspect(
    backup,
    requiredFormat: OfficeBackupFormat.maintenance,
  );
  require(
    inspected.fingerprint == args[3] && created.fingerprint == args[3],
    'Legacy backup does not match the separately retained synthetic pin.',
  );
  require(
    savedState(backup) == before,
    'Legacy inspection changed saved data.',
  );
  final result = await OfficeBackup.restore(
    backup,
    restored,
    expectedFingerprint: args[3],
    requiredFormat: OfficeBackupFormat.maintenance,
  );
  final reopened = await LabStore.open(
    restored,
    office: true,
    maintenanceOnly: true,
  );
  late String after;
  try {
    after = retainedState(reopened.db);
    require(after == before, 'Legacy restore/reopen changed saved records.');
    require(
      reopened.db.select('SELECT * FROM invites').isEmpty,
      'Legacy restore did not discard stale invitations.',
    );
    require(
      reopened.db.select("SELECT * FROM phones WHERE status='active'").isEmpty,
      'Legacy restore did not fence active phones.',
    );
  } finally {
    await reopened.close();
  }
  require(
    digest(await File('${restored.path}/office-key.pem').readAsBytes()) ==
            keyHash &&
        digest(await File('${restored.path}/office-cert.pem').readAsBytes()) ==
            certHash,
    'Legacy restore changed the saved synthetic office identity.',
  );
  await File(args[4]).writeAsString(
    canonical({
      'sourceRevision': legacyRevision,
      'officeBackupSha256': legacyBackupHash,
      'nativeSha256': acceptedNativeHash,
      'createdInspectedRestoredAndReopened': true,
      'sourceRetainedHash': digest(utf8.encode(before)),
      'backupRetainedHash': digest(utf8.encode(savedState(backup))),
      'restoredRetainedHash': digest(utf8.encode(after)),
      'fingerprint': result.backup.fingerprint,
      'phonesToReconfirm': result.phonesToReconfirm,
      'revokedPhones': result.backup.revokedPhones,
      'invitationsDiscarded': result.invitationsDiscarded,
    }),
    flush: true,
  );
}
