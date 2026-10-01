import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../model.dart';

/// A private Linux Unix-domain socket carrying protocol-v1 JSON Lines.
///
/// The handler owns envelope validation and authorization. Parsing failures and
/// unexpected handler failures never include request contents or exceptions.
class UnixAgentTransport {
  static const maxRequestLineBytes = 64 * 1024;
  static const maxResponseBytes = 1024 * 1024;
  static final _startingPaths = <String>{};
  static final _identifier = RegExp(r'^[A-Za-z0-9_-]{1,100}$');

  final String socketPath;
  final ServerSocket _server;
  final String _socketIdentity;
  final Future<Json> Function(Json) _handler;
  final Duration _frameTimeout;
  final int _maxConnections;
  final _clients = <Socket>{};
  final _serving = <Future<void>>{};
  late final StreamSubscription<Socket> _accepts;
  Future<void>? _closing;
  bool _closed = false;

  UnixAgentTransport._(
    this.socketPath,
    this._server,
    this._socketIdentity,
    this._handler,
    this._frameTimeout,
    this._maxConnections,
  ) {
    _accepts = _server.listen(
      (socket) {
        if (_closed || _clients.length >= _maxConnections) {
          socket.destroy();
          return;
        }
        _clients.add(socket);
        late final Future<void> serving;
        serving = _serve(socket).whenComplete(() => _serving.remove(serving));
        _serving.add(serving);
        unawaited(serving);
      },
      onError: (Object error, StackTrace stack) {
        // Do not surface socket errors, paths or native diagnostics to peers.
      },
    );
  }

