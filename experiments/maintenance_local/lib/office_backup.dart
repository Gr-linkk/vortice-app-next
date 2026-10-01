import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:sqlite3/sqlite3.dart';
import 'approval_rules.dart';
import 'evidence_store.dart';
import 'lab_store.dart';
import 'model.dart';
import 'maintenance_domain.dart';
import 'agent_service/proposal_review_rules.dart';
import 'src/rust/api/documents.dart';

/// Product entry points require [maintenance]. A null requirement retains the
/// adopted Sync Lab APIs for synthetic regression fixtures only.
enum OfficeBackupFormat { syncLab, maintenance }

class _WrongBackupFormat extends StateError {
  _WrongBackupFormat(super.message);
}

/// Safe metadata only. Private credentials remain in the owner-only directory.
class OfficeBackupSummary {
  const OfficeBackupSummary({
    required this.directory,
    required this.createdAt,
    required this.device,
    required this.fingerprint,
    required this.submissions,
    required this.receipts,
    required this.evidenceFiles,
    required this.phonesToReconfirm,
    required this.revokedPhones,
    required this.invitationsToDiscard,
  });
  final Directory directory;
  final String createdAt, device, fingerprint;
  final int submissions, receipts, evidenceFiles;
  final int phonesToReconfirm, revokedPhones, invitationsToDiscard;
}

class OfficeRestoreResult {
  const OfficeRestoreResult(this.directory, this.backup);
  final Directory directory;
  final OfficeBackupSummary backup;
  int get phonesToReconfirm => backup.phonesToReconfirm;
  int get invitationsDiscarded => backup.invitationsToDiscard;
  String get note =>
      'Restored the same office identity. $phonesToReconfirm phones require '
      'owner confirmation; $invitationsDiscarded invitations were discarded. '
      'Revoked phones remain revoked.';
}

/// Versioned local office recovery, deliberately separate from phone bundles.
///
/// Hashes detect corruption, not malicious replacement by someone with local
/// access. Compare a separately retained TLS fingerprint when restoring.
class OfficeBackup {
  static const version = 1;
  static const maintenanceVersion = 2;
  static const _maxFiles = 4096;
  static const _maxTotalBytes = 512 * 1024 * 1024;
  static const _maxDatabaseBytes = 128 * 1024 * 1024;
  static const _maxManifestBytes = 4 * 1024 * 1024;
  static const _maxIdentityBytes = 64 * 1024;

  static Future<OfficeBackupSummary> create(
    LabStore store,
    Directory destination,
  ) async {
    _linux();
    store.requireOffice();
    return store.queue.run(() async {
      Directory? stage;
      try {
        await _absent(destination);
        final source = await store.root.resolveSymbolicLinks();
        final parent = await destination.parent.resolveSymbolicLinks();
        if (parent == source || parent.startsWith('$source/')) {
          throw StateError('Choose a backup location outside the workspace.');
        }
        stage = await _stage(destination);
        // VACUUM INTO includes committed WAL contents without copying a live DB.
        if ((await File('${store.root.path}/workspace.sqlite').length()) >
            _maxDatabaseBytes) {
          throw StateError('Workspace exceeds the lab recovery limit.');
        }
        store.db.execute('VACUUM INTO ?', ['${stage.path}/workspace.sqlite']);
        await _private('${stage.path}/workspace.sqlite', false);
        for (final name in ['office-cert.pem', 'office-key.pem']) {
          await _copy(
            File('${store.root.path}/$name'),
            File('${stage.path}/$name'),
            _maxIdentityBytes,
          );
        }
        final evidence = Directory('${stage.path}/evidence');
        await evidence.create();
        await _private(evidence.path, true);
        var totalBytes = await File('${stage.path}/workspace.sqlite').length();
        if (totalBytes > _maxDatabaseBytes) {
          throw StateError('Database exceeds lab limits.');
        }
        if (await store.evidence.root.exists()) {
          var count = 0;
          await for (final item in store.evidence.root.list(
            followLinks: false,
          )) {
            final name = item.uri.pathSegments.last;
            // Incomplete transfers are excluded and cannot satisfy references.
            if (RegExp(r'^[a-f0-9]{64}\.part$').hasMatch(name) &&
                item is File) {
              continue;
            }
            if (!hashPattern.hasMatch(name) ||
                item is! File ||
                ++count > _maxFiles) {
              throw StateError(
                'The evidence directory is not a complete lab store.',
              );
            }
            totalBytes += await item.length();
            if (totalBytes > _maxTotalBytes - 2 * _maxIdentityBytes) {
              throw StateError('Recovery exceeds lab limits.');
            }
            final bytes = await _read(item, EvidenceStore.maxBytes);
            if (digest(bytes) != name) {
              throw StateError('Evidence integrity failed.');
            }
            await _write(File('${evidence.path}/$name'), bytes);
          }
        }
        final fingerprint = await _identity(stage);
        final facts = await _database(stage);
        final files = await _inventory(stage);
        final manifest = <String, dynamic>{
          'format': store.realWorkspace
              ? 'maintenance-local-office'
              : 'vortice-sync-lab-office',
          'version': store.realWorkspace ? maintenanceVersion : version,
          'role': 'linux-office',
          'createdAt': store.stamp(),
          'device': facts.device,
          'fingerprint': fingerprint,
          'files': files,
        };
        await _write(
          File('${stage.path}/manifest.json'),
          utf8.encode(canonical(manifest)),
        );
        final checked = await _inspect(stage);
        await _publish(stage, destination);
        stage = null;
        return _relocate(checked, destination);
      } catch (_) {
        throw StateError(
          'Office backup could not be confirmed. If a destination was created, verify it before using it. '
          'Check the destination, complete photos and saved office identity.',
        );
      } finally {
        await _cleanup(stage);
      }
    });
  }

