import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../lab_store.dart';
import '../model.dart';
import 'access_models.dart';
import 'access_scope.dart';
import 'agent_service.dart';
import 'grant_store.dart';
import 'grants.dart';
import 'unix_transport.dart';

/// Owns one experimental Linux office's private agent service. Construction
/// does not open files, issue grants or start a listener. Close and drain this
/// host before restoring, replacing or closing its [store].
class OfficeAgentHost {
  OfficeAgentHost({
    required this.store,
    this.runtimeDirectory,
    DateTime Function()? now,
  }) : _now = now ?? (() => DateTime.now().toUtc());

  final LabStore store;
  final Directory? runtimeDirectory;
  final DateTime Function() _now;
  final _queue = SerialQueue();
  final _changes = StreamController<void>.broadcast();
  final _handlers = <Future<Json>>{};
  static final _hosts = <String>{};
  static const _unavailable =
      'Agent connections are unavailable. Close other office instances and '
      'check the private local access files and runtime folder.';
  static const _creationFailed =
      'The connection could not be created. Check the service and selected '
      'equipment and work.';
  static const _revocationFailed =
      'The connection could not be revoked. Check the private local access files.';

  AgentAccessScope? _scope;
  OfficeAgentGrantStore? _access;
  UnixAgentTransport? _transport;
  _SessionGrants? _session;
  String? _claim;
  var _enabled = false;
  var _stopEpoch = 0;
  var _closeRequested = false;
  Future<void>? _closing;
  List<OfficeAgentGrantSummary> _grants = const [];
  var _snapshot = const OfficeAgentHostSnapshot(
    state: OfficeAgentHostState.disabled,
    enabled: false,
  );

  AgentAccessScope? get scope => _scope;
  OfficeAgentHostSnapshot get snapshot => _snapshot;
  List<OfficeAgentGrantSummary> get grants => _grants;
  Stream<void> get changes => _changes.stream;

  Future<void> initialize() {
    final epoch = _stopEpoch;
    return _queue.run(() => _refresh(epoch));
  }

  Future<void> reload() {
    final epoch = _stopEpoch;
    return _queue.run(() => _refresh(epoch));
  }

  Future<void> enable() {
    final epoch = _stopEpoch;
    return _queue.run(() async {
      if (_closeRequested) return;
      try {
        if (!await _open()) return;
        await _access!.setEnabled(true);
        _enabled = true;
        _grants = List.unmodifiable(await _access!.list());
        await _start(epoch);
      } catch (_) {
        await _failClosed();
      }
    });
  }

  Future<void> disable() {
    // This synchronous fence is deliberately outside the lifecycle queue.
    // Active and queued handlers must lose authority before persistence or
    // transport shutdown waits for a durable operation to finish.
    _stopEpoch++;
    _session?.deny();
    if (!_closeRequested) _publish(OfficeAgentHostState.stopping);
    return _queue.run(() async {
      if (_closeRequested) return;
      var failed = false;
      try {
        if (await _open()) {
          await _access!.setEnabled(false);
          _enabled = false;
          _grants = List.unmodifiable(await _access!.list());
        }
      } catch (_) {
        failed = true;
      }
      try {
        await _stop();
      } catch (_) {
        failed = true;
      }
      _publish(
        failed
            ? OfficeAgentHostState.unavailable
            : OfficeAgentHostState.disabled,
        problem: failed ? _unavailable : null,
      );
    });
  }

  Future<IssuedAgentGrant> issue(
    AgentGrantRequest request,
  ) => _queue.run(() async {
    if (_closeRequested || _access == null || _session?.active != true) {
      throw StateError(_creationFailed);
    }
    try {
      // Catalog validation and issuance are held within the ordinary store
      // queue: an owner command cannot change the selected records in between.
      final issued = await store.queue.run(() async {
        if (_session?.active != true) throw StateError(_creationFailed);
        final current = AgentAccessScope.forOffice(store);
        if (current == null || current.workspaceId != _scope!.workspaceId) {
          _session?.deny();
          throw StateError(_unavailable);
        }
        final equipment = store.equipment.map((row) => row['id']).toSet();
        final jobs = {for (final row in store.jobs) row['id']: row};
        if (request.equipmentIds.isEmpty ||
            !equipment.containsAll(request.equipmentIds) ||
            !jobs.keys.toSet().containsAll(request.jobIds) ||
            request.jobIds.any(
              (id) => !request.equipmentIds.contains(jobs[id]!['equipmentId']),
            )) {
          throw StateError(_creationFailed);
        }
        return _access!.issue(request);
      });
      _grants = List.unmodifiable(await _access!.list());
      _publish(_snapshot.state, socketPath: _snapshot.socketPath);
      return issued;
    } on ArgumentError {
      throw StateError(_creationFailed);
    } on StateError catch (error) {
      if (error.message != _creationFailed) await _failClosed();
      throw StateError(_creationFailed);
    } catch (_) {
      await _failClosed();
      throw StateError(_creationFailed);
    }
  });

