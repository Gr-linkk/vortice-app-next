import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/evidence_store.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/local_sync.dart';
import 'package:maintenance_local/model.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';

const _saved = 'Saved on the computer. Photos verified.';
const _waiting = 'Saved on this phone—waiting to send.';

class _Gate {
  _Gate(this.route, this.ordinal);
  final String route;
  final int ordinal;
  int seen = 0;
  final arrived = Completer<Json>();
  final release = Completer<void>();
  void open() {
    if (!release.isCompleted) release.complete();
  }
}

/// A synthetic loopback TLS proxy pauses a response only after the actual office
/// produced it. Tests can therefore distinguish the office's saved snapshot
/// from a phone edit made while that snapshot is in flight.
class _OfficeProxy {
  _OfficeProxy(this.upstream, this.http);
  final OfficeServer upstream;
  final HttpServer http;
  final _connections = <PinnedConnection>{};
  _Gate? gate;
  String? loseNextResponse;

  static Future<_OfficeProxy> start(OfficeServer upstream) async {
    final http = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      upstream.identity.context,
    );
    final proxy = _OfficeProxy(upstream, http);
    http.listen(proxy._handle);
    return proxy;
  }

  String invitation() => canonical({
    ...jsonDecode(upstream.invitation('127.0.0.1')) as Json,
    'url': 'https://127.0.0.1:${http.port}',
  });

  _Gate pause(String route, {int ordinal = 1}) {
    gate?.open();
    return gate = _Gate(route, ordinal);
  }

  Future<void> _handle(HttpRequest request) async {
    final route = request.uri.path;
    final connection = PinnedConnection({
      'url': 'https://127.0.0.1:${upstream.port}',
      'fingerprint': upstream.identity.fingerprint,
      'token': request.headers.value('authorization')?.substring(7),
    });
    _connections.add(connection);
    var detached = false;
    try {
      final response = await connection.request(
        route,
        await readJson(request),
        authenticated: route != '/pair',
      );
      final current = gate;
      if (current != null &&
          route == current.route &&
          ++current.seen == current.ordinal) {
        current.arrived.complete(response);
        await current.release.future;
      }
      if (route == loseNextResponse) {
        loseNextResponse = null;
        detached = true;
        (await request.response.detachSocket(writeHeaders: false)).destroy();
      } else {
        request.response.headers.contentType = ContentType.json;
        request.response.write(canonical(response));
      }
    } catch (error) {
      if (!detached) {
        request.response.statusCode = 409;
        request.response.headers.contentType = ContentType.json;
        request.response.write(canonical({'error': error.toString()}));
      }
    } finally {
      connection.close();
      _connections.remove(connection);
      if (!detached) await request.response.close();
    }
  }

  Future<void> close() async {
    gate?.open();
    await http.close(force: true);
    for (final connection in _connections.toList()) {
      connection.close();
    }
  }
}

