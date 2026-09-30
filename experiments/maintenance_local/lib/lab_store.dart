import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';
import 'evidence_store.dart';
import 'approval_rules.dart';
import 'model.dart';
import 'src/rust/api/documents.dart';

/// This store owns a single synthetic company. Membership secrets never leave it.
class LabStore {
  LabStore._(this.root, this.office, this.db, this.now)
    : evidence = EvidenceStore(Directory('${root.path}/evidence'));
  final Directory root;
  final bool office;
  final Database db;
  final DateTime Function() now;
  final EvidenceStore evidence;
  final queue = SerialQueue();

  static Future<LabStore> open(
    Directory root, {
    required bool office,
    DateTime Function()? now,
  }) async {
    await root.create(recursive: true);
    if (Platform.isLinux) await Process.run('chmod', ['700', root.path]);
    final db = sqlite3.open('${root.path}/workspace.sqlite');
    final version = db.select('PRAGMA user_version').first.values.first as int;
    if (version > 1) {
      db.close();
      throw StateError(
        'This workspace was saved by a newer Sync Lab. Its files have been retained. Open it with the matching or newer version.',
      );
    }
    db.execute('PRAGMA journal_mode=WAL');
    db.execute('PRAGMA synchronous=FULL');
    db.execute('PRAGMA foreign_keys=ON');
    db.execute(
      '''CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS documents (id TEXT PRIMARY KEY, bytes BLOB NOT NULL);
      CREATE TABLE IF NOT EXISTS submissions (id TEXT PRIMARY KEY, hash TEXT NOT NULL, payload TEXT NOT NULL, state TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS receipts (id TEXT PRIMARY KEY, submission_id TEXT NOT NULL UNIQUE REFERENCES submissions(id), hash TEXT NOT NULL, payload TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS invites (hash TEXT PRIMARY KEY, expires TEXT NOT NULL, used_by TEXT);
      CREATE TABLE IF NOT EXISTS phones (id TEXT PRIMARY KEY, label TEXT NOT NULL, token_hash TEXT NOT NULL UNIQUE, status TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS events (id INTEGER PRIMARY KEY, kind TEXT NOT NULL, payload TEXT NOT NULL);
    ''',
    );
    db.execute('PRAGMA user_version=1');
    final store = LabStore._(root, office, db, now ?? DateTime.now);
    if (store.setting('device') == null) {
      store.setSetting('device', const Uuid().v4());
    }
    return store;
  }

  String get device => setting('device') as String;
  String stamp() => now().toUtc().toIso8601String();
  dynamic setting(String key) {
    final rows = db.select('SELECT value FROM settings WHERE key=?', [key]);
    return rows.isEmpty ? null : jsonDecode(rows.first['value'] as String);
  }

  void setSetting(String key, Object? value) => db.execute(
    'INSERT INTO settings VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',
    [key, canonical(value)],
  );
  Json? get workspace => setting('workspace') as Json?;
  Uint8List? get document {
    final rows = db.select("SELECT bytes FROM documents WHERE id='inspection'");
    return rows.isEmpty ? null : rows.first['bytes'] as Uint8List;
  }