  Future<void> revoke(String id) {
    // Block this grant locally before its durable revocation waits behind any
    // handler. The persisted provider remains the authority across reopening.
    _session?.denyGrant(id);
    return _queue.run(() async {
      if (_closeRequested || _access == null) {
        throw StateError(_revocationFailed);
      }
      try {
        await _access!.revoke(id);
        _grants = List.unmodifiable(await _access!.list());
        _publish(_snapshot.state, socketPath: _snapshot.socketPath);
      } catch (_) {
        await _failClosed();
        throw StateError(_revocationFailed);
      }
    });
  }

  Future<void> _refresh(int epoch) async {
    if (_closeRequested) return;
    try {
      if (!await _open()) return;
      _enabled = await _access!.enabled();
      _grants = List.unmodifiable(await _access!.list());
      if (_enabled) {
        await _start(epoch);
      } else {
        _session?.deny();
        await _stop();
        _publish(OfficeAgentHostState.disabled);
      }
    } catch (_) {
      await _failClosed();
    }
  }

  Future<bool> _open() async {
    final current = AgentAccessScope.forOffice(store);
    if (!Platform.isLinux || current == null) {
      if (_access != null || _transport != null) throw StateError(_unavailable);
      _scope = null;
      _publish(OfficeAgentHostState.disabled);
      return false;
    }
    if (_access != null) {
      if (current.workspaceId != _scope!.workspaceId) {
        throw StateError(_unavailable);
      }
      return true;
    }
    _scope = current;
    final key = store.root.resolveSymbolicLinksSync();
    if (!_hosts.add(key)) throw StateError(_unavailable);
    _claim = key;
    try {
      // A fresh open saves only an empty disabled config and a lifetime lease;
      // it creates no credential. Phones/unprepared offices never reach here.
      _access = await OfficeAgentGrantStore.open(
        workspaceRoot: store.root,
        scope: current,
        now: _now,
      );
      return true;
    } catch (_) {
      _hosts.remove(key);
      _claim = null;
      rethrow;
    }
  }

  Future<void> _start(int epoch) async {
    if (_closeRequested || epoch != _stopEpoch) return;
    if (_transport != null && _session?.active == true) {
      _publish(
        OfficeAgentHostState.listening,
        socketPath: _transport!.socketPath,
      );
      return;
    }
    await _stop();
    if (_closeRequested || epoch != _stopEpoch) return;
    _publish(OfficeAgentHostState.starting);
    final directory = await _privateRuntime();
    // Use a fresh endpoint each start. A crash can leave private socket entries,
    // but reopening neither follows nor unlinks them. Consumers must copy the
    // current listening endpoint again after a restart; it is never a stable
    // service address. Stale entries remain outside all workspace backups.
    final path = '${directory.path}/a-${secret().substring(0, 16)}.sock';
    if (utf8.encode(path).length > 107) throw StateError(_unavailable);
    final session = _SessionGrants(_access!);
    final service = AgentService(
      store: store,
      workspaceId: _scope!.workspaceId,
      serviceDeviceId: _scope!.deviceId,
      grants: session,
      now: _now,
    );
    final transport = await UnixAgentTransport.start(
      socketPath: path,
      handler: (request) {
        final handling = service.handle(request);
        _handlers.add(handling);
        return handling.whenComplete(() => _handlers.remove(handling));
      },
    );
    if (_closeRequested || epoch != _stopEpoch) {
      session.deny();
      await transport.close();
      return;
    }
    _session = session;
    _transport = transport;
    session.allow();
    _publish(OfficeAgentHostState.listening, socketPath: path);
  }

