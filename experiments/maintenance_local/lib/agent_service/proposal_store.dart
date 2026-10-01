import 'dart:convert';
import 'dart:io';
import 'package:uuid/uuid.dart';
import '../model.dart';
import '../maintenance_domain.dart';
import 'errors.dart';

/// Separate local-only pending proposals. Existing backup/replication excludes
/// this directory. There is deliberately no apply or human-review API here.
class AgentProposalStore {
  AgentProposalStore(Directory workspace)
    : root = Directory('${workspace.absolute.path}/agent-proposals-v1'),
      _syntheticFlushDirectory = null;

  /// Explicit test-only I/O seam; never exposed through the wire or launcher.
  AgentProposalStore.forSyntheticTest(
    Directory workspace, {
    required int Function(Directory) flushDirectory,
  }) : root = Directory('${workspace.absolute.path}/agent-proposals-v1'),
       _syntheticFlushDirectory = flushDirectory;
  final Directory root;
  final int Function(Directory)? _syntheticFlushDirectory;
  final _queue = SerialQueue();
  static final _filename = RegExp(r'^[a-f0-9]{64}\.json$');
  static const maxRecordBytes = 16 * 1024 * 1024;
  String _key(String grant, String key) => contentHash([grant, key]);

  Future<Json?> lookup(String grant, String key) async {
    final type = await FileSystemEntity.type(root.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return null;
    if (type != FileSystemEntityType.directory) {
      throw const AgentFailure('internal_error');
    }
    if ((root.statSync().mode & 0xfff) != 0x1c0) {
      throw const AgentFailure('internal_error');
    }
    _rootIdentity();
    final file = File('${root.path}/${_key(grant, key)}.json');
    if (!await file.exists()) return null;
    return _read(file);
  }

  Future<List<Json>> records() async {
    final type = await FileSystemEntity.type(root.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return [];
    if (type != FileSystemEntityType.directory) {
      throw const AgentFailure('internal_error');
    }
    if ((root.statSync().mode & 0xfff) != 0x1c0) {
      throw const AgentFailure('internal_error');
    }
    _rootIdentity();
    final records = <Json>[];
    await for (final item in root.list(followLinks: false)) {
      final name = item.uri.pathSegments.last;
      if (name.startsWith('.pending-')) continue;
      if (item is! File || !_filename.hasMatch(name)) {
        throw const AgentFailure('internal_error');
      }
      records.add(await _read(item));
    }
    records.sort(
      (a, b) => (a['result']['proposal_id'] as String).compareTo(
        b['result']['proposal_id'] as String,
      ),
    );
    return records;
  }

  Future<Json> create({
    required String grantId,
    required String actorId,
    required Json payload,
    required Json context,
    required Json scope,
    required DateTime createdAt,
    required Future<void> Function() authorize,
    Future<void> Function()? validateContext,
  }) {
    payload = jsonDecode(canonical(payload)) as Json;
    context = jsonDecode(canonical(context)) as Json;
    scope = jsonDecode(canonical(scope)) as Json;
    return _queue.run(() async {
      await authorize();
      final key = payload['idempotency_key'] as String;
      final existing = await lookup(grantId, key);
      if (existing != null) {
        await authorize();
        if (existing['actor_id'] != actorId) {
          throw const AgentFailure('unauthorized');
        }
        return _replay(existing, payload, scope: scope, authorize: authorize);
      }
      final result = <String, dynamic>{
        'proposal_id': const Uuid().v4(),
        'type': 'inspection.notes',
        'job_id': payload['job_id'],
        'expected_document_hash': payload['expected_document_hash'],
        'notes': payload['notes'],
        'status': 'pending_human_review',
        'requires_human_review': true,
        'applied': false,
        'created_at': createdAt.toUtc().toIso8601String(),
        'idempotency_key': key,
        'local_only': true,
        'backup_included': false,
        'human_review_available': false,
      };
      final record = <String, dynamic>{
        'version': 2,
        'grant_id': grantId,
        'actor_id': actorId,
        'payload': payload,
        'context': context,
        'scope': scope,
        'command': 'proposals.create',
        'result': result,
      };
      record['hash'] = contentHash(record);
      final serialized = canonical(record);
      if (utf8.encode(serialized).length > maxRecordBytes) {
        throw const AgentFailure('internal_error');
      }
      await _privateRoot();
      final rootIdentity = _rootIdentity();
      final stage = File('${root.path}/.pending-${const Uuid().v4()}');
      final target = File('${root.path}/${_key(grantId, key)}.json');
      try {
        await stage.writeAsString(serialized, flush: true);
        await _mode(stage.path, '600');
        await validateContext?.call();
        await authorize();
        if (_rootIdentity() != rootIdentity) {
          throw const AgentFailure('internal_error');
        }
        // No Dart suspension between the final authority check and publication.
        final published = Process.runSync('/usr/bin/mv', [
          '--no-clobber',
          '--no-target-directory',
          '--',
          stage.path,
          target.path,
        ]);
        if (published.exitCode != 0) throw const AgentFailure('internal_error');
        if (stage.existsSync()) {
          final collision = await _read(target);
          await authorize();
          if (collision['actor_id'] != actorId) {
            throw const AgentFailure('unauthorized');
          }
          return _replay(
            collision,
            payload,
            scope: scope,
            authorize: authorize,
          );
        }
        _flushDirectory(rootIdentity);
        try {
          await authorize();
          _confirmRecord(record, rootIdentity);
        } catch (_) {
          // Publication already happened. A denied or interrupted final
          // acknowledgement cannot claim this original create was rejected.
          throw const AgentFailure('internal_error');
        }
        return jsonDecode(canonical(result)) as Json;
      } finally {
        if (_sameRoot(rootIdentity) && stage.existsSync()) stage.deleteSync();
      }
    });
  }

  /// A visible record is not proof that its publication survived a directory
  /// flush. Exact create retries confirm durability again, then reauthorize.
  Future<Json> replay(
    Json record,
    Json payload, {
    required Json scope,
    required Future<void> Function() authorize,
  }) {
    record = jsonDecode(canonical(record)) as Json;
    payload = jsonDecode(canonical(payload)) as Json;
    scope = jsonDecode(canonical(scope)) as Json;
    return _queue.run(
      () => _replay(record, payload, scope: scope, authorize: authorize),
    );
  }

  Future<Json> _replay(
    Json record,
    Json payload, {
    required Json scope,
    required Future<void> Function() authorize,
  }) async {
    if (canonical(record['payload']) != canonical(payload) ||
        canonical(record['scope']) != canonical(scope) ||
        record['command'] != 'proposals.create') {
      throw const AgentFailure('idempotency_conflict');
    }
    await authorize();
    final rootIdentity = _rootIdentity();
    final current = await lookup(
      record['grant_id'] as String,
      payload['idempotency_key'] as String,
    );
    if (current == null || canonical(current) != canonical(record)) {
      throw const AgentFailure('internal_error');
    }
    _flushDirectory(rootIdentity);
    await authorize();
    _confirmRecord(record, rootIdentity);
    return jsonDecode(canonical(record['result'])) as Json;
  }

  void _flushDirectory(String rootIdentity) {
    if (_rootIdentity() != rootIdentity) {
      throw const AgentFailure('internal_error');
    }
    final exitCode =
        _syntheticFlushDirectory?.call(root) ??
        Process.runSync('/usr/bin/sync', ['-f', '--', root.path]).exitCode;
    if (exitCode != 0 || _rootIdentity() != rootIdentity) {
      throw const AgentFailure('internal_error');
    }
  }

  // No async work follows the final authorization. Confirm that the same
  // immutable record is still present before acknowledging its saved result.
  void _confirmRecord(Json record, String rootIdentity) {
    if (_rootIdentity() != rootIdentity) {
      throw const AgentFailure('internal_error');
    }
    final file = File(
      '${root.path}/${_key(record['grant_id'] as String, record['payload']['idempotency_key'] as String)}.json',
    );
    if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
            FileSystemEntityType.file ||
        (file.statSync().mode & 0xfff) != 0x180 ||
        file.lengthSync() > maxRecordBytes ||
        canonical(jsonDecode(file.readAsStringSync())) != canonical(record)) {
      throw const AgentFailure('internal_error');
    }
  }

  bool _sameRoot(String identity) {
    try {
      return _rootIdentity() == identity;
    } catch (_) {
      return false;
    }
  }

  String _rootIdentity() {
    if (FileSystemEntity.typeSync(root.path, followLinks: false) !=
            FileSystemEntityType.directory ||
        (root.statSync().mode & 0xfff) != 0x1c0 ||
        root.resolveSymbolicLinksSync() != root.path ||
        FileSystemEntity.typeSync(root.parent.path, followLinks: false) !=
            FileSystemEntityType.directory ||
        (root.parent.statSync().mode & 0xfff) != 0x1c0) {
      throw const AgentFailure('internal_error');
    }
    final result = Process.runSync('/usr/bin/stat', [
      '--format=%d:%i',
      '--',
      root.path,
    ]);
    if (result.exitCode != 0) throw const AgentFailure('internal_error');
    return result.stdout.toString().trim();
  }

  Future<void> _privateRoot() async {
    final type = await FileSystemEntity.type(root.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      await root.create();
    } else if (type != FileSystemEntityType.directory) {
      throw const AgentFailure('internal_error');
    }
    await _mode(root.path, '700');
  }

  Future<void> _mode(String path, String mode) async {
    final result = await Process.run('/usr/bin/chmod', [mode, '--', path]);
    if (result.exitCode != 0 ||
        ((await FileStat.stat(path)).mode & 0x3f) != 0) {
      throw const AgentFailure('internal_error');
    }
  }

  Future<Json> _read(File file) async {
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
            FileSystemEntityType.file ||
        await file.length() > maxRecordBytes) {
      throw const AgentFailure('internal_error');
    }
    if ((file.statSync().mode & 0xfff) != 0x180) {
      throw const AgentFailure('internal_error');
    }
    final record = jsonDecode(await file.readAsString()) as Json;
    final clean = Map<String, dynamic>.from(record)..remove('hash');
    if (!_keys(record, {
          'version',
          'grant_id',
          'actor_id',
          'payload',
          'context',
          'scope',
          'command',
          'result',
          'hash',
        }) ||
        record['grant_id'] is! String ||
        record['actor_id'] is! String ||
        record['context'] is! Json ||
        record['version'] != 2 ||
        record['command'] != 'proposals.create' ||
        record['scope'] is! Json ||
        record['hash'] != contentHash(clean) ||
        record['payload'] is! Json ||
        record['result'] is! Json ||
        file.uri.pathSegments.last !=
            '${_key(record['grant_id'] as String, record['payload']['idempotency_key'] as String)}.json' ||
        record['result']['status'] != 'pending_human_review' ||
        record['result']['applied'] != false) {
      throw const AgentFailure('internal_error');
    }
    final payload = record['payload'] as Json;
    final result = record['result'] as Json;
    final context = record['context'] as Json;
    validateJobContext(context);
    final scope = record['scope'] as Json;
    if (!_keys(scope, {'workspace_id', 'company_id', 'device_id'}) ||
        !scope.values.every(
          (value) =>
              value is String &&
              RegExp(r'^[A-Za-z0-9_-]{1,100}$').hasMatch(value),
        ) ||
        scope['company_id'] != context['companyId']) {
      throw const AgentFailure('internal_error');
    }
    if (!_keys(payload, {
          'idempotency_key',
          'type',
          'job_id',
          'expected_document_hash',
          'notes',
        }) ||
        !_keys(result, {
          'proposal_id',
          'type',
          'job_id',
          'expected_document_hash',
          'notes',
          'status',
          'requires_human_review',
          'applied',
          'created_at',
          'idempotency_key',
          'local_only',
          'backup_included',
          'human_review_available',
        }) ||
        payload['type'] != 'inspection.notes' ||
        payload['job_id'] != context['jobId'] ||
        payload['notes'] is! String ||
        (payload['notes'] as String).trim().isEmpty ||
        (payload['notes'] as String).length > 10000 ||
        payload['expected_document_hash'] is! String ||
        !hashPattern.hasMatch(payload['expected_document_hash'] as String) ||
        payload['idempotency_key'] is! String ||
        !_uuid.hasMatch(payload['idempotency_key'] as String) ||
        result['proposal_id'] is! String ||
        !_uuid.hasMatch(result['proposal_id'] as String) ||
        result['created_at'] is! String ||
        DateTime.tryParse(result['created_at'] as String)?.isUtc != true ||
        result['requires_human_review'] != true ||
        result['local_only'] != true ||
        result['backup_included'] != false ||
        result['human_review_available'] != false ||
        [
          'type',
          'job_id',
          'expected_document_hash',
          'notes',
          'idempotency_key',
        ].any((key) => result[key] != payload[key])) {
      throw const AgentFailure('internal_error');
    }
    return record;
  }

  static bool _keys(Json value, Set<String> keys) =>
      value.length == keys.length && value.keys.every(keys.contains);
  static final _uuid = RegExp(
    r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$',
  );
}