  static Future<OfficeBackupSummary> inspect(
    Directory directory, {
    OfficeBackupFormat? requiredFormat,
  }) async {
    _linux();
    try {
      return await _inspect(directory, requiredFormat: requiredFormat);
    } on _WrongBackupFormat {
      rethrow;
    } catch (_) {
      throw StateError('This is not a complete, valid office backup.');
    }
  }

  static Future<OfficeRestoreResult> restore(
    Directory backup,
    Directory destination, {
    String? expectedFingerprint,
    OfficeBackupFormat? requiredFormat,
  }) async {
    _linux();
    Directory? stage;
    try {
      await _absent(destination);
      final manifest =
          jsonDecode(
                utf8.decode(
                  await _read(
                    File('${backup.path}/manifest.json'),
                    _maxManifestBytes,
                  ),
                ),
              )
              as Json;
      final summary = await _inspect(
        backup,
        manifest: manifest,
        requiredFormat: requiredFormat,
      );
      if (expectedFingerprint != null &&
          summary.fingerprint != expectedFingerprint) {
        throw StateError('Office identity did not match.');
      }
      final source = await backup.resolveSymbolicLinks();
      final parent = await destination.parent.resolveSymbolicLinks();
      if (parent == source || parent.startsWith('$source/')) {
        throw StateError('Restore must be outside the backup.');
      }
      stage = await _stage(destination);
      for (final item in (manifest['files'] as Map).entries) {
        final name = item.key as String;
        final target = File('${stage.path}/$name');
        if (name.startsWith('evidence/')) {
          await target.parent.create();
          await _private(target.parent.path, true);
        }
        await _copy(File('${backup.path}/$name'), target, _limit(name));
      }
      // Re-check staged bytes against the original verified manifest: source
      // changes during copying must never publish a different office identity.
      await _write(
        File('${stage.path}/manifest.json'),
        utf8.encode(canonical(manifest)),
      );
      final staged = await _inspect(stage, requiredFormat: requiredFormat);
      if (staged.fingerprint != summary.fingerprint ||
          staged.device != summary.device) {
        throw StateError('Backup changed while being restored.');
      }
      await File('${stage.path}/manifest.json').delete();
      final db = sqlite3.open('${stage.path}/workspace.sqlite');
      try {
        db.execute('PRAGMA foreign_keys=ON');
        db.execute('BEGIN IMMEDIATE');
        try {
          db.execute(
            "UPDATE phones SET status='pending' WHERE status IN ('active','pending')",
          );
          db.execute('DELETE FROM invites');
          if (requiredFormat == OfficeBackupFormat.maintenance) {
            for (final entry in {
              'localMaintenanceApplication':
                  'org.vortice.next.maintenance_local',
              'localMaintenanceRole': 'linux-office',
            }.entries) {
              db.execute(
                'INSERT INTO settings VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',
                [entry.key, canonical(entry.value)],
              );
            }
          }
          final note = <String, dynamic>{
            'restoredAt': DateTime.now().toUtc().toIso8601String(),
            'backupCreatedAt': summary.createdAt,
            'phonesToReconfirm': summary.phonesToReconfirm,
            'invitationsDiscarded': summary.invitationsToDiscard,
            'fingerprint': summary.fingerprint,
          };
          db.execute(
            'INSERT INTO settings VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',
            ['officeRestore', canonical(note)],
          );
          db.execute('INSERT INTO events(kind,payload) VALUES (?,?)', [
            'office-restored',
            canonical(note),
          ]);
          db.execute('COMMIT');
        } catch (_) {
          db.execute('ROLLBACK');
          rethrow;
        }
      } finally {
        db.close();
      }
      final fenced = await _database(stage);
      if (fenced.device != summary.device ||
          fenced.active != 0 ||
          fenced.invites != 0 ||
          fenced.pending != summary.phonesToReconfirm ||
          fenced.revoked != summary.revokedPhones ||
          await _identity(stage) != summary.fingerprint) {
        throw StateError('Restore validation failed.');
      }
      await _private('${stage.path}/workspace.sqlite', false);
      if (requiredFormat == OfficeBackupFormat.maintenance) {
        await _write(
          File('${stage.path}/maintenance-local-owner.json'),
          utf8.encode(
            canonical({
              'application': 'org.vortice.next.maintenance_local',
              'role': 'linux-office',
              'version': 1,
            }),
          ),
        );
      }
      await _publish(stage, destination);
      stage = null;
      return OfficeRestoreResult(destination, summary);
    } on _WrongBackupFormat {
      rethrow;
    } catch (_) {
      throw StateError(
        'Office restore failed. Use a complete office backup with '
        'the expected identity and an absent destination. Existing data was retained.',
      );
    } finally {
      await _cleanup(stage);
    }
  }

