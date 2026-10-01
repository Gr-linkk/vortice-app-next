import 'dart:convert';
import '../job_progress.dart';
import '../lab_store.dart';
import '../model.dart';
import 'read_snapshot.dart';
import 'errors.dart';
import 'grants.dart';
import 'proposal_store.dart';

/// Permission-checked local reads and unapplied note suggestions. No authority
/// is inferred from the office role, filesystem access or mechanic enrollment.
class AgentService {
  AgentService({
    required this.store,
    required this.workspaceId,
    required this.serviceDeviceId,
    this.grants = const DenyAgentGrants(),
    DateTime Function()? now,
    AgentProposalStore? proposals,
  }) : now = now ?? (() => DateTime.now().toUtc()),
       proposals = proposals ?? AgentProposalStore(store.root);
  final LabStore store;
  final String workspaceId, serviceDeviceId;
  final GrantProvider grants;
  final DateTime Function() now;
  final AgentProposalStore proposals;
  final _queue = SerialQueue();
  static const commands = <String>{
    'capabilities',
    'workspace.status',
    'equipment.list',
    'equipment.show',
    'work.list',
    'work.show',
    'procedures.list',
    'procedures.show',
    'history.list',
    'proposals.list',
    'proposals.show',
    'proposals.create',
  };
  static const maxResponseBytes = 1024 * 1024;
  static const maxResultBytes = 900 * 1024;
  static final _id = RegExp(r'^[A-Za-z0-9_-]{1,100}$');
  static final _uuid = RegExp(
    r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$',
  );

  Future<Json> handle(Json input) {
    Json request;
    try {
      request = _copy(input);
    } catch (_) {
      return Future.value(_failure(null, null, 'invalid_request'));
    }
    return _queue.run(() async {
      final requestId = _validId(request['request_id'])
          ? request['request_id'] as String
          : null;
      var scope = _scope(request['scope']);
      try {
        if (!_keys(request, {
              'protocol_version',
              'request_id',
              'scope',
              'credential',
              'command',
              'args',
            }) ||
            requestId == null ||
            scope == null ||
            request['credential'] is! Json ||
            !_keys(request['credential'] as Json, {'token'}) ||
            request['credential']['token'] is! String ||
            (request['credential']['token'] as String).isEmpty ||
            (request['credential']['token'] as String).length > 4096 ||
            request['command'] is! String ||
            request['args'] is! Json ||
            utf8.encode(canonical(request)).length > 65536) {
          scope = null;
          throw const AgentFailure('invalid_request');
        }
        if (request['protocol_version'] != 1 ||
            request['protocol_version'] is! int) {
          throw const AgentFailure('unsupported_version');
        }
        final command = request['command'] as String;
        if (!commands.contains(command)) {
          throw const AgentFailure('unsupported_command');
        }
        final args = request['args'] as Json;
        _arguments(command, args);
        final token = request['credential']['token'] as String;
        final grant = await _authorize(token, scope, command);
        if (command == 'proposals.create') {
          final result = await _create(args, grant, token, scope, command);
          return _success(
            requestId,
            scope,
            {'item': result},
            contentHash(result),
            true,
          );
        }
        if (command == 'capabilities') {
          final allowed = commands.where(grant.commands.contains).toList()
            ..sort();
          final result = <String, dynamic>{
            'commands': allowed,
            'proposal_types': allowed.contains('proposals.create')
                ? ['inspection.notes']
                : [],
          };
          return _success(requestId, scope, result, contentHash(result), true);
        }
        // The service capture reuses the pure progress projector with bounded,
        // referenced-only evidence reads and a final authority/freshness fence.
        final captured = await readAgentSnapshot(store);
        final proposalRecords =
            command.startsWith('proposals.') || command == 'workspace.status'
            ? await proposals.records()
            : <Json>[];
        return await store.queue.run(() async {
          final finalGrant = await _authorize(token, scope!, command);
          if (finalGrant.id != grant.id ||
              finalGrant.actorId != grant.actorId) {
            throw const AgentFailure('unauthorized');
          }
          if (captured.sourceFingerprint != agentSourceFingerprint(store) ||
              canonical(captured.evidenceIdentities) !=
                  canonical(
                    agentEvidenceIdentities(
                      store,
                      captured.evidenceIdentities.keys,
                    ),
                  )) {
            throw const AgentFailure('stale_context');
          }
          final visible = _visible(
            captured,
            finalGrant,
            args,
            proposalRecords,
            scope,
          );
          final output = _read(command, args, visible, finalGrant, scope);
          return _success(
            requestId,
            scope,
            output.result,
            output.revision,
            output.complete,
          );
        });
      } on AgentFailure catch (error) {
        return _failure(
          requestId,
          scope,
          error.code,
          capacity: error is AgentCapacityFailure,
        );
      } catch (_) {
        return _failure(requestId, scope, 'internal_error');
      }
    });
  }

