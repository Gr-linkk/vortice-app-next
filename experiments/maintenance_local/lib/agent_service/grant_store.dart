import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'access_models.dart';
import 'access_scope.dart';
import 'grants.dart';

/// Private, local office capabilities. This sidecar is intentionally outside
/// the application database, replication and office recovery inventory.
///
/// A lifetime Linux flock gives this store the sole writer lease, including
/// across isolates and processes. Every operation reopens and validates the
/// current persisted state; replacing a pathname cannot redirect an open store.
class OfficeAgentGrantStore implements GrantProvider {
  OfficeAgentGrantStore._(
    this._workspace,
    this._scope,
    this._now,
    this._os,
    this._workspaceFd,
    this._rootFd,
    this._lockFd,
    this._workspaceIdentity,
    this._rootIdentity,
    this._lockIdentity,
  );

  static const _sidecar = 'agent-access-v1';
  static const _stateName = 'state.json';
  static const _lockName = 'writer.lock';
  static const _openFailure =
      'Office agent connections could not be safely opened.';
  static const _ioFailure =
      'Office agent connections could not be safely read or saved.';
  static const _maxBytes = 4 * 1024 * 1024;
  static const _maxGrants = 1024;
  static const _maxIds = 2048;
  static final _id = RegExp(r'^[A-Za-z0-9_-]{1,100}$');
  static final _grantId = RegExp(r'^grant-[a-f0-9]{32}$');
  static final _digest = RegExp(r'^[a-f0-9]{64}$');
  static final _token = RegExp(r'^[A-Za-z0-9_-]{43}$');
  static final _stageName = RegExp(r'^\.pending-[a-f0-9]{32}$');
  static const _readCommands = <String>{
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
  };

  final Directory _workspace;
  final AgentAccessScope _scope;
  final DateTime Function() _now;
  final _LinuxPrivateFiles _os;
  final int _workspaceFd, _rootFd, _lockFd;
  final _FileFacts _workspaceIdentity, _rootIdentity, _lockIdentity;
  Future<void> _tail = Future<void>.value();
  Future<void>? _closing;
  bool _closed = false;

  /// Creates only a disabled configuration and lease for a fresh workspace.
  /// Opening never issues a credential or changes existing unsafe state.
  static Future<OfficeAgentGrantStore> open({
    required Directory workspaceRoot,
    required AgentAccessScope scope,
    DateTime Function()? now,
  }) async {
    _LinuxPrivateFiles? os;
    var workspaceFd = -1, rootFd = -1, lockFd = -1;
    try {
      if (!Platform.isLinux || !_validScope(scope)) {
        throw StateError(_openFailure);
      }
      final workspace = workspaceRoot.absolute;
      if (workspaceRoot.path.contains('\u0000') ||
          workspace.resolveSymbolicLinksSync() != workspace.path) {
        throw StateError(_openFailure);
      }
      os = _LinuxPrivateFiles();
      workspaceFd = os.openDirectory(workspace.path);
      final workspaceFacts = os.facts(workspaceFd);
      os.requireDirectory(workspaceFacts, private: false);
      final created = os.makeDirectory(workspaceFd, _sidecar);
      rootFd = os.openChildDirectory(workspaceFd, _sidecar);
      final rootFacts = os.facts(rootFd);
      os.requireDirectory(rootFacts);
      lockFd = os.openLock(rootFd, _lockName, create: created);
      final lockFacts = os.facts(lockFd);
      os.requireFile(lockFacts, maxBytes: 0);
      os.lock(lockFd);
      final store = OfficeAgentGrantStore._(
        workspace,
        scope,
        now ?? (() => DateTime.now().toUtc()),
        os,
        workspaceFd,
        rootFd,
        lockFd,
        workspaceFacts,
        rootFacts,
        lockFacts,
      );
      if (created) {
        store._validateLocation();
        store._publish(_SavedState(false, []), previous: null);
        // The directory entry as well as its contents must be durable.
        os.flush(workspaceFd);
      } else {
        store._load();
      }
      return store;
    } catch (_) {
      if (os != null) {
        os.close(lockFd);
        os.close(rootFd);
        os.close(workspaceFd);
      }
      throw StateError(_openFailure);
    }
  }

  Future<bool> enabled() => _run(() => _load().state.enabled);

  Future<void> setEnabled(bool enabled) => _run(() {
    final saved = _load();
    if (saved.state.enabled == enabled) return;
    _publish(_SavedState(enabled, saved.state.grants), previous: saved.facts);
  });

