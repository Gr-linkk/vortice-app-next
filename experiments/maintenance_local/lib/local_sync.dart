import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'device_authority.dart';
import 'lab_store.dart';
import 'model.dart';
import 'src/rust/api/documents.dart';

String connectionProblem(Object error) {
  if (error is HandshakeException || error is TlsException) {
    return 'The computer identity could not be verified. Use an invitation from the same office computer or restore its verified backup.';
  }
  if (error is SocketException ||
      error is TimeoutException ||
      error is HttpException) {
    return 'Cannot reach the computer. Keep both apps open on the same Wi-Fi, check its selected address, and retry. The computer must accept the local connection on TCP 47841.';
  }
  if (error is FormatException || error is TypeError) {
    return 'The invitation or saved connection is incomplete. Paste a fresh complete invitation from the same computer.';
  }
  return error.toString().replaceFirst('Bad state: ', '');
}

bool localAddress(String host) {
  final ip = InternetAddress.tryParse(host);
  if (ip == null || ip.type != InternetAddressType.IPv4) return false;
  final b = ip.rawAddress;
  return b[0] == 10 ||
      b[0] == 127 ||
      (b[0] == 192 && b[1] == 168) ||
      (b[0] == 172 && b[1] >= 16 && b[1] <= 31);
}

class OfficeIdentity {
  OfficeIdentity(this.context, this.fingerprint);
  final SecurityContext context;
  final String fingerprint;
  static Future<OfficeIdentity> load(LabStore store) async {
    store.requireOffice();
    final key = File('${store.root.path}/office-key.pem'),
        cert = File('${store.root.path}/office-cert.pem');
    final hasKey = await key.exists(), hasCert = await cert.exists();
    final expected = store.setting('officeFingerprint');
    if (hasKey != hasCert ||
        (!hasKey &&
            (expected != null ||
                store.db.select('SELECT id FROM phones LIMIT 1').isNotEmpty ||
                store.db
                    .select('SELECT hash FROM invites LIMIT 1')
                    .isNotEmpty ||
                store.receipts.isNotEmpty))) {
      throw StateError(
        'The computer identity is incomplete. Files have been retained. Restore a verified office backup; a new identity cannot reconnect existing phones.',
      );
    }
    if (!hasKey) {
      final result = await Process.run('openssl', [
        'req',
        '-x509',
        '-newkey',
        'ec',
        '-pkeyopt',
        'ec_paramgen_curve:P-256',
        '-nodes',
        '-days',
        '36500',
        '-subj',
        '/CN=Vortice Sync Lab local office',
        '-keyout',
        '${key.path}.new',
        '-out',
        '${cert.path}.new',
      ]);
      if (result.exitCode != 0) {
        throw StateError(
          'Cannot create the local computer identity. Check that OpenSSL is installed and the workspace is writable.',
        );
      }
      await Process.run('chmod', [
        '600',
        '${key.path}.new',
        '${cert.path}.new',
      ]);
      await File('${key.path}.new').rename(key.path);
      await File('${cert.path}.new').rename(cert.path);
    }
    try {
      final pem = await cert.readAsString();
      final der = base64Decode(
        pem.replaceAll(RegExp(r'-----[^-]+-----|\s'), '').trim(),
      );
      final fingerprint = digest(der);
      if (expected != null && expected != fingerprint) {
        throw StateError('Stored computer identity does not match.');
      }
      final publicCert = await Process.run('openssl', [
        'x509',
        '-in',
        cert.path,
        '-pubkey',
        '-noout',
      ]);
      final publicKey = await Process.run('openssl', [
        'pkey',
        '-in',
        key.path,
        '-pubout',
      ]);
      if (publicCert.exitCode != 0 ||
          publicKey.exitCode != 0 ||
          publicCert.stdout != publicKey.stdout) {
        throw StateError('Computer certificate and key do not match.');
      }
      final ctx = SecurityContext()
        ..useCertificateChain(cert.path)
        ..usePrivateKey(key.path);
      ctx.minimumTlsProtocolVersion = TlsProtocolVersion.tls1_2;
      store.setSetting('officeFingerprint', fingerprint);
      return OfficeIdentity(ctx, fingerprint);
    } catch (_) {
      throw StateError(
        'The computer identity could not be verified. Files have been retained. Restore a verified office backup.',
      );
    }
  }
}

Future<Json> readJson(Stream<List<int>> stream) async {
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    bytes.add(chunk);
    if (bytes.length > 32 * 1024 * 1024) {
      throw StateError('Message exceeds the lab limit.');
    }
  }
  return jsonDecode(utf8.decode(bytes.takeBytes())) as Json;
}

