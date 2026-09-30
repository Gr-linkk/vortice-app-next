import 'dart:convert';
import 'dart:io';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:maintenance_local/device_authority.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/local_sync.dart';
import 'package:maintenance_local/model.dart';
import 'package:maintenance_local/office_backup.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';

void main() {
  setUpAll(
    () async => RustLib.init(
      externalLibrary: ExternalLibrary.open(
        File('rust/target/debug/librust_lib_sync_lab.so').absolute.path,
      ),
    ),
  );
  late Directory root;
  late LabStore office;
  late OfficeIdentity identity;
  final stores = <LabStore>[];
  Directory path(String name) => Directory('${root.path}/$name');
  setUp(() async {
    root = await Directory.systemTemp.createTemp('vortice-office-backup-');
    office = await LabStore.open(path('office'), office: true);
    stores.add(office);
    await office.createWorkspace();
    identity = await OfficeIdentity.load(office);
  });
  tearDown(() async {
    for (final store in stores) {
      await store.close();
    }
    stores.clear();
    await root.delete(recursive: true);
  });

  Future<void> fill() async {
    await office.update({
      'fluid': 'pass',
      'guards': 'attention',
      'meter': 125.5,
      'notes': 'Synthetic inspection photo and immutable receipt.',
    });
    await office.attach([1, 2, 3, 4, 5]);
    final submission = await office.submit();
    await office.decide(submission['id'] as String, approve: true);
  }

  void enroll(String id, String token, {String status = 'active'}) {
    final authority = DeviceAuthority(office);
    authority.request({
      'device': id,
      'label': 'Synthetic $id',
      'token': token,
      'invitation': authority.invite(),
    });
    if (status == 'active') authority.confirm(id);
    if (status == 'revoked') authority.revoke(id);
  }

  Future<LabStore> restored(String name) async {
    final store = await LabStore.open(path(name), office: true);
    stores.add(store);
    return store;
  }

  // Rehashing a deliberately changed synthetic DB distinguishes semantic
  // validation from ordinary file corruption detection.
  Future<void> rehash(String relative) async {
    final manifestFile = File('${path('backup').path}/manifest.json');
    final manifest = jsonDecode(await manifestFile.readAsString()) as Json;
    final bytes = await File('${path('backup').path}/$relative').readAsBytes();
    (manifest['files'] as Json)[relative] = {
      'hash': digest(bytes),
      'size': bytes.length,
    };
    await manifestFile.writeAsString(canonical(manifest), flush: true);
  }

  Future<void> mutateDb(void Function(Database) action) async {
    final db = sqlite3.open('${path('backup').path}/workspace.sqlite');
    try {
      action(db);
    } finally {
      db.close();
    }
    await rehash('workspace.sqlite');
  }

  test(
    'WAL snapshot preserves drafts, immutable versions, extra complete photos and identity',
    () async {
      await fill();
      await office.evidence.add([
        9,
        8,
        7,
      ]); // Complete unreferenced history is retained.
      await office.update({'notes': 'Latest committed WAL draft.'});
      final summary = await OfficeBackup.create(office, path('backup'));
      expect(summary.device, office.device);
      expect(summary.fingerprint, identity.fingerprint);
      expect(summary.submissions, 1);
      expect(summary.receipts, 1);
      expect(summary.evidenceFiles, 2);
      expect(
        await File('${path('backup').path}/workspace.sqlite-wal').exists(),
        isFalse,
      );
      final manifestBefore = await File(
        '${path('backup').path}/manifest.json',
      ).readAsString();
      await OfficeBackup.inspect(path('backup'));
      expect(
        await File('${path('backup').path}/manifest.json').readAsString(),
        manifestBefore,
      );
      await OfficeBackup.restore(
        path('backup'),
        path('restored'),
        expectedFingerprint: identity.fingerprint,
      );
      final copy = await restored('restored');
      expect(copy.device, office.device);
      expect(await copy.fields(), await office.fields());
      expect(copy.receipts, office.receipts);
      expect(copy.submissions, office.submissions);
      expect(await copy.evidence.manifest(), await office.evidence.manifest());
      expect(
        (await OfficeIdentity.load(copy)).fingerprint,
        identity.fingerprint,
      );
      expect(
        digest(await File('${copy.root.path}/office-key.pem').readAsBytes()),
        digest(await File('${office.root.path}/office-key.pem').readAsBytes()),
      );
      expect(
        await office.approvalProblem(office.submissions.single),
        isNotNull,
      );
      // The async decision remains protected by its original immutable receipt.
      await expectLater(
        copy.decide(
          copy.submissions.single['id'] as String,
          approve: false,
          reason: 'Changed',
        ),
        throwsStateError,
      );
    },
  );

  test(
    'Stale authority is fenced: active and pending await reconfirmation, revoked stays revoked',
    () async {
      final activeToken = secret(),
          pendingToken = secret(),
          revokedToken = secret();
      enroll('active-phone', activeToken);
      enroll('pending-phone', pendingToken, status: 'pending');
      enroll('revoked-phone', revokedToken, status: 'revoked');
      DeviceAuthority(office).invite(); // Outstanding unused invitation.
      final summary = await OfficeBackup.create(office, path('backup'));
      DeviceAuthority(
        office,
      ).revoke('active-phone'); // Revocation after the stale backup.
      final result = await OfficeBackup.restore(
        path('backup'),
        path('restored'),
      );
      expect(result.phonesToReconfirm, 2);
      expect(result.invitationsDiscarded, 4);
      expect(result.note, contains('owner confirmation'));
      final copy = await restored('restored');
      final authority = DeviceAuthority(copy);
      expect(authority.phones.map((p) => p['status']), [
        'pending',
        'pending',
        'revoked',
      ]);
      for (final token in [activeToken, pendingToken, revokedToken]) {
        expect(() => authority.authenticate('Bearer $token'), throwsStateError);
      }
      expect(copy.db.select('SELECT * FROM invites'), isEmpty);
      expect(
        (copy.setting('officeRestore') as Json)['invitationsDiscarded'],
        4,
      );
      authority.confirm('active-phone');
      expect(authority.authenticate('Bearer $activeToken'), 'active-phone');
      authority.confirm('revoked-phone');
      expect(
        () => authority.authenticate('Bearer $revokedToken'),
        throwsStateError,
      );
      expect(
        summary.fingerprint,
        (await OfficeIdentity.load(copy)).fingerprint,
      );
      // Backup authority is retained exactly; only the new workspace is fenced.
      final original = sqlite3.open(
        '${path('backup').path}/workspace.sqlite',
        mode: OpenMode.readOnly,
      );
      try {
        expect(
          original
              .select("SELECT status FROM phones WHERE id='active-phone'")
              .single['status'],
          'active',
        );
        expect(original.select('SELECT * FROM invites').length, 4);
      } finally {
        original.close();
      }
    },
  );

  test('New files and directories have owner-only permissions', () async {
    await fill();
    await OfficeBackup.create(office, path('backup'));
    await OfficeBackup.restore(path('backup'), path('restored'));
    for (final directory in [path('backup'), path('restored')]) {
      expect((await directory.stat()).mode & 0x3f, 0);
      await for (final file in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        expect((await file.stat()).mode & 0x3f, 0, reason: file.path);
      }
    }
  });

  test(
    'Required incomplete evidence blocks publication and leaves no staging directory',
    () async {
      await fill();
      final hash = valuesOf(await office.fields())['photo'] as String;
      await office.evidence
          .file(hash)
          .rename('${office.evidence.file(hash).path}.part');
      await expectLater(
        OfficeBackup.create(office, path('backup')),
        throwsStateError,
      );
      expect(await path('backup').exists(), isFalse);
      expect(
        (await root.list().toList()).where(
          (p) => p.path.contains('.office-recovery-'),
        ),
        isEmpty,
      );
    },
  );

  test('Existing destinations are preserved for backup and restore', () async {
    await OfficeBackup.create(office, path('backup'));
    await path('existing').create();
    final sentinel = File('${path('existing').path}/retained');
    await sentinel.writeAsString('retain existing data');
    await expectLater(
      OfficeBackup.create(office, path('existing')),
      throwsStateError,
    );
    await expectLater(
      OfficeBackup.restore(path('backup'), path('existing')),
      throwsStateError,
    );
    expect(await sentinel.readAsString(), 'retain existing data');
    await expectLater(
      OfficeBackup.create(office, path('backup')),
      throwsStateError,
    );
    await OfficeBackup.inspect(path('backup'));
  });

  test(
    'Corrupt or missing files and a wrong expected pin cannot restore',
    () async {
      await fill();
      await OfficeBackup.create(office, path('backup'));
      await expectLater(
        OfficeBackup.restore(
          path('backup'),
          path('wrong-pin'),
          expectedFingerprint: '0' * 64,
        ),
        throwsStateError,
      );
      expect(await path('wrong-pin').exists(), isFalse);
      final hash = valuesOf(await office.fields())['photo'] as String;
      await File('${path('backup').path}/evidence/$hash').writeAsBytes([0]);
      await expectLater(OfficeBackup.inspect(path('backup')), throwsStateError);
      await expectLater(
        OfficeBackup.restore(path('backup'), path('corrupt')),
        throwsStateError,
      );
      expect(await path('corrupt').exists(), isFalse);
      await File('${path('backup').path}/office-key.pem').delete();
      await expectLater(OfficeBackup.inspect(path('backup')), throwsStateError);
    },
  );

  test(
    'Mismatched private key fails even with a matching manifest file hash',
    () async {
      await OfficeBackup.create(office, path('backup'));
      final other = await LabStore.open(path('other-office'), office: true);
      stores.add(other);
      await OfficeIdentity.load(other);
      await File(
        '${other.root.path}/office-key.pem',
      ).copy('${path('backup').path}/office-key.pem');
      await rehash('office-key.pem');
      await expectLater(OfficeBackup.inspect(path('backup')), throwsStateError);
      await expectLater(
        OfficeBackup.restore(path('backup'), path('restored')),
        throwsStateError,
      );
      expect(await path('restored').exists(), isFalse);
    },
  );

  test(
    'Semantic receipt, authority and saved fingerprint changes fail after rehash',
    () async {
      await fill();
      await OfficeBackup.create(office, path('backup'));
      await mutateDb((db) {
        final row = db.select('SELECT * FROM receipts').single;
        final payload = jsonDecode(row['payload'] as String) as Json;
        payload['submissionHash'] = '0' * 64;
        db.execute('UPDATE receipts SET hash=?,payload=?', [
          contentHash(payload),
          canonical(payload),
        ]);
      });
      await expectLater(OfficeBackup.inspect(path('backup')), throwsStateError);
      await path('backup').delete(recursive: true);
      await OfficeBackup.create(office, path('backup'));
      await mutateDb(
        (db) => db.execute(
          "INSERT INTO phones VALUES ('bogus','Bogus',?,'administrator')",
          ['0' * 64],
        ),
      );
      await expectLater(OfficeBackup.inspect(path('backup')), throwsStateError);
      await path('backup').delete(recursive: true);
      await OfficeBackup.create(office, path('backup'));
      await mutateDb(
        (db) => db.execute(
          "INSERT INTO settings VALUES ('officeFingerprint',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
          [canonical('0' * 64)],
        ),
      );
      await expectLater(OfficeBackup.inspect(path('backup')), throwsStateError);
    },
  );

  test(
    'Unexpected schema and symlinks cannot become office recovery data',
    () async {
      await OfficeBackup.create(office, path('backup'));
      await mutateDb(
        (db) => db.execute(
          "CREATE TRIGGER replace_identity AFTER UPDATE ON phones BEGIN DELETE FROM settings; END",
        ),
      );
      await expectLater(
        OfficeBackup.restore(path('backup'), path('restored')),
        throwsStateError,
      );
      await path('backup').delete(recursive: true);
      await OfficeBackup.create(office, path('backup'));
      await File('${path('backup').path}/office-key.pem').delete();
      await Link(
        '${path('backup').path}/office-key.pem',
      ).create('${office.root.path}/office-key.pem');
      await expectLater(OfficeBackup.inspect(path('backup')), throwsStateError);
    },
  );

  test(
    'Phone role and public recovery bundles cannot be promoted to office backups',
    () async {
      final phone = await LabStore.open(path('phone'), office: false);
      stores.add(phone);
      await phone.importOfficeBundle(await office.publicBundle());
      await expectLater(
        OfficeBackup.create(phone, path('phone-backup')),
        throwsStateError,
      );
      await expectLater(OfficeBackup.inspect(phone.root), throwsStateError);
      final masquerading = await LabStore.open(
        path('masquerading'),
        office: true,
      );
      stores.add(masquerading);
      await masquerading.createWorkspace();
      masquerading.setSetting('pairing', {
        'token': 'synthetic phone credential',
      });
      await OfficeIdentity.load(masquerading);
      await expectLater(
        OfficeBackup.create(masquerading, path('promoted')),
        throwsStateError,
      );
    },
  );

  test(
    'Unrecognized SQLite versions fail before restore publication',
    () async {
      await OfficeBackup.create(office, path('backup'));
      await mutateDb((db) => db.execute('PRAGMA user_version=2'));
      await expectLater(OfficeBackup.inspect(path('backup')), throwsStateError);
      await expectLater(
        OfficeBackup.restore(path('backup'), path('restored')),
        throwsStateError,
      );
      expect(await path('restored').exists(), isFalse);
      await mutateDb((db) => db.execute('PRAGMA user_version=0'));
      await OfficeBackup.inspect(path('backup'));
    },
  );

  test(
    'Backup respects serial queue boundary while later edits remain outside snapshot',
    () async {
      await office.update({'notes': 'Before snapshot'});
      final pending = OfficeBackup.create(office, path('backup'));
      final later = office.update({'notes': 'After snapshot'});
      await pending;
      await later;
      await OfficeBackup.restore(path('backup'), path('restored'));
      final copy = await restored('restored');
      expect(valuesOf(await copy.fields())['notes'], 'Before snapshot');
      expect(valuesOf(await office.fields())['notes'], 'After snapshot');
    },
  );
}