  Future<List<OfficeAgentGrantSummary>> list() => _run(() {
    final records = _load().state.grants;
    return List.unmodifiable(records.map(_summary));
  });

  Future<IssuedAgentGrant> issue(AgentGrantRequest request) => _run(() {
    final saved = _load();
    if (!saved.state.enabled) {
      throw StateError(
        'Enable office agent connections before issuing access.',
      );
    }
    final createdAt = _now().toUtc();
    final expiresAt = request.expiresAt.toUtc();
    final label = request.label.trim();
    if (!_validLabel(label) ||
        !expiresAt.isAfter(createdAt) ||
        expiresAt.difference(createdAt) > const Duration(days: 7) ||
        !_validIds(request.equipmentIds, requireSome: true) ||
        !_validIds(request.jobIds)) {
      throw ArgumentError(
        'Choose a name, selected records and expiry within seven days.',
      );
    }
    if (saved.state.grants.length >= _maxGrants) {
      throw StateError(
        'The private office agent connection limit was reached.',
      );
    }
    final random = Random.secure();
    final token = base64UrlEncode(
      List<int>.generate(32, (_) => random.nextInt(256)),
    ).replaceAll('=', '');
    String id;
    do {
      id = 'grant-${_randomHex(random)}';
    } while (saved.state.grants.any((record) => record['id'] == id));
    final record = <String, dynamic>{
      'id': id,
      'actor_id': 'agent-${id.substring(6)}',
      'label': label,
      'token_sha256': sha256.convert(utf8.encode(token)).toString(),
      'created_at': createdAt.toIso8601String(),
      'expires_at': expiresAt.toIso8601String(),
      'revoked_at': null,
      'equipment_ids': request.equipmentIds.toList()..sort(),
      'job_ids': request.jobIds.toList()..sort(),
      'allow_notes': request.allowNotes,
    };
    _publish(
      _SavedState(true, [...saved.state.grants, record]),
      previous: saved.facts,
    );
    return IssuedAgentGrant(token: token, summary: _summary(record));
  });

  /// Revocation is idempotent, keeps the immutable scope and is durable before
  /// acknowledgement. Unknown IDs do not create records.
  Future<void> revoke(String grantId) => _run(() {
    if (!_grantId.hasMatch(grantId)) {
      throw ArgumentError('Choose an existing office agent connection.');
    }
    final saved = _load();
    final index = saved.state.grants.indexWhere((r) => r['id'] == grantId);
    if (index < 0 || saved.state.grants[index]['revoked_at'] != null) return;
    final record = Map<String, dynamic>.of(saved.state.grants[index]);
    var revokedAt = _now().toUtc();
    final createdAt = _date(record['created_at']);
    if (revokedAt.isBefore(createdAt)) revokedAt = createdAt;
    record['revoked_at'] = revokedAt.toIso8601String();
    final records = [...saved.state.grants];
    records[index] = record;
    _publish(_SavedState(saved.state.enabled, records), previous: saved.facts);
  });

  @override
  Future<AgentGrant?> resolve(String token) async {
    if (_closed || !_token.hasMatch(token)) return null;
    try {
      return await _run(() {
        final state = _load().state;
        if (!state.enabled) return null;
        final digest = sha256.convert(utf8.encode(token)).toString();
        for (final record in state.grants) {
          if (_sameDigest(record['token_sha256'] as String, digest)) {
            // The existing v1 service rechecks revoked and expiresAt and emits
            // its established grant_revoked/grant_expired errors.
            return _summary(record).grant;
          }
        }
        return null;
      });
    } catch (_) {
      // Credential lookups fail closed without exposing state or native errors.
      return null;
    }
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    // Reject requests immediately, including ones queued before close.
    _closed = true;
    await _tail;
    _os.close(_lockFd);
    _os.close(_rootFd);
    _os.close(_workspaceFd);
  }