  Future<AgentGrant> _authorize(
    String token,
    Json scope,
    String command,
  ) async {
    final grant = await grants.resolve(token);
    if (grant == null) throw const AgentFailure('unauthorized');
    if (grant.revoked) throw const AgentFailure('grant_revoked');
    if (!grant.expiresAt.isUtc || !grant.expiresAt.isAfter(now().toUtc())) {
      throw const AgentFailure('grant_expired');
    }
    if (scope['workspace_id'] != workspaceId ||
        scope['company_id'] != store.catalog?['companyId'] ||
        scope['device_id'] != serviceDeviceId ||
        grant.workspaceId != scope['workspace_id'] ||
        grant.companyId != scope['company_id'] ||
        grant.deviceId != scope['device_id']) {
      throw const AgentFailure('scope_mismatch');
    }
    if (!grant.commands.contains(command)) {
      throw const AgentFailure('permission_denied');
    }
    return grant;
  }

  bool _allows(AgentGrant grant, Json job) =>
      (grant.jobIds == null || grant.jobIds!.contains(job['id'])) &&
      (grant.equipmentIds == null ||
          grant.equipmentIds!.contains(job['equipmentId']));

  Future<Json> _create(
    Json args,
    AgentGrant grant,
    String token,
    Json scope,
    String command,
  ) async {
    final jobId = args['job_id'] as String;
    void accessible(AgentGrant current) {
      final matches = store.jobs.where((job) => job['id'] == jobId);
      if (matches.isEmpty || !_allows(current, matches.single)) {
        throw const AgentFailure('not_found');
      }
    }

    accessible(grant);
    final existing = await proposals.lookup(
      grant.id,
      args['idempotency_key'] as String,
    );
    if (existing != null) {
      if (existing['actor_id'] != grant.actorId) {
        throw const AgentFailure('unauthorized');
      }
      final current = await _authorize(token, scope, command);
      accessible(current);
      if (current.id != grant.id || current.actorId != grant.actorId) {
        throw const AgentFailure('unauthorized');
      }
      final accepted = await proposals.lookup(
        grant.id,
        args['idempotency_key'] as String,
      );
      if (accepted != null) {
        final replayGrant = await _authorize(token, scope, command);
        accessible(replayGrant);
        if (replayGrant.id != grant.id ||
            replayGrant.actorId != grant.actorId ||
            accepted['actor_id'] != grant.actorId) {
          throw const AgentFailure('unauthorized');
        }
        return proposals.replay(accepted, args, scope: scope);
      }
      return proposals.replay(existing, args, scope: scope);
    }
    // Hold the store queue through private publication, so the pinned context
    // and raw document hash cannot change through any ordinary store command.
    return store.queue.run(() async {
      final current = await _authorize(token, scope, command);
      accessible(current);
      if (current.id != grant.id || current.actorId != grant.actorId) {
        throw const AgentFailure('unauthorized');
      }
      final bytes = store.documentFor(jobId);
      if (bytes == null || digest(bytes) != args['expected_document_hash']) {
        throw const AgentFailure('stale_context');
      }
      final context = store.jobContextFor(jobId);
      return proposals.create(
        grantId: grant.id,
        actorId: grant.actorId,
        payload: args,
        context: context,
        scope: scope,
        createdAt: now(),
        authorize: () async {
          final authority = await _authorize(token, scope, command);
          accessible(authority);
          if (authority.id != grant.id || authority.actorId != grant.actorId) {
            throw const AgentFailure('unauthorized');
          }
        },
        validateContext: () async {
          final doc = store.documentFor(jobId);
          if (doc == null ||
              digest(doc) != args['expected_document_hash'] ||
              canonical(store.jobContextFor(jobId)) != canonical(context)) {
            throw const AgentFailure('stale_context');
          }
        },
      );
    });
  }