class OfficeServer {
  OfficeServer._(this.store, this.identity, this.server)
    : authority = DeviceAuthority(store);
  final LabStore store;
  final OfficeIdentity identity;
  final HttpServer server;
  final DeviceAuthority authority;
  final _sessions = <String, ({String id, DocumentSession state})>{};
  void Function()? onChange;
  int get port => server.port;
  static Future<OfficeServer> start(
    LabStore store, {
    int port = 47841,
    InternetAddress? address,
  }) async {
    final identity = await OfficeIdentity.load(store);
    final http = await HttpServer.bindSecure(
      address ?? InternetAddress.anyIPv4,
      port,
      identity.context,
    );
    http.idleTimeout = const Duration(seconds: 15);
    final server = OfficeServer._(store, identity, http);
    http.listen(server._handle);
    return server;
  }

  String invitation(String host) {
    if (!localAddress(host)) {
      throw StateError('Choose the local Wi-Fi IPv4 address.');
    }
    return canonical({
      'v': 1,
      'url': 'https://$host:$port',
      'fingerprint': identity.fingerprint,
      'companyId': store.workspace!['companyId'],
      'invitation': authority.invite(),
    });
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      if (!localAddress(request.connectionInfo?.remoteAddress.address ?? '')) {
        throw StateError('Only local network devices are supported.');
      }
      if (request.method != 'POST') {
        request.response.statusCode = 405;
        return;
      }
      final path = request.uri.path;
      String? device;
      if (path != '/pair') {
        device = authority.authenticate(request.headers.value('authorization'));
      }
      final p = await readJson(request).timeout(const Duration(seconds: 20));
      // A revocation while a request body is arriving must also take effect.
      if (device != null) {
        authority.authenticate(request.headers.value('authorization'));
      }
      void checkAuthority() {
        if (device != null) {
          authority.authenticate(request.headers.value('authorization'));
        }
      }

      final Json result;
      switch (path) {
        case '/pair':
          result = authority.request(p);
        case '/bundle':
          result = await store.queue.run(() async {
            checkAuthority();
            return store.publicBundle();
          });
        case '/sync':
          result = await store.queue.run(() async {
            checkAuthority();
            final id = p['session'] as String;
            if (id.length > 100) throw StateError('Invalid sync session.');
            final jobId = store.realWorkspace ? p['jobId'] as String : null;
            if (store.realWorkspace) store.jobContextFor(jobId!);
            if (p.keys.toSet().difference({
              'session',
              'message',
              if (store.realWorkspace) 'jobId',
            }).isNotEmpty) {
              throw StateError('Invalid sync operation.');
            }
            final sessionKey = store.realWorkspace ? '$device:$jobId' : device!;
            var entry = _sessions[sessionKey];
            if (entry == null || entry.id != id) {
              entry = (id: id, state: await newSession());
              _sessions[sessionKey] = entry;
            }
            try {
              final packet = await entry.state.step(
                bytes: jobId == null
                    ? store.document!
                    : store.documentFor(jobId)!,
                incoming: p['message'] == null
                    ? null
                    : base64Decode(p['message'] as String),
              );
              store.validateFields(
                jsonDecode(await documentValues(bytes: packet.document))
                    as Json,
                jobId: jobId,
              );
              checkAuthority();
              store.transaction(
                () => store.saveDocument(packet.document, jobId: jobId),
              );
              return {
                'message': packet.message == null
                    ? null
                    : base64Encode(packet.message!),
              };
            } catch (_) {
              _sessions.remove(sessionKey);
              rethrow;
            }
          });
        case '/submit':
          await store.acceptSubmission(
            p,
            device!,
            checkAuthority: checkAuthority,
          );
          result = {'accepted': p['id']};
        case '/blob/status':
          result = await store.queue.run(() async {
            checkAuthority();
            if (store.realWorkspace &&
                !(await store.requiredEvidence()).contains(p['hash'])) {
              throw StateError(
                'Photo is not referenced by this company’s work.',
              );
            }
            checkAuthority();
            return store.evidence.status(
              p['hash'] as String,
              checkAuthority: checkAuthority,
            );
          });
        case '/blob/put':
          result = await store.queue.run(() async {
            checkAuthority();
            if (store.realWorkspace &&
                !(await store.requiredEvidence()).contains(p['hash'])) {
              throw StateError(
                'Photo is not referenced by this company’s work.',
              );
            }
            checkAuthority();
            await store.evidence.append(
              p['hash'] as String,
              p['offset'] as int,
              p['total'] as int,
              base64Decode(p['bytes'] as String),
              checkAuthority: checkAuthority,
            );
            checkAuthority();
            return store.evidence.status(
              p['hash'] as String,
              checkAuthority: checkAuthority,
            );
          });
        case '/blob/get':
          result = await store.queue.run(() async {
            checkAuthority();
            if (store.realWorkspace &&
                !(await store.requiredEvidence()).contains(p['hash'])) {
              throw StateError(
                'Photo is not referenced by this company’s work.',
              );
            }
            checkAuthority();
            final bytes = await store.evidence.chunk(
              p['hash'] as String,
              p['offset'] as int,
            );
            checkAuthority();
            return {'bytes': base64Encode(bytes)};
          });
        default:
          throw StateError('Unknown local operation.');
      }
      if (device != null) {
        authority.authenticate(request.headers.value('authorization'));
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(canonical(result));
      onChange?.call();
    } catch (error) {
      request.response.statusCode = 409;
      request.response.headers.contentType = ContentType.json;
      request.response.write(canonical({'error': error.toString()}));
    } finally {
      await request.response.close();
    }
  }