void main() {
  setUpAll(() async {
    await RustLib.init(
      externalLibrary: ExternalLibrary.open(
        File(
          Platform.environment['MAINTENANCE_NATIVE_LIBRARY'] ??
              'rust/target/debug/librust_lib_sync_lab.so',
        ).absolute.path,
      ),
    );
  });
  late Directory root;
  late DateTime clock;
  late LabStore office, phone;
  late OfficeServer server;
  late _OfficeProxy proxy;
  late PhoneSync sync;
  late String firstId, secondId;

  Future<String> addJob(String label) async {
    final equipment = await office.addEquipment(
      name: 'Synthetic setup equipment $label',
      serial: 'SETUP-PROBE-$label',
    );
    final procedure = await office.publishChecklist(
      title: 'Synthetic setup procedure $label',
      items: [
        {
          'id': 'guard',
          'label': 'Inspect the synthetic guard',
          'input_type': 'check',
        },
      ],
      provenance: {'kind': 'company-authored'},
    );
    final job = await office.prepareWork(
      equipmentId: equipment['id'] as String,
      templateId: procedure['id'] as String,
      title: 'Synthetic setup inspection $label',
    );
    return job['id'] as String;
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('maintenance-setup-probe-');
    clock = DateTime.utc(2026, 9, 30, 14);
    office = await LabStore.open(
      Directory('${root.path}/office'),
      office: true,
      maintenanceOnly: true,
      now: () => clock,
    );
    await office.createCompany('Synthetic setup probe company');
    phone = await LabStore.open(
      Directory('${root.path}/phone'),
      office: false,
      maintenanceOnly: true,
      now: () => clock,
    );
    server = await OfficeServer.start(
      office,
      port: 0,
      address: InternetAddress.loopbackIPv4,
    );
    proxy = await _OfficeProxy.start(server);
    sync = PhoneSync(phone);
  });
  tearDown(() async {
    await proxy.close();
    await server.close();
    await phone.close();
    await office.close();
    await root.delete(recursive: true);
  });

  Future<void> connect({bool seedJobs = true}) async {
    if (seedJobs) {
      firstId = await addJob('A');
      secondId = await addJob('B');
    }
    await sync.enroll(proxy.invitation());
    server.authority.confirm(phone.device);
    await sync.sync();
    expect(sync.visibleMessage, _saved);
  }

  Future<Json> submit(
    String jobId, {
    List<int> photo = const [1, 2, 3, 4],
  }) async {
    await phone.update({
      'answer:guard': {'result': 'action', 'value': ''},
      'meter': 0,
      'notes': 'Synthetic setup finding requiring follow-up.',
    }, jobId: jobId);
    await phone.attach(photo, jobId: jobId);
    return phone.submit(jobId: jobId);
  }

  test(
    'Selecting another job preserves confirmed status; editing a nonselected job invalidates it',
    () async {
      await connect();
      phone.selectJob(firstId);
      expect(sync.visibleMessage, _saved);
      phone.selectJob(secondId);
      expect(sync.visibleMessage, _saved);
      await phone.update({
        'notes': 'First job changed while the second is selected.',
      }, jobId: firstId);
      expect(phone.activeJobId, secondId);
      expect(sync.visibleMessage, _waiting);
      phone.selectJob(firstId);
      expect(sync.visibleMessage, _waiting);
      await sync.sync();
      expect(sync.visibleMessage, _saved);
      phone.selectJob(secondId);
      expect(sync.visibleMessage, _saved);
    },
  );

  test(
    'A restarted phone exposes its nonselected queued version instead of a prior complete send',
    () async {
      await connect();
      phone.selectJob(firstId);
      final submission = await submit(secondId);
      final device = phone.device,
          completeBefore = phone.setting('lastCompleteSync');
      await phone.close();
      phone = await LabStore.open(
        Directory('${root.path}/phone'),
        office: false,
        maintenanceOnly: true,
        now: () => clock,
      );
      sync = PhoneSync(phone);
      expect(phone.device, device);
      expect(phone.activeJobId, firstId);
      expect(phone.setting('lastCompleteSync'), completeBefore);
      expect(phone.submissions.single['_state'], 'queued');
      expect(
        canonical(await phone.submit(jobId: secondId)),
        canonical(submission),
      );
      expect(sync.connectionResponses, 0);
      expect(sync.visibleMessage, _waiting);
    },
  );

  test(
    'A final office bundle captured before a late nonselected edit cannot declare that edit sent',
    () async {
      await connect();
      phone.selectJob(firstId);
      final gate = proxy.pause('/bundle', ordinal: 2);
      final sending = sync.sync();
      try {
        final captured = await gate.arrived.future.timeout(
          const Duration(seconds: 5),
        );
        expect((captured['documents'] as Json).keys.toSet(), {
          firstId,
          secondId,
        });
        await phone.update({
          'notes': 'Late local edit after the final office snapshot.',
        }, jobId: secondId);
      } finally {
        gate.open();
      }
      await sending;
      expect(valuesOf(await office.fields(jobId: secondId))['notes'], '');
      expect(
        valuesOf(await phone.fields(jobId: secondId))['notes'],
        'Late local edit after the final office snapshot.',
      );
      expect(
        sync.message,
        _saved,
      ); // Transport finished for the earlier snapshot.
      expect(sync.visibleMessage, _waiting);
      expect(sync.lastGuidance, isNull);
    },
  );

  test(
    'A job added by the office during document exchange is included in the final status anchor',
    () async {
      await connect();
      final gate = proxy.pause('/sync');
      final sending = sync.sync();
      late String laterId;
      try {
        await gate.arrived.future.timeout(const Duration(seconds: 5));
        laterId = await addJob('C');
      } finally {
        gate.open();
      }
      await sending;
      expect(phone.jobs.map((job) => job['id']), [firstId, secondId, laterId]);
      expect(sync.visibleMessage, _saved);
      phone.selectJob(firstId);
      await phone.update({
        'notes': 'Newly received third job changed locally.',
      }, jobId: laterId);
      expect(sync.visibleMessage, _waiting);
    },
  );

  test(
    'An empty real company catalog has no phantom unsent inspection after a verified exchange',
    () async {
      await connect(seedJobs: false);
      expect(phone.realWorkspace, isTrue);
      expect(phone.jobs, isEmpty);
      expect(phone.document, isNull);
      expect(sync.visibleMessage, _saved);
      expect(phone.submissions, isEmpty);
      expect(phone.receipts, isEmpty);
    },
  );

  test(
    'A lost chunk response leaves partial office evidence and never exposes completed status or review history',
    () async {
      await connect();
      final lastComplete = phone.setting('lastCompleteSync');
      clock = clock.add(const Duration(seconds: 1));
      final submission = await submit(
        secondId,
        photo: List.generate(700013, (i) => (i * 19 + 3) % 251),
      );
      final hash = (submission['values'] as Json)['photo'] as String;
      proxy.loseNextResponse = '/blob/put';
      await expectLater(sync.sync(), throwsA(isA<HttpException>()));
      expect(
        (await office.evidence.status(hash))['offset'],
        EvidenceStore.chunkBytes,
      );
      expect(await office.evidence.complete(hash), isFalse);
      expect(phone.setting('lastCompleteSync'), lastComplete);
      expect(phone.submissions.single['_state'], 'queued');
      expect(sync.visibleMessage, _waiting);
      expect(sync.lastGuidance!.message, 'Cannot reach the computer.');
      await expectLater(
        office.decide(submission['id'] as String, approve: true),
        throwsStateError,
      );
      expect(office.receipts, isEmpty);
      expect(phone.receipts, isEmpty);
    },
  );

  test(
    'Missing authoritative decision history remains actionable and cannot become a generic completed banner',
    () async {
      await connect();
      final submission = await submit(firstId);
      await sync.sync();
      final receipt = await office.decide(
        submission['id'] as String,
        approve: true,
      );
      await sync.sync();
      final lastComplete = phone.setting('lastCompleteSync');
      // A synthetic older-history fault, without changing the retained phone's
      // reviewed record. The phone is never authorized to upload a decision.
      office.db.execute('DELETE FROM receipts WHERE id=?', [receipt['id']]);
      clock = clock.add(const Duration(seconds: 1));
      await expectLater(sync.sync(), throwsStateError);
      expect(
        sync.visibleMessage,
        contains('missing an earlier office decision'),
      );
      expect(sync.visibleMessage, isNot(_saved));
      expect(sync.lastGuidance, isNull);
      expect(phone.setting('lastCompleteSync'), lastComplete);
      expect(phone.receipts.single, receipt);
      expect(office.receipts, isEmpty);
    },
  );

  test(
    'A retry keeps transport help until the actual pending response arrives',
    () async {
      await sync.enroll(proxy.invitation());
      expect(sync.visibleMessage, startsWith('Confirm code '));
      proxy.loseNextResponse = '/pair';
      await expectLater(sync.sync(), throwsA(isA<HttpException>()));
      final help = sync.lastGuidance, responses = sync.connectionResponses;
      expect(help, isNotNull);
      expect(sync.visibleMessage, _waiting);
      final gate = proxy.pause('/pair');
      final retry = sync.sync();
      try {
        await gate.arrived.future.timeout(const Duration(seconds: 5));
        expect(sync.busy, isTrue);
        expect(sync.lastGuidance, same(help));
        expect(sync.connectionResponses, responses);
        expect(sync.visibleMessage, _waiting);
      } finally {
        gate.open();
      }
      await retry;
      expect(sync.lastGuidance, isNull);
      expect(sync.connectionResponses, responses + 1);
      expect(sync.visibleMessage, startsWith('Confirm code '));
      expect(sync.busy, isFalse);
    },
  );

  test(
    'Revocation wins over queued nonselected work and preserves its exact authority banner',
    () async {
      await connect();
      phone.selectJob(firstId);
      await submit(secondId);
      final responses = sync.connectionResponses;
      server.authority.revoke(phone.device);
      await sync.sync();
      expect(sync.visibleMessage, 'This phone has been revoked.');
      expect(sync.lastGuidance, isNull);
      expect(sync.connectionResponses, responses + 1);
      expect(phone.submissions.single['_state'], 'queued');
      expect(office.submissions, isEmpty);
    },
  );

  test(
    'A rejected credential keeps application guidance and never exposes the saved URL or token',
    () async {
      await connect();
      final original = sync.pairing!;
      final invalidToken = secret();
      phone.setSetting('pairing', {
        ...original,
        'invitation': server.authority.invite(),
        'token': invalidToken,
      });
      final lastComplete = phone.setting('lastCompleteSync');
      await expectLater(sync.sync(), throwsStateError);
      expect(
        sync.visibleMessage,
        contains('This device credential cannot enroll again.'),
      );
      expect(sync.visibleMessage, isNot(_saved));
      expect(sync.lastGuidance, isNull);
      expect(phone.setting('lastCompleteSync'), lastComplete);
      for (final private in [
        original['url'],
        original['token'],
        invalidToken,
      ]) {
        expect(sync.visibleMessage, isNot(contains(private as String)));
      }
    },
  );

  test(
    'Unsafe saved URL rejection and a failed loopback connection never echo the endpoint or token',
    () async {
      await connect();
      final unused = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = unused.port;
      await unused.close();
      const private = 'SYNTHETIC_PRIVATE_QUERY_DO_NOT_DISPLAY';
      final original = sync.pairing!;
      final endpoint = 'https://127.0.0.1:$port';
      final unsafeUrl = '$endpoint/?token=$private';
      phone.setSetting('pairing', {...original, 'url': unsafeUrl});
      await expectLater(sync.sync(), throwsStateError);
      expect(sync.visibleMessage, contains('Invalid local office invitation.'));
      expect(sync.visibleMessage, isNot(contains(unsafeUrl)));
      expect(sync.visibleMessage, isNot(contains(private)));
      expect(sync.lastGuidance, isNull);
      phone.setSetting('pairing', {...original, 'url': endpoint});
      await expectLater(sync.sync(), throwsA(isA<SocketException>()));
      expect(sync.visibleMessage, _waiting);
      expect(sync.lastGuidance, isNotNull);
      for (final displayed in [
        sync.message,
        sync.visibleMessage,
        sync.lastGuidance!.text,
      ]) {
        expect(displayed, isNot(contains(unsafeUrl)));
        expect(displayed, isNot(contains(endpoint)));
        expect(displayed, isNot(contains(private)));
      }
    },
  );

  test(
    'Typed transport diagnostics cannot leak synthetic URL or token through displayed guidance',
    () {
      const token = 'SYNTHETIC_PRIVATE_TOKEN_DO_NOT_DISPLAY';
      const url = 'https://127.0.0.1:54321/private?token=$token';
      for (final error in <Object>[
        const HandshakeException('$url $token'),
        const TlsException('$url $token'),
        const SocketException('$url $token'),
        TimeoutException('$url $token'),
        HttpException('$url $token', uri: Uri.parse(url)),
        const FormatException('$url $token'),
      ]) {
        final guidance = connectionGuidance(error);
        expect(guidance, isNotNull);
        for (final displayed in [guidance!.text, connectionProblem(error)]) {
          expect(displayed, isNot(contains(url)));
          expect(displayed, isNot(contains(token)));
        }
      }
      final network = connectionGuidance(const SocketException('$url $token'))!;
      expect(network.text, contains('TCP 47841'));
      expect(network.text, isNot(contains('47831')));
    },
  );
}