  static Future<void> _cleanup(Directory? stage) async {
    if (stage == null) return;
    try {
      if (await stage.exists()) await stage.delete(recursive: true);
    } catch (_) {
      throw StateError(
        'Office recovery cleanup could not finish. Keep any .office-recovery-* '
        'staging folder private and retain the original workspace and backup. '
        'After this attempt stops, retry into a different absent destination. '
        'Verify any published backup before using it; follow the recovery '
        'runbook for a restored workspace.',
      );
    }
  }

  static void _linux() {
    if (!Platform.isLinux) {
      throw StateError('Office backup and restore require Linux.');
    }
  }

  static Future<void> _absent(Directory target) async {
    if (await FileSystemEntity.type(target.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw StateError('Destination already exists.');
    }
  }

  static Future<Directory> _stage(Directory target) async {
    final stage = await target.parent.createTemp('.office-recovery-');
    await _private(stage.path, true);
    return stage;
  }

  static Future<void> _publish(Directory stage, Directory target) async {
    await _absent(target);
    // Flush staged file and directory metadata before exposing a complete copy.
    await _sync(stage);
    // Same-parent GNU mv uses a no-replace rename: concurrent creation of even
    // an empty destination must never replace an existing workspace.
    final result = await Process.run('mv', [
      '--no-clobber',
      '--no-target-directory',
      '--',
      stage.path,
      target.absolute.path,
    ]);
    if (result.exitCode != 0 || await stage.exists()) {
      throw StateError(
        'Destination could not be published without replacement.',
      );
    }
    // Persist the publication itself before reporting a recoverable backup.
    await _sync(target.parent);
  }

  static Future<void> _sync(Directory directory) async {
    final result = await Process.run('sync', ['-f', '--', directory.path]);
    if (result.exitCode != 0) {
      throw StateError('Recovery publication could not be flushed.');
    }
  }

  static Future<void> _private(String path, bool directory) async {
    final result = await Process.run('chmod', [
      directory ? '700' : '600',
      '--',
      path,
    ]);
    if (result.exitCode != 0 ||
        ((await FileStat.stat(path)).mode & 0x3f) != 0) {
      throw StateError('Cannot protect local recovery files.');
    }
  }

  static Future<List<int>> _read(File file, int maximum) async {
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw StateError('Recovery requires ordinary files.');
    }
    final size = await file.length();
    if (size < 1 || size > maximum) {
      throw StateError('Recovery file exceeds lab limits.');
    }
    final bytes = await file.readAsBytes();
    if (bytes.length != size) throw StateError('Recovery file changed.');
    return bytes;
  }