  Future<void> close() async {
    await server.close(force: true);
    _sessions.clear();
  }
}

class PinnedConnection {
  PinnedConnection(this.pair)
    : client = HttpClient(context: SecurityContext(withTrustedRoots: false)) {
    final url = Uri.parse(pair['url'] as String);
    if (url.scheme != 'https' ||
        !localAddress(url.host) ||
        url.userInfo.isNotEmpty ||
        (url.path.isNotEmpty && url.path != '/') ||
        url.hasQuery ||
        url.hasFragment ||
        !hashPattern.hasMatch(pair['fingerprint'] as String)) {
      throw StateError('Invalid local office invitation.');
    }
    client.connectionTimeout = const Duration(seconds: 5);
    client.badCertificateCallback = (cert, host, port) =>
        host == url.host &&
        port == url.port &&
        digest(cert.der) == pair['fingerprint'];
  }
  final Json pair;
  final HttpClient client;
  Future<Json> request(
    String path,
    Json body, {
    bool authenticated = true,
  }) async {
    final uri = Uri.parse(pair['url'] as String).replace(path: path);
    final req = await client.postUrl(uri);
    req.followRedirects = false;
    req.headers.contentType = ContentType.json;
    if (authenticated) {
      req.headers.set('authorization', 'Bearer ${pair['token']}');
    }
    req.write(canonical(body));
    final response = await req.close().timeout(const Duration(seconds: 20));
    final data = await readJson(response).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw StateError(data['error'] as String? ?? 'Office connection failed.');
    }
    return data;
  }

  void close() => client.close(force: true);
}

class PhoneSync {
  PhoneSync(this.store);
  final LabStore store;
  bool busy = false;
  String message = 'Saved on this phone.';
  void Function()? onChange;
  Json? get pairing => store.setting('pairing') as Json?;
  Future<void> enroll(
    String invitation, {
    String label = 'Inspection phone',
  }) async {
    if (store.office) throw StateError('Only phones enroll.');
    final Json p;
    try {
      p = jsonDecode(invitation.trim()) as Json;
    } catch (_) {
      throw StateError(
        'Paste the complete invitation copied from the computer.',
      );
    }
    if (p['v'] != 1 ||
        p['invitation'] is! String ||
        p['companyId'] is! String) {
      throw StateError('Unsupported invitation.');
    }
    if (store.workspace != null &&
        store.workspace!['companyId'] != p['companyId']) {
      throw StateError('Different company. Your saved work has been retained.');
    }
    // Persist this operation's exact identity and secret before the uncertain request.
    // Re-pasting the same invitation must not mint another identity on retry.
    final old = pairing;
    if (old != null &&
        old['companyId'] == p['companyId'] &&
        old['fingerprint'] != p['fingerprint']) {
      throw StateError(
        'The computer identity changed. Your saved work and existing connection have been retained.',
      );
    }
    final sameOffice =
        old != null &&
        old['fingerprint'] == p['fingerprint'] &&
        old['companyId'] == p['companyId'];
    final candidate = sameOffice
        ? <String, dynamic>{
            ...old,
            'url': p['url'],
            'invitation': p['invitation'],
          }
        : <String, dynamic>{
            ...p,
            'device': store.device,
            'label': label,
            'token': secret(),
          };
    final connection = PinnedConnection(candidate);
    try {
      store.setSetting('pairing', candidate);
      await _pair(connection, candidate);
    } finally {
      connection.close();
    }
  }

  Future<bool> _pair(PinnedConnection c, Json p) async {
    final response = await c.request('/pair', {
      'device': store.device,
      'label': p['label'],
      'token': p['token'],
      'invitation': p['invitation'],
    }, authenticated: false);
    message = response['status'] == 'pending'
        ? 'Confirm code ${response['code']} on the computer.'
        : response['status'] == 'revoked'
        ? 'This phone has been revoked.'
        : 'Connected to the computer.';
    onChange?.call();
    return response['status'] == 'active';
  }

