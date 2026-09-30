import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';
import 'evidence_store.dart';
import 'approval_rules.dart';
import 'model.dart';
import 'maintenance_domain.dart';
import 'src/rust/api/documents.dart';

/// Company storage and durable capture. Office authority never enters documents.
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
    bool maintenanceOnly = false,
  }) async {
    final needsOwner = maintenanceOnly
        ? await _maintenanceLocation(root, office: office)
        : false;
    await root.create(recursive: true);
    if (Platform.isLinux) await Process.run('chmod', ['700', root.path]);
    if (needsOwner) {
      final owner = File('${root.path}/maintenance-local-owner.json');
      // Publish app ownership before database initialization so an interrupted
      // first launch remains recognizable without inspecting a foreign DB.
      await owner.writeAsString(
        canonical(_maintenanceOwner(office: office)),
        flush: true,
      );
      if (Platform.isLinux) await Process.run('chmod', ['600', owner.path]);
    }
    final db = sqlite3.open('${root.path}/workspace.sqlite');
    final version = db.select('PRAGMA user_version').first.values.first as int;
    if (version > 2) {
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
    if (version == 0) db.execute('PRAGMA user_version=1');
    final store = LabStore._(root, office, db, now ?? DateTime.now);
    if (store.setting('device') == null) {
      store.setSetting('device', const Uuid().v4());
    }
    if (maintenanceOnly) {
      store.setSetting(
        'localMaintenanceApplication',
        'org.vortice.next.maintenance_local',
      );
      store.setSetting(
        'localMaintenanceRole',
        office ? 'linux-office' : 'mechanic-phone',
      );
    }
    return store;
  }

  /// Normal startup must never adopt another application's directory. Inspect
  /// existing ownership before chmod, journal setup, schema or identity writes.
  /// Even SQLite read-only opens can create WAL/SHM sidecars, so ownership is
  /// checked without opening the database at all.
  /// Legacy runtime fixtures deliberately use the compatibility API instead.
  static Json _maintenanceOwner({required bool office}) => {
    'application': 'org.vortice.next.maintenance_local',
    'role': office ? 'linux-office' : 'mechanic-phone',
    'version': 1,
  };

  static Future<bool> _maintenanceLocation(
    Directory root, {
    required bool office,
  }) async {
    const retained =
        'This folder does not belong to this local maintenance app and device role. '
        'Choose a new empty folder or restore a verified maintenance backup. Existing files were retained.';
    final kind = await FileSystemEntity.type(root.path, followLinks: false);
    if (kind == FileSystemEntityType.notFound) return true;
    if (kind != FileSystemEntityType.directory) throw StateError(retained);
    if (await root.list(followLinks: false).isEmpty) return true;
    final owner = File('${root.path}/maintenance-local-owner.json');
    if (await FileSystemEntity.type(owner.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw StateError(retained);
    }
    try {
      if (await owner.length() > 512 ||
          canonical(jsonDecode(await owner.readAsString())) !=
              canonical(_maintenanceOwner(office: office))) {
        throw StateError(retained);
      }
      return false;
    } catch (_) {
      throw StateError(retained);
    }
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
  Json? get catalog => setting('catalog') as Json?;
  bool get realWorkspace => catalog != null;
  List<Json> _catalogRows(String key) => (catalog?[key] as List? ?? [])
      .map((r) => Map<String, dynamic>.from(r as Map))
      .toList();
  List<Json> get equipment => _catalogRows('equipment');
  List<Json> get templates => _catalogRows('templates');
  List<Json> get jobs => _catalogRows('jobs');
  String? get activeJobId {
    if (!realWorkspace) return workspace?['jobId'] as String?;
    final selected = setting('activeJobId');
    if (selected is String && jobs.any((j) => j['id'] == selected)) {
      return selected;
    }
    return jobs.firstOrNull?['id'] as String?;
  }

  void selectJob(String id) {
    jobContextFor(id);
    setSetting('activeJobId', id);
  }

  Json jobContextFor(String id) {
    if (!realWorkspace) {
      final meta = setting('workspace') as Json?;
      if (meta == null || meta['jobId'] != id) {
        throw StateError('Work order not found.');
      }
      return meta;
    }
    return jobContext(catalog!, id);
  }

  Json? get workspace {
    if (!realWorkspace) return setting('workspace') as Json?;
    final id = activeJobId;
    return id == null
        ? {'companyId': catalog!['companyId'], 'company': catalog!['company']}
        : jobContextFor(id);
  }

  String _documentId(String? jobId) {
    if (!realWorkspace) {
      if (jobId != null && workspace?['jobId'] != jobId) {
        throw StateError('Work order not found.');
      }
      return 'inspection';
    }
    final id = jobId ?? activeJobId;
    if (id == null) throw StateError('Prepare a work order first.');
    jobContextFor(id);
    return id;
  }

  Uint8List? documentFor(String id) {
    final key = _documentId(id);
    final rows = db.select('SELECT bytes FROM documents WHERE id=?', [key]);
    return rows.isEmpty ? null : rows.first['bytes'] as Uint8List;
  }

  Uint8List? get document {
    if (realWorkspace && activeJobId == null) return null;
    final rows = db.select('SELECT bytes FROM documents WHERE id=?', [
      _documentId(null),
    ]);
    return rows.isEmpty ? null : rows.first['bytes'] as Uint8List;
  }

  void saveDocument(Uint8List bytes, {String? jobId}) {
    if (bytes.isEmpty || bytes.length > 16 * 1024 * 1024) {
      throw StateError(
        'Work history exceeds the supported local document size.',
      );
    }
    db.execute(
      'INSERT INTO documents VALUES (?,?) ON CONFLICT(id) DO UPDATE SET bytes=excluded.bytes',
      [_documentId(jobId), bytes],
    );
  }

  void validateFields(Json alternatives, {String? jobId}) {
    if (realWorkspace) {
      validateJobDocument(alternatives, jobContextFor(jobId ?? activeJobId!));
    } else {
      validateDocument(alternatives);
    }
  }

  String? submissionProblem(Json alternatives, {String? jobId}) => realWorkspace
      ? incompleteJob(alternatives, jobContextFor(jobId ?? activeJobId!))
      : incomplete(alternatives);

  Future<void> createCompany(
    String name, {
    String coordinatorName = 'Office coordinator',
  }) => queue.run(() async {
    requireOffice();
    if (catalog != null || setting('workspace') != null) {
      throw StateError('This workspace already has a company.');
    }
    final next = makeCatalog(
      id: const Uuid().v4(),
      name: name,
      coordinatorName: coordinatorName,
    );
    validateCatalog(next);
    transaction(() {
      setSetting('catalog', next);
      db.execute('PRAGMA user_version=2');
      event('company-created', {'companyId': next['companyId']});
    });
  });
  Future<Json> addEquipment({
    required String name,
    String serial = '',
    String meterUnit = 'hours',
  }) => queue.run(() async {
    requireOffice();
    final next = catalog;
    if (next == null) throw StateError('Create a company first.');
    final item = makeEquipment(
      id: const Uuid().v4(),
      name: name,
      serial: serial,
      meterUnit: meterUnit,
    );
    (next['equipment'] as List).add(item);
    validateCatalog(next);
    transaction(() {
      setSetting('catalog', next);
      event('equipment-created', {'id': item['id']});
    });
    return item;
  });
  Future<Json> publishChecklist({
    required String title,
    required List<Json> items,
    Json? provenance,
  }) => queue.run(() async {
    requireOffice();
    final next = catalog;
    if (next == null) throw StateError('Create a company first.');
    final template = makeTemplate(
      id: const Uuid().v4(),
      title: title,
      items: items,
      provenance: provenance ?? {'kind': 'company-authored'},
    );
    (next['templates'] as List).add(template);
    validateCatalog(next);
    transaction(() {
      setSetting('catalog', next);
      event('checklist-published', {
        'id': template['id'],
        'hash': template['hash'],
      });
    });
    return template;
  });
  Future<Json> prepareWork({
    required String equipmentId,
    required String templateId,
    required String title,
  }) => queue.run(() async {
    requireOffice();
    final next = catalog;
    if (next == null) throw StateError('Create a company first.');
    final asset = equipment.where((e) => e['id'] == equipmentId).firstOrNull;
    final template = templates.where((e) => e['id'] == templateId).firstOrNull;
    if (asset == null || template == null) {
      throw StateError('Select existing equipment and a published checklist.');
    }
    final job = makeJob(
      id: const Uuid().v4(),
      title: title,
      equipment: asset,
      template: template,
    );
    (next['jobs'] as List).add(job);
    validateCatalog(next);
    final context = jobContext(next, job['id'] as String);
    final bytes = await createDocument(
      actor: '$device:${job['id']}',
      fieldsJson: canonical(initialJobFields(context)),
    );
    validateJobDocument(
      jsonDecode(await documentValues(bytes: bytes)) as Json,
      context,
    );
    transaction(() {
      setSetting('catalog', next);
      saveDocument(bytes, jobId: job['id'] as String);
      setSetting('activeJobId', job['id']);
      event('work-prepared', {
        'id': job['id'],
        'snapshotHash': job['snapshotHash'],
      });
    });
    return job;
  });
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
    if (realWorkspace) {
      throw StateError('Use prepared work orders in this company.');
    }
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

  Future<Json> fields({String? jobId}) async {
    final bytes = jobId == null ? document : documentFor(jobId);
    return bytes == null
        ? {}
        : jsonDecode(await documentValues(bytes: bytes)) as Json;
  }

  Future<void> update(Json patch, {Uint8List? base, String? jobId}) =>
      queue.run(() async {
        final id = _documentId(jobId);
        if (realWorkspace && patch.keys.any((key) => key.startsWith('_'))) {
          throw StateError('Work-order identity cannot be edited.');
        }
        final bytes = realWorkspace ? documentFor(id) : document;
        if (bytes == null) throw StateError('Connect to the company first.');
        final edited = await editDocument(
          bytes: base ?? bytes,
          actor: base == null ? device : '$device:${const Uuid().v4()}',
          fieldsJson: canonical(patch),
        );
        final updated = base == null
            ? edited
            : await mergeDocuments(left: bytes, right: edited);
        final view = jsonDecode(await documentValues(bytes: updated)) as Json;
        validateFields(view, jobId: realWorkspace ? id : null);
        transaction(() {
          saveDocument(updated, jobId: realWorkspace ? id : null);
          setSetting('savedAt', stamp());
          event('edited', {
            'jobId': realWorkspace ? id : workspace?['jobId'],
            'fields': patch.keys.toList(),
          });
        });
      });
  Future<String> attach(List<int> bytes, {String? jobId}) async {
    final hash = await evidence.add(bytes);
    await update({'photo': hash}, jobId: jobId);
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

  Future<Json> submit({String? jobId}) => queue.run(() async {
    final id = realWorkspace ? _documentId(jobId) : null;
    final context = realWorkspace ? jobContextFor(id!) : workspace!;
    final bytes = realWorkspace ? documentFor(id!)! : document!;
    final view = await fields(jobId: id);
    final problem = submissionProblem(view, jobId: id);
    if (problem != null) throw StateError(problem);
    if (!await evidence.complete(valuesOf(view)['photo'] as String)) {
      throw StateError('Save the complete photo first.');
    }
    final version = digest(bytes);
    final prior = submissions
        .where(
          (p) =>
              p['documentHash'] == version &&
              p['device'] == device &&
              p['jobId'] == context['jobId'],
        )
        .firstOrNull;
    if (prior != null) {
      return Map<String, dynamic>.from(prior)..remove('_state');
    }
    final payload = <String, dynamic>{
      'id': const Uuid().v4(),
      'companyId': context['companyId'],
      'jobId': context['jobId'],
      'device': device,
      'createdAt': stamp(),
      'document': base64Encode(bytes),
      'documentHash': version,
      'values': valuesOf(view),
      if (realWorkspace) ...{
        'schemaVersion': 1,
        'equipmentId': context['equipmentId'],
        'snapshotHash': context['snapshotHash'],
        'revision': context['revision'],
        'context': context,
        'submissionRevision':
            _previousSubmission(
                  context['jobId'] as String,
                  device,
                )?['submissionRevision'] ==
                null
            ? 1
            : (_previousSubmission(
                        context['jobId'] as String,
                        device,
                      )!['submissionRevision']
                      as int) +
                  1,
        'predecessorId': _previousSubmission(
          context['jobId'] as String,
          device,
        )?['id'],
      },
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

  Json? _previousSubmission(String jobId, String actor) => submissions
      .where((p) => p['jobId'] == jobId && p['device'] == actor)
      .lastOrNull;

  void _checkSubmissionChain(Json p) {
    if (!realWorkspace) return;
    final existing = submissions.where((s) => s['id'] == p['id']).firstOrNull;
    if (existing != null) return;
    if (submissions.any(
      (s) =>
          s['device'] == p['device'] &&
          s['jobId'] == p['jobId'] &&
          s['documentHash'] == p['documentHash'],
    )) {
      throw StateError(
        'This document version already has a submitted record. Retry its original submission or save changed work before submitting a new version.',
      );
    }
    final prior = _previousSubmission(
      p['jobId'] as String,
      p['device'] as String,
    );
    if (p['predecessorId'] != prior?['id'] ||
        p['submissionRevision'] !=
            (prior == null ? 1 : (prior['submissionRevision'] as int) + 1)) {
      throw StateError(
        'Submission revision does not follow this device’s saved work.',
      );
    }
  }

  Future<void> validateSubmission(Json p) => ApprovalRules.validateSubmission(
    p,
    realWorkspace ? jobContextFor(p['jobId'] as String) : workspace,
  );

  Future<void> acceptSubmission(
    Json payload,
    String authenticatedDevice, {
    void Function()? checkAuthority,
  }) => queue.run(() async {
    requireOffice();
    checkAuthority?.call();
    if (payload.containsKey('_state')) {
      throw StateError(
        'Local send status cannot be submitted. Retry the original submission without local status metadata; saved work has been retained.',
      );
    }
    if (payload['device'] != authenticatedDevice) {
      throw StateError('Submission device does not match this connection.');
    }
    await validateSubmission(payload);
    checkAuthority?.call();
    transaction(() {
      _checkSubmissionChain(payload);
      _saveSubmission(payload, 'received');
    });
  });

  Future<String?> approvalProblem(Json submission) async =>
      ApprovalRules.problem(
        submission: submission,
        workspace: realWorkspace
            ? jobContextFor(submission['jobId'] as String)
            : workspace,
        current: await fields(
          jobId: realWorkspace ? submission['jobId'] as String : null,
        ),
        currentDocumentHash: realWorkspace
            ? digest(documentFor(submission['jobId'] as String)!)
            : null,
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
      'reviewedBy': realWorkspace
          ? catalog!['coordinatorName']
          : 'Office owner',
      if (realWorkspace) 'reviewerDevice': device,
      'values': submission['values'],
    };
    transaction(() {
      _saveReceipt(receipt);
      event('reviewed', receipt);
    });
    return receipt;
  });

  void _saveReceipt(Json r) {
    final submittedRows = db.select(
      'SELECT payload FROM submissions WHERE id=?',
      [r['submissionId']],
    );
    if (submittedRows.isEmpty) {
      throw StateError('Decision does not match its submitted version.');
    }
    final submitted =
        jsonDecode(submittedRows.single['payload'] as String) as Json;
    ApprovalRules.validateReceipt(
      r,
      submitted,
      workspace: realWorkspace
          ? jobContextFor(submitted['jobId'] as String)
          : workspace,
    );
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
    final required = <String>{};
    if (realWorkspace) {
      for (final job in jobs) {
        final view = await fields(jobId: job['id'] as String);
        required.addAll(((view['photo'] as List?) ?? []).whereType<String>());
      }
    } else {
      final view = await fields();
      required.addAll(((view['photo'] as List?) ?? []).whereType<String>());
    }
    for (final p in submissions) {
      required.add((p['values'] as Json)['photo'] as String);
    }
    return required;
  }

  Future<Json> publicBundle() async {
    final required = realWorkspace ? await requiredEvidence() : <String>{};
    return {
      if (realWorkspace) ...{
        'format': 'maintenance-local-company',
        'version': 1,
        'catalog': catalog,
        'officeDevice': device,
        'documents': {
          for (final job in jobs)
            job['id'] as String: base64Encode(
              documentFor(job['id'] as String)!,
            ),
        },
      } else ...{
        'workspace': workspace,
        'document': base64Encode(document!),
      },
      'submissions': submissions
          .map((p) => Map<String, dynamic>.from(p)..remove('_state'))
          .toList(),
      'receipts': receipts,
      'blobs': (await evidence.manifest())
          .where((b) => !realWorkspace || required.contains(b['hash']))
          .toList(),
      'savedAt': stamp(),
    };
  }

  /// Caller must have authenticated the pinned office endpoint. No phone authority is imported.
  Future<void> importOfficeBundle(Json bundle) => queue.run(() async {
    if (office) {
      throw StateError('An office cannot import another device authority.');
    }
    if (bundle.containsKey('catalog')) {
      await _importCompanyBundle(bundle);
      return;
    }
    if (realWorkspace) {
      throw StateError(
        'Unsupported company bundle. Saved work has been retained.',
      );
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
    final submitted = <String, Json>{
      for (final p in submissions)
        p['id'] as String: Map<String, dynamic>.from(p)..remove('_state'),
    };
    for (final p in bundle['submissions'] as List) {
      final payload = Map<String, dynamic>.from(p as Map);
      await ApprovalRules.validateSubmission(payload, meta);
      submitted[payload['id'] as String] = payload;
    }
    for (final r in bundle['receipts'] as List) {
      final receipt = Map<String, dynamic>.from(r as Map);
      final p = submitted[receipt['submissionId']];
      if (p == null) throw StateError('Decision lacks its submitted version.');
      ApprovalRules.validateReceipt(receipt, p, workspace: meta);
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

  Future<void> _importCompanyBundle(Json bundle) async {
    if (bundle['format'] != 'maintenance-local-company' ||
        bundle['version'] != 1 ||
        bundle.keys.toSet().difference({
          'format',
          'version',
          'catalog',
          'officeDevice',
          'documents',
          'submissions',
          'receipts',
          'blobs',
          'savedAt',
        }).isNotEmpty ||
        bundle['catalog'] is! Json ||
        bundle['documents'] is! Map ||
        bundle['submissions'] is! List ||
        bundle['receipts'] is! List ||
        bundle['officeDevice'] is! String ||
        (bundle['officeDevice'] as String).isEmpty ||
        (bundle['officeDevice'] as String).length > 100 ||
        bundle['blobs'] is! List ||
        bundle['savedAt'] is! String ||
        DateTime.tryParse(bundle['savedAt'] as String) == null) {
      throw StateError(
        'Unsupported company bundle. Saved work has been retained.',
      );
    }
    final blobIds = <String>{};
    for (final blob in bundle['blobs'] as List) {
      if (blob is! Json ||
          blob.keys.toSet().length != 2 ||
          blob['hash'] is! String ||
          !hashPattern.hasMatch(blob['hash'] as String) ||
          blob['size'] is! int ||
          (blob['size'] as int) < 1 ||
          (blob['size'] as int) > EvidenceStore.maxBytes ||
          !blobIds.add(blob['hash'] as String)) {
        throw StateError('Invalid complete-photo manifest.');
      }
    }
    if (setting('officeDevice') != null &&
        setting('officeDevice') != bundle['officeDevice']) {
      throw StateError(
        'Office authority changed. Saved work has been retained.',
      );
    }
    final next = bundle['catalog'] as Json;
    validateCatalog(next);
    if (setting('workspace') != null ||
        (catalog != null && catalog!['companyId'] != next['companyId'])) {
      throw StateError('Different company. Existing work is retained.');
    }
    if (catalog != null) {
      for (final key in ['companyId', 'company', 'coordinatorName']) {
        if (catalog![key] != next[key]) {
          throw StateError('The saved company identity cannot be replaced.');
        }
      }
      for (final key in ['equipment', 'templates', 'jobs']) {
        for (final old in _catalogRows(key)) {
          final fresh = (next[key] as List)
              .where((j) => (j as Map)['id'] == old['id'])
              .firstOrNull;
          if (fresh == null || canonical(fresh) != canonical(old)) {
            throw StateError(
              'Saved company records cannot be removed or replaced.',
            );
          }
        }
      }
    }
    final documents = bundle['documents'] as Map;
    final jobIds = (next['jobs'] as List)
        .map((j) => (j as Map)['id'] as String)
        .toSet();
    if (documents.keys.toSet().difference(jobIds).isNotEmpty ||
        jobIds.difference(documents.keys.toSet()).isNotEmpty) {
      throw StateError('Company bundle has incomplete work history.');
    }
    final merged = <String, Uint8List>{};
    for (final id in jobIds) {
      final incoming = base64Decode(documents[id] as String);
      if (incoming.isEmpty || incoming.length > 16 * 1024 * 1024) {
        throw StateError('Invalid work document size.');
      }
      final rows = db.select('SELECT bytes FROM documents WHERE id=?', [id]);
      final bytes = rows.isEmpty
          ? incoming
          : await mergeDocuments(
              left: rows.single['bytes'] as Uint8List,
              right: incoming,
            );
      validateJobDocument(
        jsonDecode(await documentValues(bytes: bytes)) as Json,
        jobContext(next, id),
      );
      merged[id] = bytes;
    }
    final submitted = <String, Json>{
      for (final p in submissions)
        p['id'] as String: Map<String, dynamic>.from(p)..remove('_state'),
    };
    for (final p in bundle['submissions'] as List) {
      final payload = Map<String, dynamic>.from(p as Map);
      await ApprovalRules.validateSubmission(
        payload,
        jobContext(next, payload['jobId'] as String),
      );
      final old = submitted[payload['id']];
      if (old != null && contentHash(old) != contentHash(payload)) {
        throw StateError('Submission identity reused with changed content.');
      }
      submitted[payload['id'] as String] = payload;
    }
    ApprovalRules.validateSubmissionHistory(submitted.values);
    for (final r in bundle['receipts'] as List) {
      final receipt = Map<String, dynamic>.from(r as Map);
      final p = submitted[receipt['submissionId']];
      if (p == null) throw StateError('Decision lacks its submitted version.');
      ApprovalRules.validateReceipt(
        receipt,
        p,
        workspace: jobContext(next, p['jobId'] as String),
      );
      if (receipt['reviewerDevice'] != bundle['officeDevice']) {
        throw StateError('Decision belongs to a different office authority.');
      }
    }
    transaction(() {
      setSetting('catalog', next);
      setSetting('officeDevice', bundle['officeDevice']);
      db.execute('PRAGMA user_version=2');
      for (final e in merged.entries) {
        saveDocument(e.value, jobId: e.key);
      }
      for (final p in bundle['submissions'] as List) {
        _saveSubmission(Map<String, dynamic>.from(p as Map), 'received');
      }
      for (final r in bundle['receipts'] as List) {
        _saveReceipt(Map<String, dynamic>.from(r as Map));
      }
    });
  }

  Future<void> close() async {
    await queue.idle;
    db.close();
  }
}