  static Future<void> _write(File file, List<int> bytes) async {
    // Staging parent is private before any credential bytes are written.
    await file.writeAsBytes(bytes, flush: true);
    await _private(file.path, false);
  }

  static Future<void> _copy(File source, File target, int limit) async =>
      _write(target, await _read(source, limit));

  static int _limit(String path) => path == 'workspace.sqlite'
      ? _maxDatabaseBytes
      : path.startsWith('evidence/')
      ? EvidenceStore.maxBytes
      : _maxIdentityBytes;

  static Future<Json> _inventory(Directory root) async {
    final names = ['workspace.sqlite', 'office-cert.pem', 'office-key.pem'];
    final evidence = Directory('${root.path}/evidence');
    if (await evidence.exists()) {
      await for (final item in evidence.list(followLinks: false)) {
        final name = item.uri.pathSegments.last;
        if (item is! File || !hashPattern.hasMatch(name)) {
          throw StateError('Invalid evidence file.');
        }
        names.add('evidence/$name');
      }
    }
    if (names.length > _maxFiles + 3) {
      throw StateError('Too many recovery files.');
    }
    names.sort();
    final files = <String, dynamic>{};
    var total = 0;
    for (final name in names) {
      final bytes = await _read(File('${root.path}/$name'), _limit(name));
      total += bytes.length;
      if (total > _maxTotalBytes) {
        throw StateError('Recovery exceeds lab limits.');
      }
      files[name] = {'hash': digest(bytes), 'size': bytes.length};
    }
    return files;
  }