  Future<Directory> _privateRuntime() async {
    final id = await Process.run('/usr/bin/id', ['-u']);
    final uid = (id.stdout as String).trim();
    if (id.exitCode != 0 || !RegExp(r'^\d+$').hasMatch(uid)) {
      throw StateError(_unavailable);
    }
    final runtime = runtimeDirectory ?? Directory('/tmp/vortice-agent-$uid');
    final path = runtime.path;
    if (path.isEmpty || !path.startsWith('/') || path.contains('\u0000')) {
      throw StateError(_unavailable);
    }
    final kind = FileSystemEntity.typeSync(path, followLinks: false);
    if (kind == FileSystemEntityType.notFound) {
      final parent = runtime.parent;
      if (FileSystemEntity.typeSync(parent.path, followLinks: false) !=
              FileSystemEntityType.directory ||
          parent.resolveSymbolicLinksSync() != parent.path) {
        throw StateError(_unavailable);
      }
      // mkdir atomically refuses an entry someone else already created. Never
      // chmod an existing path, create parent trees, or adopt a symlink.
      final made = await Process.run('/usr/bin/mkdir', [
        '--mode=700',
        '--',
        path,
      ]);
      if (made.exitCode != 0) throw StateError(_unavailable);
    }
    final owner = await Process.run('/usr/bin/stat', [
      '--format=%u',
      '--',
      path,
    ]);
    if (FileSystemEntity.typeSync(path, followLinks: false) !=
            FileSystemEntityType.directory ||
        runtime.resolveSymbolicLinksSync() != path ||
        (runtime.statSync().mode & 0xfff) != 0x1c0 ||
        owner.exitCode != 0 ||
        (owner.stdout as String).trim() != uid) {
      throw StateError(_unavailable);
    }
    return runtime;
  }

  Future<void> _stop() async {
    _session?.deny();
    final transport = _transport;
    if (transport == null) return;
    try {
      await transport.close();
    } finally {
      // Also track handlers here so a transport-close error cannot release the
      // grant lease or let a caller close its LabStore ahead of durable work.
      await Future.wait(_handlers.toList());
      _transport = null;
      _session = null;
    }
  }

  Future<void> _failClosed() async {
    _session?.deny();
    try {
      await _stop();
    } catch (_) {
      // The handler drain in _stop still finishes before this fixed guidance.
    }
    _grants = const [];
    _publish(OfficeAgentHostState.unavailable, problem: _unavailable);
  }

  void _publish(
    OfficeAgentHostState state, {
    String? socketPath,
    String? problem,
  }) {
    if (_changes.isClosed) return;
    _snapshot = OfficeAgentHostSnapshot(
      state: state,
      enabled: _enabled,
      scope: _scope,
      socketPath: state == OfficeAgentHostState.listening ? socketPath : null,
      problem: problem,
    );
    _changes.add(null);
  }

  Future<void> close() {
    if (_closing != null) return _closing!;
    _closeRequested = true;
    _stopEpoch++;
    _session?.deny();
    _publish(OfficeAgentHostState.stopping);
    return _closing = _queue.run(() async {
      var failed = false;
      try {
        try {
          await _stop();
        } finally {
          await _access?.close();
        }
      } catch (_) {
        failed = true;
      } finally {
        if (_claim != null) {
          _hosts.remove(_claim);
        }
        _claim = null;
        _access = null;
        _publish(
          OfficeAgentHostState.closed,
          problem: failed ? _unavailable : null,
        );
        await _changes.close();
      }
    });
  }
}

/// A session fence surrounds every fresh persisted-provider read, including the
/// service's final authorization immediately before a response or commit.
class _SessionGrants implements GrantProvider {
  _SessionGrants(this.provider);
  final GrantProvider provider;
  var _active = false;
  final _deniedGrants = <String>{};
  bool get active => _active;
  void allow() => _active = true;
  void deny() => _active = false;
  void denyGrant(String id) => _deniedGrants.add(id);

  @override
  Future<AgentGrant?> resolve(String token) async {
    if (!_active) return null;
    final grant = await provider.resolve(token);
    if (!_active || grant == null) return null;
    if (_deniedGrants.contains(grant.id)) {
      return AgentGrant(
        id: grant.id,
        actorId: grant.actorId,
        workspaceId: grant.workspaceId,
        companyId: grant.companyId,
        deviceId: grant.deviceId,
        expiresAt: grant.expiresAt,
        commands: grant.commands,
        jobIds: grant.jobIds,
        equipmentIds: grant.equipmentIds,
        revoked: true,
      );
    }
    return grant;
  }
}