  Future<T> _run<T>(T Function() body) {
    final result = _tail.then((_) {
      if (_closed) throw StateError('Office agent connections are closed.');
      try {
        return body();
      } on ArgumentError {
        rethrow;
      } on StateError catch (error) {
        if (error.message ==
                'Enable office agent connections before issuing access.' ||
            error.message ==
                'The private office agent connection limit was reached.') {
          rethrow;
        }
        throw StateError(_ioFailure);
      } catch (_) {
        throw StateError(_ioFailure);
      }
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  void _validateLocation() {
    if (_workspace.resolveSymbolicLinksSync() != _workspace.path) {
      throw StateError(_ioFailure);
    }
    final workspaceFd = _os.openDirectory(_workspace.path);
    var rootFd = -1, lockFd = -1;
    try {
      final workspace = _os.facts(workspaceFd);
      _os.requireDirectory(workspace, private: false);
      if (!workspace.sameIdentity(_workspaceIdentity)) {
        throw StateError(_ioFailure);
      }
      rootFd = _os.openChildDirectory(workspaceFd, _sidecar);
      final root = _os.facts(rootFd);
      _os.requireDirectory(root);
      if (!root.sameIdentity(_rootIdentity)) throw StateError(_ioFailure);
      lockFd = _os.openLock(rootFd, _lockName, create: false);
      final lock = _os.facts(lockFd);
      _os.requireFile(lock, maxBytes: 0);
      if (!lock.sameIdentity(_lockIdentity)) throw StateError(_ioFailure);
      // Bound the directory inventory; abandoned private staging files are
      // preserved after a crash, but never mistaken for published authority.
      for (final name in _os.names(rootFd, maximum: 64)) {
        if (name != _stateName &&
            name != _lockName &&
            !_stageName.hasMatch(name)) {
          throw StateError(_ioFailure);
        }
        final fd = _os.openRead(rootFd, name);
        try {
          _os.requireFile(_os.facts(fd), maxBytes: _maxBytes);
        } finally {
          _os.close(fd);
        }
      }
    } finally {
      _os.close(lockFd);
      _os.close(rootFd);
      _os.close(workspaceFd);
    }
  }

  _LoadedState _load() {
    _validateLocation();
    final fd = _os.openRead(_rootFd, _stateName);
    try {
      final before = _os.facts(fd);
      _os.requireFile(before, maxBytes: _maxBytes);
      if (before.size == 0) throw StateError(_ioFailure);
      final bytes = _os.read(fd, before.size);
      if (!_os.facts(fd).sameVersion(before)) throw StateError(_ioFailure);
      final text = utf8.decode(bytes, allowMalformed: false);
      final decoded = jsonDecode(text);
      // The writer emits compact JSON. Round-tripping also rejects duplicate
      // object keys and other ambiguous encodings rather than normalizing them.
      if (decoded is! Map<String, dynamic> || jsonEncode(decoded) != text) {
        throw StateError(_ioFailure);
      }
      final state = _decodeState(decoded);
      if (!_stateFacts().sameVersion(before)) throw StateError(_ioFailure);
      _validateLocation();
      return _LoadedState(state, before);
    } finally {
      _os.close(fd);
    }
  }

  _FileFacts _stateFacts() {
    final fd = _os.openRead(_rootFd, _stateName);
    try {
      final facts = _os.facts(fd);
      _os.requireFile(facts, maxBytes: _maxBytes);
      return facts;
    } finally {
      _os.close(fd);
    }
  }

  void _publish(_SavedState state, {required _FileFacts? previous}) {
    final bytes = utf8.encode(
      jsonEncode({
        'format': _sidecar,
        'scope': _scope.toJson(),
        'enabled': state.enabled,
        'grants': state.grants,
      }),
    );
    if (bytes.length > _maxBytes) throw StateError(_ioFailure);
    final stage = '.pending-${_randomHex(Random.secure())}';
    final fd = _os.createFile(_rootFd, stage);
    _FileFacts? stageFacts;
    var published = false;
    try {
      stageFacts = _os.facts(fd);
      _os.requireFile(stageFacts, maxBytes: 0);
      _os.write(fd, bytes);
      _os.flush(fd);
      final written = _os.facts(fd);
      _os.requireFile(written, maxBytes: _maxBytes);
      if (written.size != bytes.length || !written.sameIdentity(stageFacts)) {
        throw StateError(_ioFailure);
      }
      _validateLocation();
      if (previous == null) {
        if (_os.childExists(_rootFd, _stateName)) throw StateError(_ioFailure);
      } else if (!_stateFacts().sameVersion(previous)) {
        throw StateError(_ioFailure);
      }
      // Descriptor-relative publication never follows a destination symlink.
      // All same-UID participants must honor the sole writer lease; there is
      // no await between the final validation and rename.
      _os.rename(_rootFd, stage, _stateName);
      published = true;
      _os.flush(_rootFd);
      // Linux rename may update ctime, while the flushed contents, inode and
      // mtime must remain unchanged.
      if (!_stateFacts().samePublishedContents(written)) {
        throw StateError(_ioFailure);
      }
    } finally {
      _os.close(fd);
      if (!published && stageFacts != null) {
        // Cleanup only the inode created here. Unknown existing state is kept.
        _os.removeOwned(_rootFd, stage, stageFacts);
      }
    }
  }

  _SavedState _decodeState(Map<String, dynamic> value) {
    if (!_keys(value, {'format', 'scope', 'enabled', 'grants'}) ||
        value['format'] != _sidecar ||
        value['enabled'] is! bool ||
        value['scope'] is! Map<String, dynamic> ||
        jsonEncode(value['scope']) != jsonEncode(_scope.toJson()) ||
        value['grants'] is! List ||
        (value['grants'] as List).length > _maxGrants) {
      throw StateError(_ioFailure);
    }
    final grants = <Map<String, dynamic>>[];
    final ids = <String>{}, digests = <String>{};
    for (final raw in value['grants'] as List) {
      if (raw is! Map<String, dynamic> ||
          !_keys(raw, {
            'id',
            'actor_id',
            'label',
            'token_sha256',
            'created_at',
            'expires_at',
            'revoked_at',
            'equipment_ids',
            'job_ids',
            'allow_notes',
          }) ||
          raw['id'] is! String ||
          !_grantId.hasMatch(raw['id'] as String) ||
          raw['actor_id'] != 'agent-${(raw['id'] as String).substring(6)}' ||
          raw['label'] is! String ||
          !_validLabel(raw['label'] as String) ||
          raw['token_sha256'] is! String ||
          !_digest.hasMatch(raw['token_sha256'] as String) ||
          raw['allow_notes'] is! bool ||
          !_validSavedIds(raw['equipment_ids'], requireSome: true) ||
          !_validSavedIds(raw['job_ids']) ||
          !ids.add(raw['id'] as String) ||
          !digests.add(raw['token_sha256'] as String)) {
        throw StateError(_ioFailure);
      }
      final created = _date(raw['created_at']);
      final expires = _date(raw['expires_at']);
      if (!expires.isAfter(created) ||
          expires.difference(created) > const Duration(days: 7) ||
          (raw['revoked_at'] != null &&
              _date(raw['revoked_at']).isBefore(created))) {
        throw StateError(_ioFailure);
      }
      grants.add(raw);
    }
    return _SavedState(value['enabled'] as bool, grants);
  }

  OfficeAgentGrantSummary _summary(Map<String, dynamic> record) =>
      OfficeAgentGrantSummary(
        grant: AgentGrant(
          id: record['id'] as String,
          actorId: record['actor_id'] as String,
          workspaceId: _scope.workspaceId,
          companyId: _scope.companyId,
          deviceId: _scope.deviceId,
          expiresAt: _date(record['expires_at']),
          revoked: record['revoked_at'] != null,
          commands: {
            ..._readCommands,
            if (record['allow_notes'] as bool) 'proposals.create',
          },
          equipmentIds: (record['equipment_ids'] as List)
              .cast<String>()
              .toSet(),
          jobIds: (record['job_ids'] as List).cast<String>().toSet(),
        ),
        label: record['label'] as String,
        createdAt: _date(record['created_at']),
        revokedAt: record['revoked_at'] == null
            ? null
            : _date(record['revoked_at']),
      );

  static bool _validScope(AgentAccessScope scope) =>
      _id.hasMatch(scope.workspaceId) &&
      _id.hasMatch(scope.companyId) &&
      _id.hasMatch(scope.deviceId);

  static bool _validLabel(String value) =>
      value.isNotEmpty &&
      value.length <= 80 &&
      value.trim() == value &&
      !value.runes.any((rune) => rune < 32 || rune == 127);

  static bool _validIds(Set<String> values, {bool requireSome = false}) =>
      (!requireSome || values.isNotEmpty) &&
      values.length <= _maxIds &&
      values.every(_id.hasMatch);

  static bool _validSavedIds(Object? raw, {bool requireSome = false}) {
    if (raw is! List || raw.length > _maxIds || (requireSome && raw.isEmpty)) {
      return false;
    }
    String? previous;
    for (final id in raw) {
      if (id is! String ||
          !_id.hasMatch(id) ||
          (previous != null && previous.compareTo(id) >= 0)) {
        return false;
      }
      previous = id;
    }
    return true;
  }

  static DateTime _date(Object? value) {
    if (value is! String || value.length > 30) throw StateError(_ioFailure);
    final date = DateTime.parse(value);
    if (!date.isUtc || date.toIso8601String() != value) {
      throw StateError(_ioFailure);
    }
    return date;
  }

  static bool _keys(Map<String, dynamic> value, Set<String> keys) =>
      value.length == keys.length && keys.every(value.containsKey);

  static bool _sameDigest(String left, String right) {
    var difference = left.length ^ right.length;
    for (var i = 0; i < left.length && i < right.length; i++) {
      difference |= left.codeUnitAt(i) ^ right.codeUnitAt(i);
    }
    return difference == 0;
  }

  static String _randomHex(Random random) => List<int>.generate(
    16,
    (_) => random.nextInt(256),
  ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

class _SavedState {
  _SavedState(this.enabled, this.grants);
  final bool enabled;
  final List<Map<String, dynamic>> grants;
}

class _LoadedState {
  _LoadedState(this.state, this.facts);
  final _SavedState state;
  final _FileFacts facts;
}

class _FileFacts {
  _FileFacts(ByteData data)
    : uid = data.getUint32(20, Endian.host),
      mode = data.getUint16(28, Endian.host),
      links = data.getUint32(16, Endian.host),
      inode = data.getUint64(32, Endian.host),
      size = data.getUint64(40, Endian.host),
      deviceMajor = data.getUint32(136, Endian.host),
      deviceMinor = data.getUint32(140, Endian.host),
      changedSeconds = data.getInt64(96, Endian.host),
      changedNanos = data.getUint32(104, Endian.host),
      modifiedSeconds = data.getInt64(112, Endian.host),
      modifiedNanos = data.getUint32(120, Endian.host);
  final int uid, mode, links, inode, size, deviceMajor, deviceMinor;
  final int changedSeconds, changedNanos, modifiedSeconds, modifiedNanos;
  bool sameIdentity(_FileFacts other) =>
      inode == other.inode &&
      deviceMajor == other.deviceMajor &&
      deviceMinor == other.deviceMinor;
  bool sameVersion(_FileFacts other) =>
      sameIdentity(other) &&
      uid == other.uid &&
      mode == other.mode &&
      links == other.links &&
      size == other.size &&
      changedSeconds == other.changedSeconds &&
      changedNanos == other.changedNanos &&
      modifiedSeconds == other.modifiedSeconds &&
      modifiedNanos == other.modifiedNanos;
  bool samePublishedContents(_FileFacts other) =>
      sameIdentity(other) &&
      uid == other.uid &&
      mode == other.mode &&
      links == other.links &&
      size == other.size &&
      modifiedSeconds == other.modifiedSeconds &&
      modifiedNanos == other.modifiedNanos;
}

/// Linux descriptor-relative primitives. statx has the same documented 256-byte
/// layout on Linux architectures; no platform-dependent struct stat is assumed.
class _LinuxPrivateFiles {
  _LinuxPrivateFiles() : _library = DynamicLibrary.open('libc.so.6');
  final DynamicLibrary _library;
  late final _malloc = _library
      .lookupFunction<
        Pointer<Void> Function(IntPtr),
        Pointer<Void> Function(int)
      >('malloc');
  late final _free = _library
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('free');
  late final _openAt = _library
      .lookupFunction<
        Int32 Function(Int32, Pointer<Uint8>, Int32, Uint32),
        int Function(int, Pointer<Uint8>, int, int)
      >('openat');
  late final _mkdirAt = _library
      .lookupFunction<
        Int32 Function(Int32, Pointer<Uint8>, Uint32),
        int Function(int, Pointer<Uint8>, int)
      >('mkdirat');
  late final _close = _library
      .lookupFunction<Int32 Function(Int32), int Function(int)>('close');
  late final _flock = _library
      .lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>(
        'flock',
      );
  late final _fsync = _library
      .lookupFunction<Int32 Function(Int32), int Function(int)>('fsync');
  late final _statx = _library
      .lookupFunction<
        Int32 Function(Int32, Pointer<Uint8>, Int32, Uint32, Pointer<Uint8>),
        int Function(int, Pointer<Uint8>, int, int, Pointer<Uint8>)
      >('statx');
  late final _read = _library
      .lookupFunction<
        IntPtr Function(Int32, Pointer<Uint8>, IntPtr),
        int Function(int, Pointer<Uint8>, int)
      >('read');
  late final _write = _library
      .lookupFunction<
        IntPtr Function(Int32, Pointer<Uint8>, IntPtr),
        int Function(int, Pointer<Uint8>, int)
      >('write');
  late final _renameAt = _library
      .lookupFunction<
        Int32 Function(Int32, Pointer<Uint8>, Int32, Pointer<Uint8>),
        int Function(int, Pointer<Uint8>, int, Pointer<Uint8>)
      >('renameat');
  late final _unlinkAt = _library
      .lookupFunction<
        Int32 Function(Int32, Pointer<Uint8>, Int32),
        int Function(int, Pointer<Uint8>, int)
      >('unlinkat');
  late final _geteuid = _library
      .lookupFunction<Uint32 Function(), int Function()>('geteuid');
  late final _fdopendir = _library
      .lookupFunction<
        Pointer<Void> Function(Int32),
        Pointer<Void> Function(int)
      >('fdopendir');
  late final _readdir = _library
      .lookupFunction<
        Pointer<Uint8> Function(Pointer<Void>),
        Pointer<Uint8> Function(Pointer<Void>)
      >('readdir64');
  late final _closedir = _library
      .lookupFunction<
        Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('closedir');
  late final _errno = _library
      .lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>(
        '__errno_location',
      );

  static const _noFollow = 0x20000, _cloexec = 0x80000, _directory = 0x10000;
  static const _nonblock = 0x800, _create = 0x40, _exclusive = 0x80;

  T _name<T>(String value, T Function(Pointer<Uint8>) action) {
    final bytes = utf8.encode(value);
    if (value.contains('\u0000')) throw StateError('Invalid private pathname.');
    final pointer = _malloc(bytes.length + 1).cast<Uint8>();
    if (pointer == nullptr) throw StateError('Private allocation failed.');
    try {
      pointer.asTypedList(bytes.length + 1).setAll(0, [...bytes, 0]);
      return action(pointer);
    } finally {
      _free(pointer.cast<Void>());
    }
  }

  int _open(int directory, String name, int flags, [int mode = 0]) =>
      _name(name, (pointer) {
        final fd = _openAt(
          directory,
          pointer,
          flags | _noFollow | _cloexec,
          mode,
        );
        if (fd < 0) throw StateError('Private entry could not be opened.');
        return fd;
      });

  int openDirectory(String path) => _open(-100, path, _directory);
  int openChildDirectory(int fd, String name) => _open(fd, name, _directory);
  int openRead(int fd, String name) => _open(fd, name, _nonblock);
  int openLock(int fd, String name, {required bool create}) => _open(
    fd,
    name,
    2 | _nonblock | (create ? _create | _exclusive : 0),
    0x180,
  );
  int createFile(int fd, String name) =>
      _open(fd, name, 1 | _nonblock | _create | _exclusive, 0x180);

  bool makeDirectory(int fd, String name) => _name(name, (pointer) {
    if (_mkdirAt(fd, pointer, 0x1c0) == 0) return true;
    // Opening and validating the existing entry distinguishes EEXIST from
    // failures without making changes to that entry.
    final existing = openChildDirectory(fd, name);
    close(existing);
    return false;
  });

  _FileFacts facts(int fd) => _name('', (name) {
    final buffer = _malloc(256).cast<Uint8>();
    if (buffer == nullptr) throw StateError('Private allocation failed.');
    try {
      buffer.asTypedList(256).fillRange(0, 256, 0);
      if (_statx(fd, name, 0x1000 | 0x100, 0x7ff, buffer) != 0) {
        throw StateError('Private entry could not be checked.');
      }
      final bytes = buffer.asTypedList(256);
      final data = ByteData.sublistView(bytes);
      if ((data.getUint32(0, Endian.host) & 0x7ff) != 0x7ff) {
        throw StateError('Private entry metadata is incomplete.');
      }
      return _FileFacts(data);
    } finally {
      _free(buffer.cast<Void>());
    }
  });

  void requireDirectory(_FileFacts facts, {bool private = true}) {
    if (facts.uid != _geteuid() ||
        (facts.mode & 0xf000) != 0x4000 ||
        (private ? (facts.mode & 0xfff) != 0x1c0 : (facts.mode & 0xc12) != 0)) {
      throw StateError('Private directory ownership or mode is unsafe.');
    }
  }

  void requireFile(_FileFacts facts, {required int maxBytes}) {
    if (facts.uid != _geteuid() ||
        (facts.mode & 0xf000) != 0x8000 ||
        (facts.mode & 0xfff) != 0x180 ||
        facts.links != 1 ||
        facts.size > maxBytes) {
      throw StateError('Private file ownership, mode or size is unsafe.');
    }
  }

  void lock(int fd) {
    if (_flock(fd, 2 | 4) != 0) {
      throw StateError('Private writer lease is held.');
    }
  }

  void flush(int fd) {
    if (_fsync(fd) != 0) {
      throw StateError('Private state could not be flushed.');
    }
  }

  List<String> names(int fd, {required int maximum}) {
    final directoryFd = openChildDirectory(fd, '.');
    final directory = _fdopendir(directoryFd);
    if (directory == nullptr) {
      close(directoryFd);
      throw StateError('Private directory could not be read.');
    }
    try {
      final names = <String>[];
      while (true) {
        _errno().value = 0;
        final entry = _readdir(directory);
        if (entry == nullptr) {
          if (_errno().value != 0) {
            throw StateError('Private directory could not be read.');
          }
          return names;
        }
        // Linux dirent64 has 64-bit ino/off, 16-bit reclen and 8-bit type;
        // d_name starts at byte 19, independently of native word size.
        final header = ByteData.sublistView(entry.asTypedList(19));
        final length = header.getUint16(16, Endian.host);
        if (length < 20 || length > 4096) {
          throw StateError('Private directory entry is malformed.');
        }
        final bytes = (entry + 19).asTypedList(length - 19);
        final end = bytes.indexOf(0);
        if (end < 0) throw StateError('Private directory entry is malformed.');
        final name = utf8.decode(bytes.sublist(0, end), allowMalformed: false);
        if (name == '.' || name == '..') continue;
        if (names.length >= maximum) {
          throw StateError('Private directory inventory exceeds its limit.');
        }
        names.add(name);
      }
    } finally {
      _closedir(directory);
    }
  }

  List<int> read(int fd, int size) {
    final pointer = _malloc(size).cast<Uint8>();
    if (pointer == nullptr) throw StateError('Private allocation failed.');
    try {
      var offset = 0;
      while (offset < size) {
        final count = _read(fd, pointer + offset, size - offset);
        if (count <= 0) throw StateError('Private state could not be read.');
        offset += count;
      }
      return List<int>.of(pointer.asTypedList(size));
    } finally {
      _free(pointer.cast<Void>());
    }
  }

  void write(int fd, List<int> bytes) {
    final pointer = _malloc(bytes.length).cast<Uint8>();
    if (pointer == nullptr) throw StateError('Private allocation failed.');
    try {
      pointer.asTypedList(bytes.length).setAll(0, bytes);
      var offset = 0;
      while (offset < bytes.length) {
        final count = _write(fd, pointer + offset, bytes.length - offset);
        if (count <= 0) throw StateError('Private state could not be written.');
        offset += count;
      }
    } finally {
      _free(pointer.cast<Void>());
    }
  }

  bool childExists(int fd, String name) => _name(name, (pointer) {
    final buffer = _malloc(256).cast<Uint8>();
    if (buffer == nullptr) throw StateError('Private allocation failed.');
    try {
      if (_statx(fd, pointer, 0x100, 0x7ff, buffer) == 0) return true;
      if (_errno().value == 2) return false;
      throw StateError('Private destination could not be checked.');
    } finally {
      _free(buffer.cast<Void>());
    }
  });

  void rename(int fd, String from, String to) => _name(
    from,
    (source) => _name(to, (target) {
      if (_renameAt(fd, source, fd, target) != 0) {
        throw StateError('Private state could not be published.');
      }
    }),
  );

  void removeOwned(int fd, String name, _FileFacts owned) {
    var checkFd = -1;
    try {
      checkFd = openRead(fd, name);
      if (facts(checkFd).sameIdentity(owned)) {
        _name(name, (pointer) => _unlinkAt(fd, pointer, 0));
      }
    } catch (_) {
      // An entry that cannot be proven ours remains for recovery.
    } finally {
      close(checkFd);
    }
  }

  void close(int fd) {
    if (fd >= 0) _close(fd);
  }
}