  /// Binds a new pathname inside an existing ordinary directory with mode 0700.
  /// Existing entries and symlink parents are refused without changing them.
  static Future<UnixAgentTransport> start({
    required String socketPath,
    required Future<Json> Function(Json) handler,
    Duration frameTimeout = const Duration(seconds: 10),
    int maxConnections = 64,
  }) async {
    const failure = 'The private local agent socket could not be started.';
    if (!Platform.isLinux ||
        frameTimeout <= Duration.zero ||
        maxConnections < 1 ||
        maxConnections > 64) {
      throw StateError(failure);
    }
    String path;
    try {
      final file = File(socketPath).absolute;
      path = file.path;
      final parent = file.parent;
      if (socketPath.isEmpty ||
          socketPath.contains('\u0000') ||
          !socketPath.startsWith('/') ||
          utf8.encode(socketPath).length > 107 ||
          path != socketPath ||
          FileSystemEntity.typeSync(parent.path, followLinks: false) !=
              FileSystemEntityType.directory ||
          parent.resolveSymbolicLinksSync() != parent.path ||
          (parent.statSync().mode & 0xfff) != 0x1c0 ||
          FileSystemEntity.typeSync(path, followLinks: false) !=
              FileSystemEntityType.notFound ||
          !_startingPaths.add(path)) {
        throw StateError(failure);
      }
    } catch (_) {
      throw StateError(failure);
    }

    ServerSocket? server;
    String? identity;
    var published = false;
    try {
      // Dart unlinks its original AF_UNIX address on close. Bind a private,
      // unpredictable anchor so it cannot unlink a replacement of the public
      // name. Linux Unix sockets can be reached through an inode hardlink.
      final anchor =
          '${File(path).parent.path}/.agent-${secret().substring(0, 16)}';
      if (FileSystemEntity.typeSync(anchor, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw StateError(failure);
      }
      server = await ServerSocket.bind(
        InternetAddress(anchor, type: InternetAddressType.unix),
        0,
        shared: false,
      );
      identity = _identity(anchor);
      if (identity == null) throw StateError(failure);
      final result = await Process.run('/usr/bin/chmod', ['600', '--', anchor]);
      if (result.exitCode != 0 ||
          _identity(anchor) != identity ||
          (File(anchor).statSync().mode & 0xfff) != 0x180) {
        throw StateError(failure);
      }
      // ln fails atomically if any entry already occupies the public name.
      final link = await Process.run('/usr/bin/ln', [
        '--no-target-directory',
        '--physical',
        '--',
        anchor,
        path,
      ]);
      if (link.exitCode != 0) throw StateError(failure);
      published = true;
      if (_identity(path) != identity) {
        throw StateError(failure);
      }
      return UnixAgentTransport._(
        path,
        server,
        identity,
        handler,
        frameTimeout,
        maxConnections,
      );
    } catch (_) {
      if (server != null) await server.close();
      if (published) _removeOwned(path, identity);
      throw StateError(failure);
    } finally {
      _startingPaths.remove(path);
    }
  }

  // Dart FileStat does not expose inode identity. Linux stat is used without a
  // shell and without printing its output; it lstat-checks the pathname.
  static String? _identity(String path) {
    try {
      if (FileSystemEntity.typeSync(path, followLinks: false) !=
          FileSystemEntityType.unixDomainSock) {
        return null;
      }
      final result = Process.runSync('/usr/bin/stat', [
        '--format=%d:%i',
        '--',
        path,
      ]);
      final value = (result.stdout as String).trim();
      if (result.exitCode != 0 || !RegExp(r'^\d+:\d+$').hasMatch(value)) {
        return null;
      }
      return value;
    } catch (_) {
      return null;
    }
  }

  static void _removeOwned(String path, String? identity) {
    try {
      if (identity != null && _identity(path) == identity) {
        File(path).deleteSync();
      }
    } catch (_) {
      // Refuse to delete a path whose ownership cannot be established.
    }
  }

  Future<void> _serve(Socket socket) async {
    final bytes = <int>[];
    var oversized = false;
    var expired = false;
    Timer? deadline;
    void armDeadline() {
      deadline?.cancel();
      deadline = Timer(_frameTimeout, () {
        expired = true;
        // No rejection claim: a peer may not have observed a previous reply.
        socket.destroy();
      });
    }

    armDeadline();
    try {
      await for (final chunk in socket) {
        for (final byte in chunk) {
          if (_closed || expired) return;
          if (byte == 10) {
            // An active durable handler has no transport deadline.
            deadline?.cancel();
            final response = oversized
                ? _encode(_invalidRequest())
                : await _request(bytes);
            bytes.clear();
            oversized = false;
            if (_closed || expired) return;
            armDeadline();
            await _write(socket, response);
            // One absolute deadline per next frame; incoming partial bytes do
            // not extend it. Writes are bounded too, without timing handlers.
            armDeadline();
          } else if (!oversized) {
            if (bytes.length == maxRequestLineBytes) {
              bytes.clear();
              oversized = true;
            } else {
              bytes.add(byte);
            }
          }
        }
      }
      // An unterminated last line is not a complete JSONL request.
      if (!_closed && !expired && (oversized || bytes.isNotEmpty)) {
        await _write(socket, _encode(_invalidRequest()));
      }
      if (!_closed) await socket.close();
    } catch (_) {
      // Peer disconnects and socket failures have no public diagnostics.
    } finally {
      deadline?.cancel();
      _clients.remove(socket);
      socket.destroy();
    }
  }

  Future<List<int>> _request(List<int> bytes) async {
    Json request;
    try {
      final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
      if (decoded is! Json) return _encode(_invalidRequest());
      request = decoded;
    } catch (_) {
      return _encode(_invalidRequest());
    }
    try {
      final result = await _handler(request);
      // Encode once into a bounded sink before writing any response bytes.
      return _encode(result);
    } catch (_) {
      return _encode(_internalError(request));
    }
  }

  static List<int> _encode(Json response) {
    final sink = _ResponseSink(maxResponseBytes - 1);
    final encoder = JsonUtf8Encoder().startChunkedConversion(sink);
    encoder.add(response);
    encoder.close();
    sink.bytes.add([10]);
    return sink.bytes.takeBytes();
  }

  Future<void> _write(Socket socket, List<int> response) async {
    socket.add(response);
    await socket.flush();
  }

  static Json _invalidRequest() => {
    'protocol_version': 1,
    'request_id': null,
    'scope': null,
    'ok': false,
    'error': {
      'code': 'invalid_request',
      'message': 'Send one UTF-8 JSON object per line, at most 64 KiB.',
      'retryable': false,
      'outcome': 'rejected',
    },
  };

  static Json _internalError(Json request) {
    final requestId = request['request_id'];
    final scope = request['scope'];
    const keys = {'workspace_id', 'company_id', 'device_id'};
    final safeScope =
        scope is Json &&
        scope.length == keys.length &&
        keys.every((key) {
          final value = scope[key];
          return value is String && _identifier.hasMatch(value);
        });
    return {
      'protocol_version': 1,
      'request_id': requestId is String && _identifier.hasMatch(requestId)
          ? requestId
          : null,
      'scope': safeScope ? Map<String, dynamic>.of(scope) : null,
      'ok': false,
      'error': {
        'code': 'internal_error',
        'message': 'The command could not be completed.',
        'retryable': false,
        'outcome': 'unknown',
      },
    };
  }

  /// Stops accepting peers, destroys open connections, drains active handlers,
  /// and removes our original public socket inode. Safe to call more than once.
  /// The private parent remains trusted against same-UID concurrent mutation.
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _closed = true;
    for (final socket in _clients.toList()) {
      socket.destroy();
    }
    await _accepts.cancel();
    await _server.close();
    await Future.wait(_serving.toList());
    _removeOwned(socketPath, _socketIdentity);
  }
}

class _ResponseSink implements Sink<List<int>> {
  _ResponseSink(this.limit);
  final int limit;
  final bytes = BytesBuilder(copy: false);

  @override
  void add(List<int> data) {
    if (bytes.length + data.length > limit) {
      throw StateError('The response exceeds the private transport limit.');
    }
    bytes.add(data);
  }

  @override
  void close() {}
}