  void saveDocument(Uint8List bytes) => db.execute(
    "INSERT INTO documents VALUES ('inspection',?) ON CONFLICT(id) DO UPDATE SET bytes=excluded.bytes",
    [bytes],
  );
  void transaction(void Function() action) {
    db.execute('BEGIN IMMEDIATE');
    try {
      action();
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  void event(String kind, Json data) => db.execute(
    'INSERT INTO events(kind,payload) VALUES (?,?)',
    [kind, canonical(data)],
  );
  void requireOffice() {
    if (!office) throw StateError('Only the office computer can do this.');
  }

  Future<void> createWorkspace() => queue.run(() async {
    requireOffice();
    if (workspace != null) return;
    final meta = {
      'companyId': const Uuid().v4(),
      'jobId': const Uuid().v4(),
      'company': 'Demo maintenance company',
      'equipment': 'Demo generator',
      'job': 'Daily equipment inspection',
    };
    final bytes = await createDocument(
      actor: device,
      fieldsJson: canonical(initialFields),
    );
    transaction(() {
      setSetting('workspace', meta);
      saveDocument(bytes);
      event('created', meta);
    });
  });

  Future<Json> fields() async => document == null
      ? {}
      : jsonDecode(await documentValues(bytes: document!)) as Json;
  Future<void> update(Json patch, {Uint8List? base}) => queue.run(() async {
    if (document == null) throw StateError('Connect to the company first.');
    final edited = await editDocument(
      bytes: base ?? document!,
      actor: base == null ? device : '$device:${const Uuid().v4()}',
      fieldsJson: canonical(patch),
    );
    final updated = base == null
        ? edited
        : await mergeDocuments(left: document!, right: edited);
    final view = jsonDecode(await documentValues(bytes: updated)) as Json;
    validateDocument(view);
    transaction(() {
      saveDocument(updated);
      setSetting('savedAt', stamp());
      event('edited', {'fields': patch.keys.toList()});
    });
  });

  Future<String> attach(List<int> bytes) async {
    final hash = await evidence.add(bytes);
    await update({'photo': hash});
    return hash;
  }

  List<Json> get submissions => db
      .select('SELECT payload,state FROM submissions ORDER BY rowid')
      .map(
        (r) => {
          ...jsonDecode(r['payload'] as String) as Json,
          '_state': r['state'],
        },
      )
      .toList();
  List<Json> get receipts => db
      .select('SELECT payload FROM receipts ORDER BY rowid')
      .map((r) => jsonDecode(r['payload'] as String) as Json)
      .toList();

  Future<Json> submit() => queue.run(() async {
    final view = await fields();
    final problem = incomplete(view);
    if (problem != null) throw StateError(problem);
    if (!await evidence.complete(valuesOf(view)['photo'] as String)) {
      throw StateError('Save the complete photo first.');
    }
    final version = digest(document!);
    final prior = submissions
        .where((p) => p['documentHash'] == version && p['device'] == device)
        .firstOrNull;
    if (prior != null) {
      return Map<String, dynamic>.from(prior)..remove('_state');
    }
    final payload = <String, dynamic>{
      'id': const Uuid().v4(),
      'companyId': workspace!['companyId'],
      'jobId': workspace!['jobId'],
      'device': device,
      'createdAt': stamp(),
      'document': base64Encode(document!),
      'documentHash': version,
      'values': valuesOf(view),
    };
    transaction(() {
      _saveSubmission(payload, office ? 'received' : 'queued');
      event('submitted', {'id': payload['id']});
    });
    return payload;
  });

  void _saveSubmission(Json payload, String state) {
    final existing = db.select('SELECT hash FROM submissions WHERE id=?', [
      payload['id'],
    ]);
    final hash = contentHash(payload);
    if (existing.isNotEmpty && existing.first['hash'] != hash) {
      throw StateError('Submission identity reused with changed content.');
    }
    db.execute(
      'INSERT INTO submissions VALUES (?,?,?,?) ON CONFLICT(id) DO UPDATE SET state=excluded.state',
      [payload['id'], hash, canonical(payload), state],
    );
  }

  Future<void> validateSubmission(Json p) =>
      ApprovalRules.validateSubmission(p, workspace);

  Future<void> acceptSubmission(
    Json payload,
    String authenticatedDevice, {
    void Function()? checkAuthority,
  }) => queue.run(() async {
    requireOffice();
    checkAuthority?.call();
    if (payload['device'] != authenticatedDevice) {
      throw StateError('Submission device does not match this connection.');
    }
    await validateSubmission(payload);
    checkAuthority?.call();
    transaction(() => _saveSubmission(payload, 'received'));
  });

  Future<String?> approvalProblem(Json submission) async =>
      ApprovalRules.problem(
        submission: submission,
        workspace: workspace,
        current: await fields(),
        completeEvidence: evidence.complete,
      );

  Future<Json> decide(
    String id, {
    required bool approve,
    String reason = '',
  }) => queue.run(() async {
    requireOffice();
    final rows = db.select('SELECT payload FROM submissions WHERE id=?', [id]);
    if (rows.isEmpty) throw StateError('Submission not found.');
    final submission = jsonDecode(rows.first['payload'] as String) as Json;
    final prior = receipts.where((r) => r['submissionId'] == id).firstOrNull;
    if (prior != null) {
      if (prior['decision'] == (approve ? 'approved' : 'returned') &&
          prior['reason'] == reason.trim()) {
        return prior;
      }
      throw StateError(
        'This version already has an immutable decision. Submit a new version.',
      );
    }
    if (!approve && reason.trim().isEmpty) {
      throw StateError('Explain what needs to change.');
    }
    if (approve) {
      final problem = await approvalProblem(submission);
      if (problem != null) throw StateError(problem);
    }
    final receipt = <String, dynamic>{
      'id': const Uuid().v4(),
      'submissionId': id,
      'submissionHash': contentHash(submission),
      'decision': approve ? 'approved' : 'returned',
      'reason': reason.trim(),
      'reviewedAt': stamp(),
      'reviewedBy': 'Office owner',
      'values': submission['values'],
    };
    transaction(() {
      _saveReceipt(receipt);
      event('reviewed', receipt);
    });
    return receipt;
  });

  void _saveReceipt(Json r) {
    final rows = db.select(
      'SELECT hash FROM receipts WHERE id=? OR submission_id=?',
      [r['id'], r['submissionId']],
    );
    if (rows.isNotEmpty && rows.first['hash'] != contentHash(r)) {
      throw StateError('Approved history cannot be replaced.');
    }
    final sub = db.select('SELECT hash FROM submissions WHERE id=?', [
      r['submissionId'],
    ]);
    if (sub.isEmpty || sub.first['hash'] != r['submissionHash']) {
      throw StateError('Decision does not match its submitted version.');
    }
    db.execute('INSERT OR IGNORE INTO receipts VALUES (?,?,?,?)', [
      r['id'],
      r['submissionId'],
      contentHash(r),
      canonical(r),
    ]);
  }

  Future<Set<String>> requiredEvidence() async {
    final view = await fields();
    return {
      ...((view['photo'] as List?) ?? []).whereType<String>(),
      for (final p in submissions) (p['values'] as Json)['photo'] as String,
    };
  }

  Future<Json> publicBundle() async => {
    'workspace': workspace,
    'document': base64Encode(document!),
    'submissions': submissions
        .map((p) => Map<String, dynamic>.from(p)..remove('_state'))
        .toList(),
    'receipts': receipts,
    'blobs': await evidence.manifest(),
    'savedAt': stamp(),
  };

  /// Caller must have authenticated the paired office TLS endpoint.
  Future<void> importOfficeBundle(Json bundle) => queue.run(() async {
    if (office) {
      throw StateError('An office cannot import another device authority.');
    }
    final meta = bundle['workspace'] as Json;
    if (workspace != null && workspace!['companyId'] != meta['companyId']) {
      throw StateError('Different company. Existing work is retained.');
    }
    final incoming = base64Decode(bundle['document'] as String);
    final merged = document == null
        ? incoming
        : await mergeDocuments(left: document!, right: incoming);
    validateDocument(jsonDecode(await documentValues(bytes: merged)) as Json);
    for (final p in bundle['submissions'] as List) {
      await ApprovalRules.validateSubmission(
        Map<String, dynamic>.from(p as Map),
        meta,
      );
    }
    transaction(() {
      setSetting('workspace', meta);
      saveDocument(merged);
      for (final p in bundle['submissions'] as List) {
        _saveSubmission(Map<String, dynamic>.from(p as Map), 'received');
      }
      for (final r in bundle['receipts'] as List) {
        _saveReceipt(Map<String, dynamic>.from(r as Map));
      }
    });
  });

  Future<void> close() async {
    await queue.idle;
    db.close();
  }
}