  _Visible _visible(
    AgentReadSnapshot capture,
    AgentGrant grant,
    Json args,
    List<Json> records,
    Json scope,
  ) {
    final jobs = (capture.catalog['jobs'] as List)
        .cast<Json>()
        .where(
          (job) =>
              _allows(grant, job) &&
              (args['job_id'] == null || args['job_id'] == job['id']) &&
              (args['equipment_id'] == null ||
                  args['equipment_id'] == job['equipmentId']),
        )
        .toList();
    final ids = jobs.map((job) => job['id']).toSet();
    final equipmentIds = jobs.map((job) => job['equipmentId']).toSet();
    final equipment = (capture.catalog['equipment'] as List)
        .cast<Json>()
        .where(
          (row) =>
              (grant.equipmentIds == null ||
                  grant.equipmentIds!.contains(row['id'])) &&
              (grant.jobIds == null && args['job_id'] == null ||
                  equipmentIds.contains(row['id'])) &&
              (args['equipment_id'] == null ||
                  args['equipment_id'] == row['id']),
        )
        .map(_copy)
        .toList();
    final work = jobs
        .map((job) => _work(capture.progress.jobs[job['id']]!))
        .toList();
    final procedures = <String, Json>{};
    for (final job in jobs) {
      final snapshot = _safeContext(job['checklistSnapshot'] as Json);
      final key = snapshot['id'] as String;
      final prior = procedures[key];
      if (prior != null && canonical(prior) != canonical(snapshot)) {
        throw const AgentFailure('internal_error');
      }
      procedures[key] = snapshot;
    }
    final history = <Json>[
      for (final job in jobs)
        for (final version in capture.progress.jobs[job['id']]!.history)
          _version(version, detailed: true),
    ];
    final pending = <Json>[
      for (final record in records)
        if (record['grant_id'] == grant.id &&
            record['actor_id'] == grant.actorId &&
            canonical(record['scope']) == canonical(scope) &&
            ids.contains(record['payload']['job_id']))
          _copy(record['result'] as Json),
    ];
    return _Visible(
      equipment,
      work,
      procedures.values.toList(),
      history,
      pending,
    );
  }

  _Output _read(
    String command,
    Json args,
    _Visible view,
    AgentGrant grant,
    Json scope,
  ) {
    if (command == 'capabilities') {
      final allowed = commands.where(grant.commands.contains).toList()..sort();
      final result = <String, dynamic>{
        'commands': allowed,
        'proposal_types': allowed.contains('proposals.create')
            ? ['inspection.notes']
            : [],
      };
      return _Output(result, contentHash(result), true);
    }
    if (command == 'workspace.status') {
      final result = <String, dynamic>{
        'scope': scope,
        'local_work_count': view.work.length,
        'local_equipment_count': view.equipment.length,
        'known_version_count': view.history.length,
        'pending_proposal_count': view.proposals.length,
        'proposals_local_only': true,
        'proposals_backup_included': false,
        'proposal_human_review_available': false,
        'known_decisions_are_historical': true,
      };
      return _Output(
        result,
        contentHash([
          result,
          view.work,
          view.equipment,
          view.history,
          view.proposals,
        ]),
        true,
      );
    }
    final list = switch (command.split('.').first) {
      'equipment' => view.equipment,
      'work' => view.work,
      'procedures' => view.procedures,
      'history' => view.history,
      'proposals' => view.proposals,
      _ => <Json>[],
    };
    final idKey = switch (command.split('.').first) {
      'work' => 'job_id',
      'history' => 'submission_id',
      'proposals' => 'proposal_id',
      _ => 'id',
    };
    list.sort((a, b) => (a[idKey] as String).compareTo(b[idKey] as String));
    final revision = contentHash(list);
    if (command.endsWith('.show')) {
      final target =
          args[switch (command) {
            'equipment.show' => 'equipment_id',
            'work.show' => 'job_id',
            'procedures.show' => 'procedure_id',
            _ => 'proposal_id',
          }];
      final found = list.where((row) => row[idKey] == target);
      if (found.isEmpty) throw const AgentFailure('not_found');
      final item = found.single;
      return _Output({'item': item}, contentHash(item), true);
    }
    final limit = args['limit'] as int? ?? 25;
    final filters = Map<String, dynamic>.from(args)
      ..remove('limit')
      ..remove('cursor');
    final query = contentHash([
      grant.id,
      grant.actorId,
      scope,
      command,
      filters,
    ]);
    var offset = 0;
    if (args['cursor'] != null) {
      Json cursor;
      try {
        cursor =
            jsonDecode(
                  utf8.decode(
                    base64Url.decode(
                      base64Url.normalize(args['cursor'] as String),
                    ),
                  ),
                )
                as Json;
      } catch (_) {
        throw const AgentFailure('invalid_request');
      }
      if (!_keys(cursor, {'version', 'query', 'revision', 'offset'}) ||
          cursor['version'] != 1 ||
          cursor['query'] != query ||
          cursor['offset'] is! int ||
          (cursor['offset'] as int) < 0) {
        throw const AgentFailure('invalid_request');
      }
      if (cursor['revision'] != revision) {
        throw const AgentFailure('stale_context');
      }
      offset = cursor['offset'] as int;
      if (offset > list.length) throw const AgentFailure('invalid_request');
    }
    final page = <Json>[];
    var bytes = 128;
    for (final item in list.skip(offset).take(limit)) {
      final size = utf8.encode(canonical(item)).length + 1;
      if (size + 128 > maxResultBytes - 1024) {
        throw const AgentCapacityFailure();
      }
      if (bytes + size > maxResultBytes - 1024) break;
      page.add(item);
      bytes += size;
    }
    final end = offset + page.length;
    final more = end < list.length;
    final cursor = more
        ? base64Url.encode(
            utf8.encode(
              canonical({
                'version': 1,
                'query': query,
                'revision': revision,
                'offset': end,
              }),
            ),
          )
        : null;
    return _Output(
      {'items': page, 'count': page.length, 'next_cursor': cursor},
      revision,
      !more,
    );
  }