  Future<void> sync() async {
    if (busy || pairing == null) return;
    busy = true;
    onChange?.call();
    PinnedConnection? c;
    try {
      c = PinnedConnection(pairing!);
      if (!await _pair(c, pairing!)) return;
      message = 'Sending saved work…';
      onChange?.call();
      var bundle = await c.request('/bundle', {});
      final company = (bundle['catalog'] ?? bundle['workspace']) as Json;
      if (company['companyId'] != pairing!['companyId']) {
        throw StateError('Office company changed.');
      }
      await store.importOfficeBundle(bundle);
      final jobIds = store.realWorkspace
          ? store.jobs.map((j) => j['id'] as String?).toList()
          : <String?>[null];
      for (final jobId in jobIds) {
        final state = await newSession(), id = secret();
        Uint8List? incoming;
        for (var round = 0; round < 32; round++) {
          final packet = await store.queue.run(() async {
            final p = await state.step(
              bytes: jobId == null
                  ? store.document!
                  : store.documentFor(jobId)!,
              incoming: incoming,
            );
            store.validateFields(
              jsonDecode(await documentValues(bytes: p.document)) as Json,
              jobId: jobId,
            );
            store.transaction(
              () => store.saveDocument(p.document, jobId: jobId),
            );
            return p;
          });
          final response = await c.request('/sync', {
            'session': id,
            'jobId': ?jobId,
            'message': packet.message == null
                ? null
                : base64Encode(packet.message!),
          });
          incoming = response['message'] == null
              ? null
              : base64Decode(response['message'] as String);
          if (incoming == null && packet.message == null) break;
          if (round == 31) {
            throw StateError(
              'Sync needs another attempt; saved work is retained.',
            );
          }
        }
      }
      // A process can stop after flushing the last local chunk but before its
      // rename. Recover matching complete partials referenced by durable work
      // before listing photos to send; incomplete bytes still cannot upload.
      for (final hash in await store.requiredEvidence()) {
        await store.evidence.status(hash);
      }
      for (final p
          in store.submissions
              .where(
                (p) => store.realWorkspace
                    ? p['device'] == store.device
                    : p['_state'] == 'queued',
              )
              .toList()) {
        final payload = Map<String, dynamic>.from(p)..remove('_state');
        final accepted = await c.request('/submit', payload);
        if (accepted['accepted'] != payload['id']) {
          throw StateError(
            'Computer acknowledgement did not match the submitted version.',
          );
        }
        // Queued state clears only on the authoritative bundle below.
      }
      final required = await store.requiredEvidence();
      for (final blob in (await store.evidence.manifest()).where(
        (blob) => !store.realWorkspace || required.contains(blob['hash']),
      )) {
        var remote = await c.request('/blob/status', {'hash': blob['hash']});
        while (remote['complete'] != true) {
          final offset = remote['offset'] as int;
          remote = await c.request('/blob/put', {
            'hash': blob['hash'],
            'offset': offset,
            'total': blob['size'],
            'bytes': base64Encode(
              await store.evidence.chunk(blob['hash'] as String, offset),
            ),
          });
        }
      }
      bundle = await c.request('/bundle', {});
      await store.importOfficeBundle(bundle);
      for (final blob in bundle['blobs'] as List) {
        var local = await store.evidence.status(blob['hash'] as String);
        while (local['complete'] != true) {
          final offset = local['offset'] as int;
          final chunk = await c.request('/blob/get', {
            'hash': blob['hash'],
            'offset': offset,
          });
          await store.evidence.append(
            blob['hash'] as String,
            offset,
            blob['size'] as int,
            base64Decode(chunk['bytes'] as String),
          );
          local = await store.evidence.status(blob['hash'] as String);
        }
      }
      final officeHashes = (bundle['blobs'] as List)
          .map((b) => b['hash'] as String)
          .toSet();
      for (final hash in await store.requiredEvidence()) {
        if (!officeHashes.contains(hash) ||
            !await store.evidence.complete(hash)) {
          throw StateError(
            'The computer is still missing an inspection photo. Keep the original phone connected to finish saving it; a lost photo cannot be restored.',
          );
        }
      }
      if (store.realWorkspace) {
        final officeReceipts = <String, Json>{
          for (final r in bundle['receipts'] as List)
            (r as Json)['id'] as String: r,
        };
        for (final receipt in store.receipts) {
          final retained = officeReceipts[receipt['id']];
          if (retained == null ||
              contentHash(retained) != contentHash(receipt)) {
            throw StateError(
              'The computer is missing an earlier office decision. Retain this phone and reconcile its saved history before treating the restored computer as complete.',
            );
          }
        }
      }
      store.setSetting('lastCompleteSync', store.stamp());
      message = 'Saved on the computer. Photos verified.';
    } catch (error) {
      message =
          'Saved on this phone—waiting to send. ${connectionProblem(error)}';
      rethrow;
    } finally {
      c?.close();
      busy = false;
      onChange?.call();
    }
  }
}