  static Future<OfficeBackupSummary> _inspect(
    Directory root, {
    Json? manifest,
    OfficeBackupFormat? requiredFormat,
  }) async {
    if (await FileSystemEntity.type(root.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw StateError('Recovery requires an ordinary directory.');
    }
    manifest ??=
        jsonDecode(
              utf8.decode(
                await _read(
                  File('${root.path}/manifest.json'),
                  _maxManifestBytes,
                ),
              ),
            )
            as Json;
    if (manifest.keys.toSet().difference({
          'format',
          'version',
          'role',
          'createdAt',
          'device',
          'fingerprint',
          'files',
        }).isNotEmpty ||
        !((manifest['format'] == 'vortice-sync-lab-office' &&
                manifest['version'] == version) ||
            (manifest['format'] == 'maintenance-local-office' &&
                manifest['version'] == maintenanceVersion)) ||
        manifest['role'] != 'linux-office' ||
        manifest['createdAt'] is! String ||
        DateTime.tryParse(manifest['createdAt'] as String) == null ||
        manifest['fingerprint'] is! String ||
        !hashPattern.hasMatch(manifest['fingerprint'] as String) ||
        manifest['files'] is! Map) {
      throw StateError('Invalid backup manifest.');
    }
    if (requiredFormat != null) {
      final expected = switch (requiredFormat) {
        OfficeBackupFormat.syncLab => ('vortice-sync-lab-office', version),
        OfficeBackupFormat.maintenance => (
          'maintenance-local-office',
          maintenanceVersion,
        ),
      };
      if (manifest['format'] != expected.$1 ||
          manifest['version'] != expected.$2) {
        throw _WrongBackupFormat(
          requiredFormat == OfficeBackupFormat.maintenance
              ? 'Use a Local Maintenance office backup. Sync Lab backups cannot be restored here.'
              : 'Use a Sync Lab office backup for this compatibility operation.',
        );
      }
    }
    await for (final item in root.list(followLinks: false)) {
      final name = item.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (!{
            'manifest.json',
            'workspace.sqlite',
            'office-cert.pem',
            'office-key.pem',
            'evidence',
          }.contains(name) ||
          (name == 'evidence' ? item is! Directory : item is! File)) {
        throw StateError('Unexpected backup entry.');
      }
    }
    if (canonical(await _inventory(root)) != canonical(manifest['files'])) {
      throw StateError('Backup hashes failed.');
    }
    final fingerprint = await _identity(root);
    final facts = await _database(root);
    if (fingerprint != manifest['fingerprint'] ||
        facts.device != manifest['device'] ||
        facts.real != (manifest['format'] == 'maintenance-local-office')) {
      throw StateError('Office identity failed.');
    }
    return OfficeBackupSummary(
      directory: root,
      createdAt: manifest['createdAt'] as String,
      device: facts.device,
      fingerprint: fingerprint,
      submissions: facts.submissions,
      receipts: facts.receipts,
      evidenceFiles: (manifest['files'] as Map).keys
          .where((k) => (k as String).startsWith('evidence/'))
          .length,
      phonesToReconfirm: facts.active + facts.pending,
      revokedPhones: facts.revoked,
      invitationsToDiscard: facts.invites,
    );
  }

  static OfficeBackupSummary _relocate(OfficeBackupSummary s, Directory d) =>
      OfficeBackupSummary(
        directory: d,
        createdAt: s.createdAt,
        device: s.device,
        fingerprint: s.fingerprint,
        submissions: s.submissions,
        receipts: s.receipts,
        evidenceFiles: s.evidenceFiles,
        phonesToReconfirm: s.phonesToReconfirm,
        revokedPhones: s.revokedPhones,
        invitationsToDiscard: s.invitationsToDiscard,
      );

  static Future<String> _identity(Directory root) async {
    final cert = File('${root.path}/office-cert.pem'),
        key = File('${root.path}/office-key.pem');
    final pem = utf8.decode(await _read(cert, _maxIdentityBytes));
    await _read(key, _maxIdentityBytes);
    final match = RegExp(
      r'^\s*-----BEGIN CERTIFICATE-----([\s\S]+?)-----END CERTIFICATE-----\s*$',
    ).firstMatch(pem);
    if (match == null) throw StateError('Invalid office certificate.');
    final der = base64Decode(match.group(1)!.replaceAll(RegExp(r'\s'), ''));
    // Do not log OpenSSL output: it may describe private identity material.
    final publicCert = await Process.run('openssl', [
      'x509',
      '-in',
      cert.path,
      '-pubkey',
      '-noout',
    ]);
    final publicKey = await Process.run('openssl', [
      'pkey',
      '-in',
      key.path,
      '-pubout',
    ]);
    if (publicCert.exitCode != 0 ||
        publicKey.exitCode != 0 ||
        publicCert.stdout != publicKey.stdout) {
      throw StateError('Office key and certificate do not match.');
    }
    SecurityContext()
      ..useCertificateChain(cert.path)
      ..usePrivateKey(key.path);
    return digest(der);
  }

  static const _schema = {
    'settings':
        'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    'documents':
        'CREATE TABLE documents (id TEXT PRIMARY KEY, bytes BLOB NOT NULL)',
    'submissions':
        'CREATE TABLE submissions (id TEXT PRIMARY KEY, hash TEXT NOT NULL, payload TEXT NOT NULL, state TEXT NOT NULL)',
    'receipts':
        'CREATE TABLE receipts (id TEXT PRIMARY KEY, submission_id TEXT NOT NULL UNIQUE REFERENCES submissions(id), hash TEXT NOT NULL, payload TEXT NOT NULL)',
    'invites':
        'CREATE TABLE invites (hash TEXT PRIMARY KEY, expires TEXT NOT NULL, used_by TEXT)',
    'phones':
        'CREATE TABLE phones (id TEXT PRIMARY KEY, label TEXT NOT NULL, token_hash TEXT NOT NULL UNIQUE, status TEXT NOT NULL)',
    'events':
        'CREATE TABLE events (id INTEGER PRIMARY KEY, kind TEXT NOT NULL, payload TEXT NOT NULL)',
  };

  static String _sql(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  static bool _id(Object? v) => v is String && v.isNotEmpty && v.length <= 100;

  static Future<_Facts> _database(Directory root) async {
    final db = sqlite3.open(
      '${root.path}/workspace.sqlite',
      mode: OpenMode.readOnly,
    );
    try {
      final schemaVersion =
          db.select('PRAGMA user_version').single.values.single as int;
      if (schemaVersion != 0 && schemaVersion != 1 && schemaVersion != 2) {
        throw StateError('Unsupported office database version.');
      }
      if (db.select('PRAGMA quick_check').single.values.single != 'ok' ||
          db.select('PRAGMA foreign_key_check').isNotEmpty) {
        throw StateError('Database integrity failed.');
      }
      final objects = db.select('SELECT type,name,sql FROM sqlite_master');
      final tables = objects.where((r) => r['type'] == 'table').toList();
      if (tables.length != _schema.length ||
          objects.any(
            (r) =>
                r['type'] != 'table' &&
                !(r['type'] == 'index' &&
                    r['sql'] == null &&
                    (r['name'] as String).startsWith('sqlite_autoindex_')),
          )) {
        throw StateError('Unsupported database schema.');
      }
      for (final row in tables) {
        if (_schema[row['name']] == null ||
            _sql(row['sql'] as String) != _sql(_schema[row['name']]!)) {
          throw StateError('Unsupported database table.');
        }
      }
      final settings = <String, dynamic>{};
      for (final row in db.select('SELECT * FROM settings')) {
        settings[row['key'] as String] = jsonDecode(row['value'] as String);
      }
      if (!_id(settings['device']) || settings.containsKey('pairing')) {
        throw StateError('Not an office authority.');
      }
      final catalog = settings['catalog'];
      final real = catalog != null;
      if ((settings.containsKey('localMaintenanceApplication') ||
              settings.containsKey('localMaintenanceRole')) &&
          (!real ||
              settings['localMaintenanceApplication'] !=
                  'org.vortice.next.maintenance_local' ||
              settings['localMaintenanceRole'] != 'linux-office')) {
        throw StateError('This is not a Local Maintenance office workspace.');
      }
      Json? workspace;
      if (real) {
        if (catalog is! Json ||
            settings['workspace'] != null ||
            schemaVersion != 2) {
          throw StateError('Invalid company database format.');
        }
        validateCatalog(catalog);
      } else {
        workspace = settings['workspace'] as Json?;
        if (schemaVersion == 2 ||
            workspace == null ||
            workspace.keys.toSet().length != 5 ||
            !{
              'companyId',
              'jobId',
              'company',
              'equipment',
              'job',
            }.every((k) => _id(workspace![k]))) {
          throw StateError('Invalid office workspace.');
        }
      }
      final documents = db.select('SELECT * FROM documents');
      final jobIds = real
          ? (catalog['jobs'] as List)
                .map((j) => (j as Map)['id'] as String)
                .toSet()
          : {'inspection'};
      if (documents.length != jobIds.length ||
          documents.any((d) => !jobIds.contains(d['id']))) {
        throw StateError('Missing prepared-work document.');
      }
      if (settings['officeFingerprint'] != null &&
          settings['officeFingerprint'] != await _identity(root)) {
        throw StateError(
          'Saved office fingerprint differs from its certificate.',
        );
      }
      final required = <String>{};
      for (final row in documents) {
        final bytes = row['bytes'] as Uint8List;
        if (bytes.isEmpty || bytes.length > 16 * 1024 * 1024) {
          throw StateError('Invalid work history size.');
        }
        final view = jsonDecode(await documentValues(bytes: bytes)) as Json;
        if (real) {
          validateJobDocument(
            view,
            jobContext(catalog as Json, row['id'] as String),
          );
        } else {
          validateDocument(view);
        }
        required.addAll((view['photo'] as List).whereType<String>());
      }
      final phoneRows = db.select('SELECT * FROM phones');
      var active = 0, pending = 0, revoked = 0;
      final devices = <String>{settings['device'] as String};
      for (final row in phoneRows) {
        if (!_id(row['id']) ||
            row['id'] == settings['device'] ||
            row['label'] is! String ||
            (row['label'] as String).isEmpty ||
            (row['label'] as String).length > 80 ||
            row['token_hash'] is! String ||
            !hashPattern.hasMatch(row['token_hash'] as String)) {
          throw StateError('Invalid device authority.');
        }
        devices.add(row['id'] as String);
        switch (row['status']) {
          case 'active':
            active++;
          case 'pending':
            pending++;
          case 'revoked':
            revoked++;
          default:
            throw StateError('Invalid device status.');
        }
      }
      final invites = db.select('SELECT * FROM invites');
      for (final row in invites) {
        if (row['hash'] is! String ||
            !hashPattern.hasMatch(row['hash'] as String) ||
            row['expires'] is! String ||
            DateTime.tryParse(row['expires'] as String) == null ||
            (row['used_by'] != null && !devices.contains(row['used_by']))) {
          throw StateError('Invalid invitation authority.');
        }
      }
      final submissions = db.select('SELECT * FROM submissions');
      final submitted = <String, Json>{};
      for (final row in submissions) {
        final payload = jsonDecode(row['payload'] as String) as Json;
        await ApprovalRules.validateSubmission(
          payload,
          real
              ? jobContext(catalog as Json, payload['jobId'] as String)
              : workspace,
        );
        if (row['id'] != payload['id'] ||
            row['hash'] != contentHash(payload) ||
            row['state'] != 'received' ||
            !devices.contains(payload['device'])) {
          throw StateError('Invalid submitted identity.');
        }
        submitted[row['id'] as String] = payload;
        required.add((payload['values'] as Json)['photo'] as String);
      }
      if (real) ApprovalRules.validateSubmissionHistory(submitted.values);
      final receipts = db.select('SELECT * FROM receipts');
      for (final row in receipts) {
        final p = jsonDecode(row['payload'] as String) as Json;
        final sub = submitted[row['submission_id']];
        if (sub == null ||
            p['id'] != row['id'] ||
            p['submissionId'] != row['submission_id'] ||
            row['hash'] != contentHash(p)) {
          throw StateError('Invalid immutable decision.');
        }
        ApprovalRules.validateReceipt(
          p,
          sub,
          workspace: real
              ? jobContext(catalog as Json, sub['jobId'] as String)
              : workspace,
        );
        if (real && p['reviewerDevice'] != settings['device']) {
          throw StateError('Decision belongs to a different office authority.');
        }
      }
      final evidence = EvidenceStore(Directory('${root.path}/evidence'));
      for (final hash in required) {
        if (!await evidence.complete(hash)) {
          throw StateError('Required evidence is incomplete.');
        }
      }
      final noteReviews = <Json>[];
      for (final row in db.select('SELECT * FROM events')) {
        if (row['kind'] is! String ||
            jsonDecode(row['payload'] as String) is! Map) {
          throw StateError('Invalid event history.');
        }
        if (row['kind'] == notesReviewEvent) {
          noteReviews.add(jsonDecode(row['payload'] as String) as Json);
        }
      }
      if (noteReviews.isNotEmpty) {
        if (!real) throw StateError('Invalid suggestion review history.');
        validateNotesReviewHistory(
          noteReviews,
          companyId: (catalog as Json)['companyId'] as String,
          reviewerDevice: settings['device'] as String,
        );
        for (final review in noteReviews) {
          final proposal = NotesProposal.fromRecord(review['proposal'] as Json);
          if (canonical(jobContext(catalog, proposal.jobId)) !=
              canonical(proposal.context)) {
            throw StateError('Invalid suggestion review context.');
          }
        }
      }
      return _Facts(
        settings['device'] as String,
        submissions.length,
        receipts.length,
        active,
        pending,
        revoked,
        invites.length,
        real,
      );
    } finally {
      db.close();
    }
  }
}

class _Facts {
  const _Facts(
    this.device,
    this.submissions,
    this.receipts,
    this.active,
    this.pending,
    this.revoked,
    this.invites,
    this.real,
  );
  final String device;
  final bool real;
  final int submissions, receipts, active, pending, revoked, invites;
}