  static void _arguments(String command, Json args) {
    Set<String> allowed;
    if (command == 'proposals.create') {
      if (!_keys(args, {
            'idempotency_key',
            'type',
            'job_id',
            'expected_document_hash',
            'notes',
          }) ||
          args['idempotency_key'] is! String ||
          !_uuid.hasMatch(args['idempotency_key'] as String) ||
          !_validId(args['job_id']) ||
          args['expected_document_hash'] is! String ||
          !hashPattern.hasMatch(args['expected_document_hash'] as String) ||
          args['notes'] is! String ||
          (args['notes'] as String).trim().isEmpty ||
          (args['notes'] as String).length > 10000) {
        throw const AgentFailure('invalid_request');
      }
      if (args['type'] != 'inspection.notes') {
        throw const AgentFailure('unsupported_proposal');
      }
      return;
    } else if (command.endsWith('.list')) {
      allowed = {'limit', 'cursor', 'job_id', 'equipment_id'};
    } else {
      allowed = switch (command) {
        'equipment.show' => {'equipment_id'},
        'work.show' => {'job_id'},
        'procedures.show' => {'procedure_id'},
        'proposals.show' => {'proposal_id'},
        _ => {},
      };
    }
    if (args.keys.any((key) => !allowed.contains(key)) ||
        (!command.endsWith('.list') && !_keys(args, allowed))) {
      throw const AgentFailure('invalid_request');
    }
    for (final entry in args.entries) {
      if (entry.key == 'limit') {
        if (entry.value is! int ||
            (entry.value as int) < 1 ||
            (entry.value as int) > 100) {
          throw const AgentFailure('invalid_request');
        }
      } else if (entry.key == 'cursor') {
        if (entry.value is! String ||
            (entry.value as String).isEmpty ||
            (entry.value as String).length > 4096) {
          throw const AgentFailure('invalid_request');
        }
      } else if (!_validId(entry.value)) {
        throw const AgentFailure('invalid_request');
      }
    }
  }

