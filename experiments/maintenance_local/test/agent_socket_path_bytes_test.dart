import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/agent_service/unix_transport.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory('/tmp').createTemp('socket-bytes-');
    final protected = await Process.run('/usr/bin/chmod', [
      '700',
      '--',
      root.path,
    ]);
    expect(protected.exitCode, 0);
  });
  tearDown(() async => root.delete(recursive: true));

  String nameWithBytes(int bytes, bool unicode) =>
      unicode ? '${'é' * (bytes ~/ 2)}${bytes.isOdd ? 'x' : ''}' : 'x' * bytes;

  Future<Directory> parentWithBytes(int bytes, bool unicode) async {
    final remaining = bytes - utf8.encode(root.path).length - 1;
    expect(remaining, greaterThan(0));
    final parent = await Directory(
      '${root.path}/${nameWithBytes(remaining, unicode)}',
    ).create();
    final protected = await Process.run('/usr/bin/chmod', [
      '700',
      '--',
      parent.path,
    ]);
    expect(protected.exitCode, 0);
    expect(utf8.encode(parent.path), hasLength(bytes));
    File(
      '${parent.path}/retained',
    ).writeAsStringSync('Keep the synthetic fixture unchanged.', flush: true);
    return parent;
  }

  Map<String, Object> contents(Directory parent) => {
    'parent_mode': parent.statSync().mode,
    for (final entry in parent.listSync(followLinks: false))
      entry.path: {
        'type': FileSystemEntity.typeSync(
          entry.path,
          followLinks: false,
        ).toString(),
        'mode': entry.statSync().mode,
        if (entry is File) 'bytes': entry.readAsBytesSync(),
      },
  };

  Future<void> rejected(String path, Directory parent) async {
    final before = contents(parent);
    var binds = 0;
    await IOOverrides.runZoned(
      () => expectLater(
        UnixAgentTransport.start(
          socketPath: path,
          handler: (_) async => {'ok': true},
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'fixed safe guidance',
            'The private local agent socket could not be started.',
          ),
        ),
      ),
      serverSocketBind:
          (address, port, {backlog = 0, v6Only = false, shared = false}) {
            binds++;
            throw StateError('Synthetic bind spy must not be reached.');
          },
    );
    expect(
      binds,
      0,
      reason: 'Both byte bounds must be checked before binding.',
    );
    expect(contents(parent), before);
    expect(
      FileSystemEntity.typeSync(path, followLinks: false),
      FileSystemEntityType.notFound,
    );
    expect(
      parent.listSync().where(
        (entry) => entry.uri.pathSegments.last.startsWith('.agent-'),
      ),
      isEmpty,
    );
  }

  for (final unicode in [false, true]) {
    final encoding = unicode ? 'Unicode' : 'ASCII';
    test(
      '$encoding 83-byte parent and 107-byte public/anchor paths are usable',
      () async {
        final parent = await parentWithBytes(83, unicode);
        final before = contents(parent);
        final path = '${parent.path}/${nameWithBytes(23, unicode)}';
        expect(utf8.encode(path), hasLength(107));
        final transport = await UnixAgentTransport.start(
          socketPath: path,
          handler: (_) async => {'ok': true},
        );
        Socket? peer;
        try {
          expect(parent.statSync().mode & 0xfff, 0x1c0);
          expect(File(path).statSync().mode & 0xfff, 0x180);
          final anchors = parent
              .listSync()
              .where(
                (entry) => entry.uri.pathSegments.last.startsWith('.agent-'),
              )
              .toList();
          expect(anchors, hasLength(1));
          expect(utf8.encode(anchors.single.path), hasLength(107));
          expect(anchors.single.statSync().mode & 0xfff, 0x180);
          peer = await Socket.connect(
            InternetAddress(path, type: InternetAddressType.unix),
            0,
          );
          final reply = peer
              .cast<List<int>>()
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .first;
          peer.add(utf8.encode('{}\n'));
          await peer.flush();
          expect(jsonDecode(await reply.timeout(const Duration(seconds: 5))), {
            'ok': true,
          });
        } finally {
          peer?.destroy();
          await transport.close();
        }
        expect(contents(parent), before);
      },
    );

    test(
      '$encoding 84-byte parent refuses its 108-byte anchor without mutation',
      () async {
        final parent = await parentWithBytes(84, unicode);
        final path = '${parent.path}/s';
        expect(utf8.encode(path), hasLength(86));
        expect(
          utf8.encode('${parent.path}/.agent-${'a' * 16}'),
          hasLength(108),
        );
        await rejected(path, parent);
      },
    );

    test(
      '$encoding 108-byte public path is refused with a usable short anchor',
      () async {
        final parent = await parentWithBytes(60, unicode);
        final path = '${parent.path}/${nameWithBytes(47, unicode)}';
        expect(utf8.encode(path), hasLength(108));
        expect(utf8.encode('${parent.path}/.agent-${'a' * 16}'), hasLength(84));
        await rejected(path, parent);
      },
    );
  }
}
