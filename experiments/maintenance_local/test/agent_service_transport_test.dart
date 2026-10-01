import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/agent_service/unix_transport.dart';
import 'package:maintenance_local/model.dart';

class _Peer {
  final Socket socket;
  final StreamIterator<String> _lines;

  _Peer(this.socket)
    : _lines = StreamIterator(
        socket
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter()),
      );

  static Future<_Peer> connect(String path) async => _Peer(
    await Socket.connect(
      InternetAddress(path, type: InternetAddressType.unix),
      0,
    ),
  );

  Future<void> send(List<int> bytes) async {
    socket.add(bytes);
    await socket.flush();
  }

  Future<Json> next() async {
    expect(await _lines.moveNext().timeout(const Duration(seconds: 5)), isTrue);
    return jsonDecode(_lines.current) as Json;
  }

  Future<void> close() async {
    socket.destroy();
    await _lines.cancel();
  }
}

void main() {
  group('private Unix JSONL transport', () {
    late Directory root;
    late String path;
    final transports = <UnixAgentTransport>[];
    final peers = <_Peer>[];

    setUp(() async {
      // Short Linux socket names and no real application workspace/data.
      root = await Directory('/tmp').createTemp('agent-transport-');
      final chmod = await Process.run('/usr/bin/chmod', [
        '700',
        '--',
        root.path,
      ]);
      expect(chmod.exitCode, 0);
      path = '${root.path}/service.sock';
    });

    tearDown(() async {
      for (final peer in peers) {
        await peer.close();
      }
      peers.clear();
      for (final transport in transports) {
        await transport.close();
      }
      transports.clear();
      await root.delete(recursive: true);
    });

    Future<UnixAgentTransport> start([
      Future<Json> Function(Json)? handler,
      Duration frameTimeout = const Duration(seconds: 10),
      int maxConnections = 64,
    ]) async {
      final transport = await UnixAgentTransport.start(
        socketPath: path,
        handler: handler ?? (request) async => {'ok': true},
        frameTimeout: frameTimeout,
        maxConnections: maxConnections,
      );
      transports.add(transport);
      return transport;
    }

    Future<_Peer> peer() async {
      final result = await _Peer.connect(path);
      peers.add(result);
      return result;
    }

    void invalid(Json value) {
      expect(value, {
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
      });
    }

    test(
      'private permissions, idle close, own path removal, idempotent close',
      () async {
        final transport = await start();
        expect(transport.socketPath, path);
        expect(root.statSync().mode & 0xfff, 0x1c0);
        expect(File(path).statSync().mode & 0xfff, 0x180);
        expect(
          FileSystemEntity.typeSync(path, followLinks: false),
          FileSystemEntityType.unixDomainSock,
        );
        final client = await peer();
        await client.send(utf8.encode('{"partial":'));
        await transport.close().timeout(const Duration(seconds: 5));
        await transport.close();
        expect(
          FileSystemEntity.typeSync(path, followLinks: false),
          FileSystemEntityType.notFound,
        );
      },
    );

    test(
      'connection cap refuses excess peers and admits a released slot',
      () async {
        var calls = 0;
        await start(
          (request) async => {'calls': ++calls},
          const Duration(seconds: 10),
          2,
        );
        final first = await peer();
        await first.send(utf8.encode('{}\n'));
        expect(await first.next(), {'calls': 1});
        final second = await peer();
        await second.send(utf8.encode('{}\n'));
        expect(await second.next(), {'calls': 2});
        final excess = await peer();
        expect(
          await excess._lines.moveNext().timeout(const Duration(seconds: 5)),
          isFalse,
        );
        expect(calls, 2);
        // Half-close and observe the server's EOF before trying the released slot.
        await first.socket.close();
        expect(
          await first._lines.moveNext().timeout(const Duration(seconds: 5)),
          isFalse,
        );
        final replacement = await peer();
        await replacement.send(utf8.encode('{}\n'));
        expect(await replacement.next(), {'calls': 3});
      },
    );

    test(
      'connection cap accepts only the bounded range 1 through 64',
      () async {
        for (final limit in [-1, 0, 65]) {
          await expectLater(
            UnixAgentTransport.start(
              socketPath: path,
              handler: (request) async => {},
              maxConnections: limit,
            ),
            throwsStateError,
          );
          expect(
            FileSystemEntity.typeSync(path, followLinks: false),
            FileSystemEntityType.notFound,
          );
        }
      },
    );

    test(
      'idle and partial frames expire silently without invoking handlers',
      () async {
        var calls = 0;
        for (final partial in ['', '{"partial":']) {
          final transport = await start(
            (request) async => {'calls': ++calls},
            const Duration(milliseconds: 80),
          );
          final client = await peer();
          if (partial.isNotEmpty) await client.send(utf8.encode(partial));
          expect(
            await client._lines.moveNext().timeout(const Duration(seconds: 5)),
            isFalse,
          );
          expect(calls, 0);
          await transport.close();
        }
      },
    );

    test(
      'a slow active handler survives the framing deadline and returns normally',
      () async {
        final entered = Completer<void>();
        final release = Completer<void>();
        final transport = await start((request) async {
          entered.complete();
          await release.future;
          return {'ok': true};
        }, const Duration(milliseconds: 40));
        final client = await peer();
        await client.send(utf8.encode('{}\n'));
        await entered.future.timeout(const Duration(seconds: 5));
        await Future<void>.delayed(const Duration(milliseconds: 120));
        release.complete();
        expect(await client.next(), {'ok': true});
        await transport.close();
      },
    );

    test(
      'response bytes including newline are bounded and oversize has unknown outcome',
      () async {
        var calls = 0;
        await start((request) async {
          calls++;
          if (calls == 1) {
            return {'text': 'x' * (UnixAgentTransport.maxResponseBytes - 12)};
          }
          if (calls == 2) {
            return {'text': 'é' * (UnixAgentTransport.maxResponseBytes ~/ 2)};
          }
          return {'ok': true};
        });
        final client = await peer();
        final request = {
          'request_id': 'req-1',
          'scope': {
            'workspace_id': 'workspace',
            'company_id': 'company',
            'device_id': 'device',
          },
        };
        await client.send(utf8.encode('${jsonEncode(request)}\n'));
        final exact = await client.next();
        expect(
          utf8.encode('${jsonEncode(exact)}\n').length,
          UnixAgentTransport.maxResponseBytes,
        );
        await client.send(utf8.encode('${jsonEncode(request)}\n{}\n'));
        final oversized = await client.next();
        expect(oversized['request_id'], request['request_id']);
        expect(oversized['scope'], request['scope']);
        expect(oversized['error'], {
          'code': 'internal_error',
          'message': 'The command could not be completed.',
          'retryable': false,
          'outcome': 'unknown',
        });
        expect(jsonEncode(oversized), isNot(contains('é')));
        expect(await client.next(), {'ok': true});
      },
    );

    test(
      'fragmented UTF-8 and asynchronous pipelining preserve request order',
      () async {
        final gate = Completer<void>();
        final entered = Completer<void>();
        final calls = <Json>[];
        await start((request) async {
          calls.add(request);
          if (calls.length == 1) {
            entered.complete();
            await gate.future;
          }
          return {'number': calls.length, 'text': request['text']};
        });
        final client = await peer();
        final first = utf8.encode('{"text":"café"}\n');
        final split = first.indexOf(0xc3) + 1;
        await client.send(first.sublist(0, split));
        await client.send([
          ...first.sublist(split),
          ...utf8.encode('{"text":"second"}\n'),
        ]);
        await entered.future.timeout(const Duration(seconds: 5));
        expect(calls, hasLength(1));
        gate.complete();
        expect(await client.next(), {'number': 1, 'text': 'café'});
        expect(await client.next(), {'number': 2, 'text': 'second'});
        expect(calls, hasLength(2));
      },
    );

    test(
      'close drains an active handler before its owner can close storage',
      () async {
        final entered = Completer<void>();
        final release = Completer<void>();
        var handlerFinished = false;
        final transport = await start((request) async {
          entered.complete();
          await release.future;
          handlerFinished = true;
          return {'ok': true};
        });
        final client = await peer();
        await client.send(utf8.encode('{}\n'));
        await entered.future.timeout(const Duration(seconds: 5));
        var closed = false;
        final closing = transport.close().then((_) => closed = true);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(closed, isFalse);
        release.complete();
        await closing.timeout(const Duration(seconds: 5));
        expect(handlerFinished, isTrue);
        expect(closed, isTrue);
      },
    );

    test(
      'malformed JSON, UTF-8, empty and nonobject lines are safe and isolated',
      () async {
        var calls = 0;
        await start((request) async => {'calls': ++calls});
        final client = await peer();
        await client.send([
          ...utf8.encode('\n{bad}\n[]\nnull\n42\n"text"\n'),
          0xc3,
          0x28,
          10,
          ...utf8.encode('{}\n'),
        ]);
        for (var i = 0; i < 7; i++) {
          invalid(await client.next());
        }
        expect(await client.next(), {'calls': 1});
        expect(calls, 1);
      },
    );

    test(
      'raw byte limit accepts exactly 64 KiB and rejects larger lines',
      () async {
        var calls = 0;
        await start((request) async => {'calls': ++calls});
        final client = await peer();
        final exact = utf8.encode(
          jsonEncode({
            'text': 'x' * (UnixAgentTransport.maxRequestLineBytes - 11),
          }),
        );
        expect(exact, hasLength(UnixAgentTransport.maxRequestLineBytes));
        await client.send([...exact, 10]);
        expect(await client.next(), {'calls': 1});
        await client.send([
          ...exact,
          32,
          10,
          ...utf8.encode(jsonEncode({'text': 'é' * 33000})),
          10,
          ...List.filled(3 * UnixAgentTransport.maxRequestLineBytes, 120),
          10,
          ...utf8.encode('{}\n'),
        ]);
        for (var i = 0; i < 3; i++) {
          invalid(await client.next());
        }
        expect(await client.next(), {'calls': 2});
        expect(calls, 2);
      },
    );

    test('unterminated EOF rejects instead of invoking the handler', () async {
      var calls = 0;
      await start((request) async => {'calls': ++calls});
      final client = await peer();
      await client.send(utf8.encode('{}'));
      await client.socket.close();
      invalid(await client.next());
      expect(calls, 0);
    });

    test(
      'handler and encoding errors are fixed and echo only safe identity',
      () async {
        var calls = 0;
        await start((request) async {
          calls++;
          if (calls == 1) throw StateError('secret-token /private/database');
          if (calls == 2) return {'unencodable': Object()};
          return {'ok': true};
        });
        final client = await peer();
        final scope = {
          'workspace_id': 'workspace-1',
          'company_id': 'company-1',
          'device_id': 'device-1',
        };
        await client.send(
          utf8.encode(
            '${jsonEncode({
              'request_id': 'req-1',
              'scope': scope,
              'credential': {'token': 'secret-token'},
            })}\n${jsonEncode({
              'request_id': '/private/database',
              'scope': {...scope, 'token': 'secret-token'},
            })}\n{}\n',
          ),
        );
        final first = await client.next();
        expect(first, {
          'protocol_version': 1,
          'request_id': 'req-1',
          'scope': scope,
          'ok': false,
          'error': {
            'code': 'internal_error',
            'message': 'The command could not be completed.',
            'retryable': false,
            'outcome': 'unknown',
          },
        });
        final second = await client.next();
        expect(second['request_id'], isNull);
        expect(second['scope'], isNull);
        expect(second['error'], first['error']);
        expect(jsonEncode([first, second]), isNot(contains('secret-token')));
        expect(
          jsonEncode([first, second]),
          isNot(contains('/private/database')),
        );
        expect(await client.next(), {'ok': true});
      },
    );

    test(
      'existing ordinary file is refused without changing bytes or mode',
      () async {
        final existing = File(path)..writeAsStringSync('preserved');
        final mode = existing.statSync().mode;
        await expectLater(start(), throwsStateError);
        expect(existing.readAsStringSync(), 'preserved');
        expect(existing.statSync().mode, mode);
      },
    );

    test(
      'existing directory and dangling symlink are refused intact',
      () async {
        await Directory(path).create();
        await expectLater(start(), throwsStateError);
        expect(Directory(path).existsSync(), isTrue);
        await Directory(path).delete();
        await Link(path).create('${root.path}/missing');
        await expectLater(start(), throwsStateError);
        expect(Link(path).targetSync(), '${root.path}/missing');
        expect(File('${root.path}/missing').existsSync(), isFalse);
      },
    );

    test(
      'existing live Unix socket is refused and its listener stays usable',
      () async {
        final existing = await ServerSocket.bind(
          InternetAddress(path, type: InternetAddressType.unix),
          0,
        );
        final accepted = existing.first;
        try {
          final mode = File(path).statSync().mode;
          await expectLater(start(), throwsStateError);
          expect(File(path).statSync().mode, mode);
          final client = await peer();
          final connection = await accepted.timeout(const Duration(seconds: 5));
          await client.send(utf8.encode('still-present'));
          connection.destroy();
        } finally {
          await existing.close();
        }
      },
    );

    test('linked and nonprivate parents are refused before binding', () async {
      final link = Link('${root.path}/linked');
      await link.create(root.path);
      await expectLater(
        UnixAgentTransport.start(
          socketPath: '${link.path}/other.sock',
          handler: (request) async => {},
        ),
        throwsStateError,
      );
      expect(File('${root.path}/other.sock').existsSync(), isFalse);
      await Process.run('/usr/bin/chmod', ['755', '--', root.path]);
      await expectLater(start(), throwsStateError);
      expect(root.statSync().mode & 0xfff, 0x1ed);
      expect(FileSystemEntity.typeSync(path), FileSystemEntityType.notFound);
    });

    test(
      'close preserves a replacement ordinary file, symlink or socket',
      () async {
        for (final replacement in ['file', 'link', 'socket']) {
          final transport = await start();
          await File(path).delete();
          ServerSocket? other;
          if (replacement == 'file') {
            await File(path).writeAsString('replacement');
          } else if (replacement == 'link') {
            await Link(path).create('${root.path}/missing');
          } else {
            other = await ServerSocket.bind(
              InternetAddress(path, type: InternetAddressType.unix),
              0,
            );
          }
          await transport.close();
          expect(
            FileSystemEntity.typeSync(path, followLinks: false),
            switch (replacement) {
              'file' => FileSystemEntityType.file,
              'link' => FileSystemEntityType.link,
              _ => FileSystemEntityType.unixDomainSock,
            },
          );
          if (replacement == 'file') {
            expect(File(path).readAsStringSync(), 'replacement');
          } else if (replacement == 'link') {
            expect(Link(path).targetSync(), '${root.path}/missing');
          }
          await other?.close();
          if (replacement == 'link') {
            await Link(path).delete();
          } else if (FileSystemEntity.typeSync(path, followLinks: false) !=
              FileSystemEntityType.notFound) {
            await File(path).delete();
          }
        }
      },
    );

    test('simultaneous starts cannot unlink the successful listener', () async {
      final first = start();
      await expectLater(start(), throwsStateError);
      final transport = await first;
      final client = await peer();
      await client.send(utf8.encode('{}\n'));
      expect(await client.next(), {'ok': true});
      expect(
        FileSystemEntity.typeSync(path),
        FileSystemEntityType.unixDomainSock,
      );
      await transport.close();
    });

    test(
      'failed bind and invalid paths have static diagnostics and no path entry',
      () async {
        final tooLong = '${root.path}/${'x' * 120}';
        for (final invalidPath in [tooLong, 'relative.sock', '$path\u0000']) {
          try {
            await UnixAgentTransport.start(
              socketPath: invalidPath,
              handler: (request) async => {},
            );
            fail('Expected a rejected socket path');
          } on StateError catch (error) {
            expect(
              error.message,
              'The private local agent socket could not be started.',
            );
            expect(error.message, isNot(contains(root.path)));
          }
        }
        expect(
          FileSystemEntity.typeSync(tooLong),
          FileSystemEntityType.notFound,
        );
        final transport = await start();
        await transport.close();
      },
    );
  }, skip: !Platform.isLinux);
}