  static Json _work(JobProgress job) => {
    'job_id': job.jobId,
    'context': _compactContext(job.context),
    'history_details_command': 'history.list',
    'draft': {
      'document_hash': job.documentHash,
      'phase': job.draftPhase.name,
      'required_answered': job.requiredAnswered,
      'required_total': job.requiredTotal,
      'conflict_keys': job.conflictKeys,
      'problem': job.problem,
      'photo_state': job.photoState.name,
    },
    'ambiguous_current_versions': job.ambiguousCurrentVersions,
    'current_versions': job.currentVersions.map(_version).toList(),
    'known_history': job.history.map(_version).toList(),
    'queued_version_ids': job.queuedVersions
        .map((version) => version.id)
        .toList(),
  };
  static Json _version(SubmittedVersion version, {bool detailed = false}) => {
    'submission_id': version.id,
    'job_id': version.jobId,
    'device_id': version.device,
    'document_hash': version.documentHash,
    'revision': version.revision,
    'local_state': version.localState,
    'photo_state': version.photoState.name,
    if (detailed) 'values': _safeContext(version.submission['values'] as Json),
    if (detailed)
      'context': _compactContext(version.submission['context'] as Json),
    'inspection_values_included': detailed,
    'known_decision': version.receipt == null
        ? null
        : _safeContext(version.receipt!),
  };
  static Json _compactContext(Json source) {
    final out = _safeContext(source);
    Json compact(Json snapshot) => {
      for (final key in ['id', 'title', 'version', 'hash', 'provenance'])
        key: snapshot[key],
      'item_count': (snapshot['items'] as List).length,
      'items_included': false,
    };
    if (out['checklistSnapshot'] is Json) {
      out['checklistSnapshot'] = compact(out['checklistSnapshot'] as Json);
    }
    if (out['job'] is Json) {
      final job = out['job'] as Json;
      job.remove('equipmentSnapshot');
      job.remove('checklistSnapshot');
    }
    return out;
  }

  static Json _safeContext(Json source) {
    final out = _copy(source);
    void clean(Json map) {
      for (final key in map.keys.toList()) {
        if (key.startsWith('_') ||
            {
              'document',
              'token',
              'privateKey',
              'certificate',
              'photo_path',
              'evidence_paths',
            }.contains(key)) {
          map.remove(key);
          continue;
        }
        final value = map[key];
        if (key == 'reference' && value is String && _fileReference(value)) {
          map.remove(key);
          continue;
        }
        if (value is Json) clean(value);
        if (value is List) {
          for (final item in value) {
            if (item is Json) clean(item);
          }
        }
      }
    }

    clean(out);
    return out;
  }

  static Json _copy(Json value) => jsonDecode(canonical(value)) as Json;
  static bool _fileReference(String value) {
    final normalized = value.trim();
    return normalized.startsWith('/') ||
        normalized.startsWith('\\') ||
        normalized.startsWith('~') ||
        normalized.toLowerCase().startsWith('file:') ||
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(normalized) ||
        (normalized.contains('/') || normalized.contains('\\')) &&
            !RegExp(r'^https?://', caseSensitive: false).hasMatch(normalized);
  }

  static bool _validId(Object? value) => value is String && _id.hasMatch(value);
  static bool _keys(Json value, Set<String> expected) =>
      value.length == expected.length && value.keys.every(expected.contains);
  static Json? _scope(Object? value) =>
      value is Json &&
          _keys(value, {'workspace_id', 'company_id', 'device_id'}) &&
          value.values.every(_validId)
      ? _copy(value)
      : null;
  Json _success(
    String id,
    Json scope,
    Json result,
    String revision,
    bool complete,
  ) {
    final response = <String, dynamic>{
      'protocol_version': 1,
      'request_id': id,
      'scope': scope,
      'ok': true,
      'result': result,
      'meta': {
        'observed_at': now().toUtc().toIso8601String(),
        'source': 'local',
        'freshness': 'local_snapshot',
        'local_revision': revision,
        'complete': complete,
        'synced': {'verified': false, 'reason': 'no_fresh_transfer_proof'},
      },
    };
    if (utf8.encode(canonical(response)).length + 1 > maxResponseBytes) {
      throw const AgentCapacityFailure();
    }
    return response;
  }

  static Json _failure(
    String? id,
    Json? scope,
    String code, {
    bool capacity = false,
  }) => {
    'protocol_version': 1,
    'request_id': id,
    'scope': scope,
    'ok': false,
    'error': {
      'code': code,
      'message': capacity
          ? agentCapacityMessage
          : agentErrorMessages[code] ?? agentErrorMessages['internal_error'],
      'retryable': false,
      'outcome': code == 'internal_error' && !capacity ? 'unknown' : 'rejected',
    },
  };
}

class _Visible {
  _Visible(
    this.equipment,
    this.work,
    this.procedures,
    this.history,
    this.proposals,
  );
  final List<Json> equipment, work, procedures, history, proposals;
}

class _Output {
  _Output(this.result, this.revision, this.complete);
  final Json result;
  final String revision;
  final bool complete;
}
