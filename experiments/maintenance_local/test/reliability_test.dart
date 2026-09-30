import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:maintenance_local/evidence_store.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/local_sync.dart';
import 'package:maintenance_local/model.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';
import 'package:maintenance_local/src/rust/api/documents.dart';

/// A loopback-only TLS fault injector using the synthetic office's identity.
/// Forwarding finishes before the response socket is destroyed, so the sender
/// cannot infer whether a durable write happened from its failed request.
class _LossyOffice {
  _LossyOffice(this.upstream, this.http);
  final OfficeServer upstream;
  final HttpServer http;
  String? loseNextResponse;
  final requests = <({String route, Json body})>[];
  final _connections = <PinnedConnection>{};

  static Future<_LossyOffice> start(
    OfficeServer upstream, {
    int port = 0,
  }) async {
    final http = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      port,
      upstream.identity.context,
    );
    final proxy = _LossyOffice(upstream, http);
    http.listen(proxy._handle);
    return proxy;
  }

  String invitation() => canonical({
    ...jsonDecode(upstream.invitation('127.0.0.1')) as Json,
    'url': 'https://127.0.0.1:${http.port}',
  });

  Future<void> _handle(HttpRequest request) async {
    final route = request.uri.path;
    final connection = PinnedConnection({
      'url': 'https://127.0.0.1:${upstream.port}',
      'fingerprint': upstream.identity.fingerprint,
      'token': request.headers.value('authorization')?.substring(7),
    });
    _connections.add(connection);
    var dropped = false;
    try {
      final body = await readJson(request);
      requests.add((route: route, body: body));
      final result = await connection.request(
        route,
        body,
        authenticated: route != '/pair',
      );
      if (route == loseNextResponse) {
        loseNextResponse = null;
        dropped = true;
        (await request.response.detachSocket(writeHeaders: false)).destroy();
        return;
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(canonical(result));
    } catch (error) {
      if (!dropped) {
        request.response.statusCode = 409;
        request.response.headers.contentType = ContentType.json;
        request.response.write(canonical({'error': error.toString()}));
      }
    } finally {
      connection.close();
      _connections.remove(connection);
      if (!dropped) await request.response.close();
    }
  }

  Future<void> close() async {
    await http.close(force: true);
    for (final connection in _connections.toList()) {
      connection.close();
    }
  }
}

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('Timed out waiting for the test queue barrier.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

void main() {
  setUpAll(
    () async => RustLib.init(
      externalLibrary: ExternalLibrary.open(
        File('rust/target/debug/librust_lib_sync_lab.so').absolute.path,
      ),
    ),
  );
  late Directory root;
  late LabStore office, phone;
  late OfficeServer server;
  late PhoneSync sync;
  _LossyOffice? proxy;
  final extraStores = <LabStore>[];

  setUp(() async {
    root = await Directory.systemTemp.createTemp('vortice-reliability-');
    office = await LabStore.open(
      Directory('${root.path}/office'),
      office: true,
    );
    await office.createWorkspace();
    phone = await LabStore.open(Directory('${root.path}/phone'), office: false);
    server = await OfficeServer.start(office, port: 0);
    sync = PhoneSync(phone);
  });
  tearDown(() async {
    await proxy?.close();
    proxy = null;
    await server.close();
    await phone.close();
    await office.close();
    for (final store in extraStores) {
      await store.close();
    }
    extraStores.clear();
    await root.delete(recursive: true);
  });

  Future<void> connect({bool throughProxy = false}) async {
    if (throughProxy) proxy = await _LossyOffice.start(server);
    await sync.enroll(
      throughProxy ? proxy!.invitation() : server.invitation('127.0.0.1'),
    );
    server.authority.confirm(phone.device);
    await sync.sync();
  }

  Future<Json> submit() async {
    await phone.update({
      'fluid': 'pass',
      'guards': 'attention',
      'meter': 173.25,
      'notes': 'Synthetic reliability fixture: secure the guard.',
    });
    await phone.attach(List.generate(700013, (i) => (i * 17 + 3) % 251));
    return phone.submit();
  }

  Future<void> restartBoth({bool throughProxy = false}) async {
    final officePort = server.port, proxyPort = proxy?.http.port;
    await proxy?.close();
    proxy = null;
    await server.close();
    await phone.close();
    await office.close();
    office = await LabStore.open(
      Directory('${root.path}/office'),
      office: true,
    );
    phone = await LabStore.open(Directory('${root.path}/phone'), office: false);
    server = await OfficeServer.start(office, port: officePort);
    sync = PhoneSync(phone);
    if (throughProxy) {
      proxy = await _LossyOffice.start(server, port: proxyPort!);
    }
  }

  test(
    'Lost TLS chunk response resumes matching bytes after both stores restart',
    () async {
      await connect(throughProxy: true);
      final submission = await submit();
      final hash = (submission['values'] as Json)['photo'] as String;
      final bytes = await phone.evidence.file(hash).readAsBytes();
      proxy!.loseNextResponse = '/blob/put';
      await expectLater(sync.sync(), throwsA(isA<HttpException>()));
      expect(sync.busy, isFalse);
      expect(
        (await office.evidence.status(hash))['offset'],
        EvidenceStore.chunkBytes,
      );
      expect(await office.evidence.complete(hash), isFalse);
      await expectLater(
        office.decide(submission['id'] as String, approve: true),
        throwsStateError,
      );

      await restartBoth(throughProxy: true);
      expect(
        (await office.evidence.status(hash))['offset'],
        EvidenceStore.chunkBytes,
      );
      await sync.sync();
      final chunks = proxy!.requests
          .where((r) => r.route == '/blob/put')
          .toList();
      expect(chunks.first.body['offset'], EvidenceStore.chunkBytes);
      expect(
        await office.evidence.file(hash).readAsBytes(),
        orderedEquals(bytes),
      );
      expect(
        await phone.evidence.file(hash).readAsBytes(),
        orderedEquals(bytes),
      );
      expect(await office.evidence.manifest(), await phone.evidence.manifest());
      expect(await office.approvalProblem(submission), isNull);
      expect(phone.setting('lastCompleteSync'), isNotNull);
    },
  );

  test(
    'Accepted submission with lost TLS response replays exact durable payload',
    () async {
      await connect(throughProxy: true);
      final submission = await submit();
      proxy!.loseNextResponse = '/submit';
      await expectLater(sync.sync(), throwsA(isA<HttpException>()));
      expect(office.submissions.single['id'], submission['id']);
      expect(phone.submissions.single['_state'], 'queued');
      expect(proxy!.requests.last.route, '/submit');
      expect(canonical(proxy!.requests.last.body), canonical(submission));
      final durableDevice = phone.device,
          durablePairing = canonical(sync.pairing);

      await restartBoth(throughProxy: true);
      expect(phone.device, durableDevice);
      expect(canonical(sync.pairing), durablePairing);
      final retriedPayload = await phone.submit();
      expect(canonical(retriedPayload), canonical(submission));
      final retryConnection = PinnedConnection(sync.pairing!);
      try {
        expect(
          (await retryConnection.request(
            '/submit',
            retriedPayload,
          ))['accepted'],
          submission['id'],
        );
      } finally {
        retryConnection.close();
      }
      await sync.sync();
      await sync.sync();
      final replay = proxy!.requests
          .where((r) => r.route == '/submit')
          .toList();
      expect(replay, hasLength(1));
      expect(canonical(replay.single.body), canonical(submission));
      expect(office.submissions, hasLength(1));
      expect(phone.submissions.single['_state'], 'received');
      final receipt = await office.decide(
        submission['id'] as String,
        approve: true,
      );
      await sync.sync();
      expect(
        await office.decide(submission['id'] as String, approve: true),
        receipt,
      );
      expect(office.receipts, hasLength(1));
      expect(phone.receipts.single, receipt);
      expect(
        office.db.select("SELECT * FROM events WHERE kind='reviewed'"),
        hasLength(1),
      );
    },
  );

  test(
    'TLS rejects gaps, changed overlaps, malformed chunks and corrupt completion',
    () async {
      await connect();
      final bytes = List.generate(4099, (i) => (i + 7) % 251);
      final hash = digest(bytes), connection = PinnedConnection(sync.pairing!);
      addTearDown(connection.close);
      Json chunk(int offset, List<int> content, {int? total}) => {
        'hash': hash,
        'offset': offset,
        'total': total ?? bytes.length,
        'bytes': base64Encode(content),
      };
      await connection.request('/blob/put', chunk(0, bytes.sublist(0, 777)));
      for (final bad in [
        chunk(778, bytes.sublist(778, 800)),
        chunk(-1, [7]),
        chunk(777, []),
        chunk(777, [7], total: 0),
        chunk(777, [7], total: EvidenceStore.maxBytes + 1),
        chunk(777, List.filled(EvidenceStore.chunkBytes + 1, 7)),
        chunk(777, [7, 8], total: 778),
        chunk(0, [99, 99]),
        {
          ...chunk(777, [7]),
          'hash': '../invalid',
        },
        {
          ...chunk(777, [7]),
          'bytes': '%%%invalid-base64',
        },
      ]) {
        await expectLater(
          connection.request('/blob/put', bad),
          throwsStateError,
        );
        expect((await office.evidence.status(hash))['offset'], 777);
        expect(await office.evidence.complete(hash), isFalse);
      }
      // A matching overlapping retry adds only the suffix; it never duplicates bytes.
      await connection.request(
        '/blob/put',
        chunk(700, bytes.sublist(700, 1200)),
      );
      expect((await office.evidence.status(hash))['offset'], 1200);
      final corruptTail = bytes.sublist(1200)..[0] = 255;
      await expectLater(
        connection.request('/blob/put', chunk(1200, corruptTail)),
        throwsStateError,
      );
      expect((await office.evidence.status(hash))['offset'], 0);
      expect(await office.evidence.manifest(), isEmpty);
      await connection.request('/blob/put', chunk(0, bytes));
      expect(
        await office.evidence.file(hash).readAsBytes(),
        orderedEquals(bytes),
      );
      await expectLater(
        connection.request('/blob/put', chunk(0, [99])),
        throwsStateError,
      );
      await expectLater(
        connection.request(
          '/blob/put',
          chunk(0, bytes, total: bytes.length + 1),
        ),
        throwsStateError,
      );
      expect(
        await office.evidence.file(hash).readAsBytes(),
        orderedEquals(bytes),
      );
    },
  );

  test(
    'Corrupt stored photo blocks approval and retries restore exact original bytes',
    () async {
      await connect();
      final submission = await submit();
      await sync.sync();
      final hash = (submission['values'] as Json)['photo'] as String;
      final original = await phone.evidence.file(hash).readAsBytes();
      await office.evidence.file(hash).writeAsBytes([9, 8, 7], flush: true);
      expect(await office.evidence.complete(hash), isFalse);
      expect(await office.evidence.manifest(), isEmpty);
      await expectLater(
        office.decide(submission['id'] as String, approve: true),
        throwsStateError,
      );
      expect(office.receipts, isEmpty);
      await sync.sync();
      expect(
        await office.evidence.file(hash).readAsBytes(),
        orderedEquals(original),
      );
      expect(await office.approvalProblem(submission), isNull);
      expect(office.submissions, hasLength(1));
    },
  );

  test(
    'All protected TLS endpoints deny missing, wrong, pending and revoked tokens',
    () async {
      await connect();
      final submission = await submit();
      final hash = (submission['values'] as Json)['photo'] as String;
      final pending = await LabStore.open(
        Directory('${root.path}/pending'),
        office: false,
      );
      extraStores.add(pending);
      final pendingSync = PhoneSync(pending);
      await pendingSync.enroll(server.invitation('127.0.0.1'));
      final pairing = sync.pairing!;
      server.authority.revoke(phone.device);
      final routes = <String, Json>{
        '/bundle': {},
        '/sync': {'session': secret(), 'message': null},
        '/submit': submission,
        '/blob/status': {'hash': hash},
        '/blob/get': {'hash': hash, 'offset': 0},
        '/blob/put': {
          'hash': hash,
          'offset': 0,
          'total': 1,
          'bytes': base64Encode([3]),
        },
      };
      final before = office.document!.toList();
      for (final mode in ['missing', 'wrong', 'pending', 'revoked']) {
        final connection = PinnedConnection(switch (mode) {
          'wrong' => {...pairing, 'token': secret()},
          'pending' => pendingSync.pairing!,
          _ => pairing,
        });
        try {
          for (final entry in routes.entries) {
            await expectLater(
              connection.request(
                entry.key,
                entry.value,
                authenticated: mode != 'missing',
              ),
              throwsA(
                isA<StateError>().having(
                  (e) => e.message,
                  'authentication rejection',
                  contains(
                    mode == 'missing'
                        ? 'credential is required'
                        : 'awaiting confirmation or has been revoked',
                  ),
                ),
              ),
              reason: '$mode credential on ${entry.key}',
            );
          }
        } finally {
          connection.close();
        }
      }
      expect(office.document!, orderedEquals(before));
      expect(office.submissions, isEmpty);
      expect(office.receipts, isEmpty);
      expect(await office.evidence.manifest(), isEmpty);
      expect((await office.evidence.status(hash))['offset'], 0);
    },
  );

  test(
    'Revocation while a TLS submission is queued prevents its durable write',
    () async {
      await connect();
      final submission = await submit();
      final connection = PinnedConnection(sync.pairing!);
      addTearDown(connection.close);
      final entered = Completer<void>(), release = Completer<void>();
      final blocker = office.queue.run(() async {
        entered.complete();
        await release.future;
      });
      await entered.future;
      final blockedTail = office.queue.idle;
      // Observe the queue's tail change, rather than guessing when the server has
      // authenticated and queued this complete request body.
      final request = connection.request('/submit', submission);
      final rejected = expectLater(request, throwsStateError);
      try {
        await _until(() => !identical(office.queue.idle, blockedTail));
        server.authority.revoke(phone.device);
      } finally {
        release.complete();
      }
      await blocker;
      await rejected;
      await office.queue.idle;
      expect(office.submissions, isEmpty);
      expect(office.receipts, isEmpty);
    },
  );

  test(
    'Revocation while a TLS photo chunk is queued prevents evidence writes',
    () async {
      await connect();
      final bytes = List.generate(4099, (i) => i % 251), hash = digest(bytes);
      final connection = PinnedConnection(sync.pairing!);
      addTearDown(connection.close);
      final entered = Completer<void>(), release = Completer<void>();
      final blocker = office.queue.run(() async {
        entered.complete();
        await release.future;
      });
      await entered.future;
      final blockedTail = office.queue.idle;
      final rejected = expectLater(
        connection.request('/blob/put', {
          'hash': hash,
          'offset': 0,
          'total': bytes.length,
          'bytes': base64Encode(bytes.sublist(0, 777)),
        }),
        throwsStateError,
      );
      try {
        await _until(() => !identical(office.queue.idle, blockedTail));
        server.authority.revoke(phone.device);
      } finally {
        release.complete();
      }
      await blocker;
      await rejected;
      await office.queue.idle;
      expect((await office.evidence.status(hash))['offset'], 0);
      expect(await office.evidence.file(hash).exists(), isFalse);
      expect(
        await File('${office.evidence.file(hash).path}.part').exists(),
        isFalse,
      );
      expect(await office.evidence.manifest(), isEmpty);
    },
  );

  test(
    'Revocation while TLS status is queued retains an unpublished complete partial',
    () async {
      await connect();
      final bytes = List.generate(4099, (i) => (i + 13) % 251);
      final hash = digest(bytes);
      await office.evidence.root.create(recursive: true);
      final partial = File('${office.evidence.file(hash).path}.part');
      await partial.writeAsBytes(bytes, flush: true);
      final connection = PinnedConnection(sync.pairing!);
      addTearDown(connection.close);
      final entered = Completer<void>(), release = Completer<void>();
      final blocker = office.queue.run(() async {
        entered.complete();
        await release.future;
      });
      await entered.future;
      final blockedTail = office.queue.idle;
      final rejected = expectLater(
        connection.request('/blob/status', {'hash': hash}),
        throwsStateError,
      );
      try {
        await _until(() => !identical(office.queue.idle, blockedTail));
        server.authority.revoke(phone.device);
      } finally {
        release.complete();
      }
      await blocker;
      await rejected;
      await office.queue.idle;
      // Do not call status here: a local status call would itself publish the
      // completed partial and conceal the side effect being checked.
      expect(await partial.exists(), isTrue);
      expect(await partial.readAsBytes(), orderedEquals(bytes));
      expect(await office.evidence.file(hash).exists(), isFalse);
      expect(await office.evidence.complete(hash), isFalse);
      expect(await office.evidence.manifest(), isEmpty);
    },
  );

  test(
    'Revocation during photo IO retains matching partial bytes without publication',
    () async {
      await connect();
      final bytes = List.generate(100003, (i) => (i * 19 + 5) % 251);
      final hash = digest(bytes);
      final bearer = 'Bearer ${sync.pairing!['token']}';
      var checks = 0, revoked = false;
      await expectLater(
        office.evidence.append(
          hash,
          0,
          bytes.length,
          bytes,
          checkAuthority: () {
            server.authority.authenticate(bearer);
            checks++;
            if (checks == 2) {
              // Revoke after pre-write authentication. The following async
              // disk operations allow this microtask to run before publication.
              scheduleMicrotask(() {
                server.authority.revoke(phone.device);
                revoked = true;
              });
            }
          },
        ),
        throwsStateError,
      );
      expect(revoked, isTrue);
      expect(() => server.authority.authenticate(bearer), throwsStateError);
      final partial = File('${office.evidence.file(hash).path}.part');
      expect(await partial.exists(), isTrue);
      expect(await partial.readAsBytes(), orderedEquals(bytes));
      expect(await office.evidence.file(hash).exists(), isFalse);
      expect(await office.evidence.complete(hash), isFalse);
      expect(await office.evidence.manifest(), isEmpty);
    },
  );

  test(
    'Revocation while an Automerge packet is queued preserves the office draft',
    () async {
      await connect();
      await phone.update({
        'notes': 'Revoked phone packet must never be applied.',
      });
      final connection = PinnedConnection(sync.pairing!);
      addTearDown(connection.close);
      final state = await newSession(), session = secret();
      final first = await state.step(bytes: phone.document!, incoming: null);
      final reply = await connection.request('/sync', {
        'session': session,
        'message': base64Encode(first.message!),
      });
      final changes = await state.step(
        bytes: first.document,
        incoming: base64Decode(reply['message'] as String),
      );
      expect(changes.message, isNotNull);
      final before = office.document!.toList();
      final entered = Completer<void>(), release = Completer<void>();
      final blocker = office.queue.run(() async {
        entered.complete();
        await release.future;
      });
      await entered.future;
      final blockedTail = office.queue.idle;
      final rejected = expectLater(
        connection.request('/sync', {
          'session': session,
          'message': base64Encode(changes.message!),
        }),
        throwsStateError,
      );
      try {
        await _until(() => !identical(office.queue.idle, blockedTail));
        server.authority.revoke(phone.device);
      } finally {
        release.complete();
      }
      await blocker;
      await rejected;
      await office.queue.idle;
      expect(office.document!, orderedEquals(before));
      expect(valuesOf(await office.fields())['notes'], '');
    },
  );

  test(
    'Revocation during a streamed TLS request body prevents submission',
    () async {
      await connect();
      final submission = await submit();
      final connection = PinnedConnection(sync.pairing!);
      addTearDown(connection.close);
      final encoded = utf8.encode(canonical(submission));
      final request = await connection.client.postUrl(
        Uri.parse(sync.pairing!['url'] as String).replace(path: '/submit'),
      );
      request.headers.contentType = ContentType.json;
      request.headers.set('authorization', 'Bearer ${sync.pairing!['token']}');
      request.contentLength = encoded.length;
      request.bufferOutput = false;
      final split = encoded.length ~/ 2;
      request.add(encoded.sublist(0, split));
      await request.flush();
      server.authority.revoke(phone.device);
      request.add(encoded.sublist(split));
      final response = await request.close();
      expect(response.statusCode, 409);
      expect((await readJson(response))['error'], contains('has been revoked'));
      expect(office.submissions, isEmpty);
      expect(office.receipts, isEmpty);
    },
  );

  test(
    'A newer SQLite schema is rejected without changing its bytes or metadata',
    () async {
      final futureRoot = Directory('${root.path}/future-schema');
      await futureRoot.create();
      final file = File('${futureRoot.path}/workspace.sqlite');
      final database = sqlite3.open(file.path);
      database.execute('PRAGMA user_version=999');
      database.execute('CREATE TABLE future_only (meaning TEXT NOT NULL)');
      database.execute(
        "INSERT INTO future_only VALUES ('preserve future data')",
      );
      database.close();
      final before = await file.readAsBytes();
      await expectLater(
        LabStore.open(futureRoot, office: true),
        throwsStateError,
      );
      expect(await file.readAsBytes(), orderedEquals(before));
      final reopened = sqlite3.open(file.path);
      try {
        expect(
          reopened.select('PRAGMA user_version').single['user_version'],
          999,
        );
        expect(
          reopened.select('PRAGMA journal_mode').single['journal_mode'],
          'delete',
        );
        expect(
          reopened.select('SELECT meaning FROM future_only').single['meaning'],
          'preserve future data',
        );
        expect(
          reopened
              .select("SELECT name FROM sqlite_master WHERE type='table'")
              .map((r) => r['name']),
          ['future_only'],
        );
      } finally {
        reopened.close();
      }
    },
  );
}
