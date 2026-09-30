import 'dart:convert';
import 'dart:io';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/local_sync.dart';
import 'package:maintenance_local/model.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';

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
  final extras = <LabStore>[];
  setUp(() async {
    root = await Directory.systemTemp.createTemp('vortice-network-');
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
    await server.close();
    await office.close();
    await phone.close();
    for (final e in extras) {
      await e.close();
    }
    extras.clear();
    await root.delete(recursive: true);
  });
  Future<void> connect() async {
    await sync.enroll(server.invitation('127.0.0.1'));
    server.authority.confirm(phone.device);
    await sync.sync();
  }

  Future<Json> submit() async {
    await phone.update({
      'fluid': 'pass',
      'guards': 'attention',
      'meter': 42.5,
      'notes': 'Synthetic test: tighten guard.',
    });
    await phone.attach(List.generate(700000, (i) => i % 251));
    return phone.submit();
  }

  test(
    'Single-use enrollment requires computer confirmation and pins its TLS certificate',
    () async {
      final invitation = server.invitation('127.0.0.1');
      await sync.enroll(invitation);
      await sync.sync();
      expect(phone.workspace, isNull);
      final c = PinnedConnection(sync.pairing!);
      await expectLater(c.request('/bundle', {}), throwsStateError);
      c.close();
      await sync.enroll(invitation);
      expect(server.authority.phones.length, 1);
      final fresh = await LabStore.open(
        Directory('${root.path}/fresh'),
        office: false,
      );
      extras.add(fresh);
      await expectLater(PhoneSync(fresh).enroll(invitation), throwsStateError);
      server.authority.confirm(phone.device);
      await sync.sync();
      expect(phone.workspace, office.workspace);
      final wrong = PinnedConnection({
        ...sync.pairing!,
        'fingerprint': '0' * 64,
      });
      await expectLater(
        wrong.request('/bundle', {}),
        throwsA(isA<HandshakeException>()),
      );
      wrong.close();
      expect(
        () =>
            PinnedConnection({...sync.pairing!, 'url': 'https://example.com'}),
        throwsStateError,
      );
    },
  );
  test(
    'TLS sync persists exact approvals, then fully restores a replacement',
    () async {
      await connect();
      final p = await submit();
      await sync.sync();
      expect(office.submissions.single['id'], p['id']);
      expect(await office.fields(), await phone.fields());
      expect(await office.evidence.manifest(), await phone.evidence.manifest());
      final receipt = await office.decide(p['id'] as String, approve: true);
      await sync.sync();
      expect(phone.receipts.single, receipt);
      server.authority.revoke(phone.device);
      final denied = PinnedConnection(sync.pairing!);
      for (final route in [
        '/bundle',
        '/sync',
        '/submit',
        '/blob/status',
        '/blob/get',
        '/blob/put',
      ]) {
        await expectLater(denied.request(route, {}), throwsStateError);
      }
      denied.close();
      final replacement = await LabStore.open(
        Directory('${root.path}/replacement'),
        office: false,
      );
      extras.add(replacement);
      final restore = PhoneSync(replacement);
      await restore.enroll(
        server.invitation('127.0.0.1'),
        label: 'Replacement',
      );
      server.authority.confirm(replacement.device);
      await restore.sync();
      expect(await replacement.fields(), await office.fields());
      expect(replacement.receipts, office.receipts);
      expect(replacement.submissions, office.submissions);
      expect(
        await replacement.evidence.manifest(),
        await office.evidence.manifest(),
      );
      expect(replacement.db.select('SELECT * FROM phones'), isEmpty);
      expect(
        await File('${replacement.root.path}/office-key.pem').exists(),
        isFalse,
      );
    },
  );
  test(
    'Uncertain submission outcome reuses durable identity after both sides restart',
    () async {
      await connect();
      final p = await submit();
      final c = PinnedConnection(sync.pairing!);
      await c.request('/submit', p);
      c.close();
      final saved = phone.submissions.single['id'];
      final port = server.port;
      await phone.close();
      phone = await LabStore.open(
        Directory('${root.path}/phone'),
        office: false,
      );
      sync = PhoneSync(phone);
      expect((await phone.submit())['id'], saved);
      await server.close();
      await office.close();
      office = await LabStore.open(
        Directory('${root.path}/office'),
        office: true,
      );
      server = await OfficeServer.start(office, port: port);
      await sync.sync();
      await sync.sync();
      expect(office.submissions.length, 1);
      expect(office.submissions.single['id'], saved);
      final changed = PinnedConnection(sync.pairing!);
      await expectLater(
        changed.request('/submit', {...p, 'createdAt': 'changed'}),
        throwsStateError,
      );
      changed.close();
      expect(await office.approvalProblem(p), isNull);
    },
  );
  test(
    'Interrupted evidence resumes from flushed bytes across server restart',
    () async {
      await connect();
      final p = await submit();
      final hash = (p['values'] as Json)['photo'] as String;
      final bytes = await phone.evidence.file(hash).readAsBytes();
      final c = PinnedConnection(sync.pairing!);
      await c.request('/submit', p);
      await c.request('/blob/put', {
        'hash': hash,
        'offset': 0,
        'total': bytes.length,
        'bytes': base64Encode(bytes.sublist(0, 777)),
      });
      c.close();
      await expectLater(
        office.decide(p['id'] as String, approve: true),
        throwsStateError,
      );
      final port = server.port;
      await server.close();
      await office.close();
      office = await LabStore.open(
        Directory('${root.path}/office'),
        office: true,
      );
      server = await OfficeServer.start(office, port: port);
      expect((await office.evidence.status(hash))['offset'], 777);
      await sync.sync();
      expect(await office.evidence.complete(hash), isTrue);
      expect(office.submissions.length, 1);
    },
  );
  test(
    'Concurrent notes/meters require resolution and stale edits preserve old receipt',
    () async {
      await connect();
      final p = await submit();
      await sync.sync();
      await office.decide(p['id'] as String, approve: true);
      await sync.sync();
      await office.update({'meter': 70, 'notes': 'Office correction'});
      await phone.update({'meter': 71, 'notes': 'Phone correction'});
      await sync.sync();
      expect(conflicts(await office.fields()), containsAll(['meter', 'notes']));
      await expectLater(phone.submit(), throwsStateError);
      expect((office.receipts.single['values'] as Json)['meter'], 42.5);
      await phone.update({'meter': 71, 'notes': 'Agreed correction'});
      final newer = await phone.submit();
      await sync.sync();
      expect(conflicts(await office.fields()), isEmpty);
      await office.decide(
        newer['id'] as String,
        approve: false,
        reason: 'Check the reading once more.',
      );
      expect(office.receipts.length, 2);
      expect(office.receipts.first['decision'], 'approved');
    },
  );
  test('Phone cannot inject authority or use an approval endpoint', () async {
    await connect();
    await expectLater(phone.update({'approved': true}), throwsStateError);
    final c = PinnedConnection(sync.pairing!);
    await expectLater(
      c.request('/approve', {'decision': 'approved'}),
      throwsStateError,
    );
    c.close();
    expect(office.receipts, isEmpty);
  });

  test(
    'Changed computer address retains the paired credential and saved work',
    () async {
      await connect();
      final token = sync.pairing!['token'];
      await phone.update({'notes': 'Retained local draft'});
      await server.close();
      server = await OfficeServer.start(office, port: 0);
      await sync.enroll(server.invitation('127.0.0.1'));
      expect(sync.pairing!['token'], token);
      await sync.sync();
      expect(server.authority.phones.length, 1);
      expect(valuesOf(await office.fields())['notes'], 'Retained local draft');
    },
  );

  test(
    'Malformed submitted metadata cannot become a broken office record',
    () async {
      await connect();
      final p = await submit();
      final c = PinnedConnection(sync.pairing!);
      for (final bad in [
        {...p, 'createdAt': null},
        {...p, 'approved': true},
        {...p, 'documentHash': 'not-a-hash'},
      ]) {
        await expectLater(c.request('/submit', bad), throwsStateError);
      }
      c.close();
      expect(office.submissions, isEmpty);
    },
  );
  test(
    'Incomplete computer copy cannot be reported as a complete replacement restore',
    () async {
      await connect();
      final p = await submit();
      final c = PinnedConnection(sync.pairing!);
      await c.request('/submit', p);
      c.close();
      server.authority.revoke(phone.device);
      final replacement = await LabStore.open(
        Directory('${root.path}/incomplete-replacement'),
        office: false,
      );
      extras.add(replacement);
      final restore = PhoneSync(replacement);
      await restore.enroll(server.invitation('127.0.0.1'));
      server.authority.confirm(replacement.device);
      await expectLater(restore.sync(), throwsStateError);
      expect(replacement.setting('lastCompleteSync'), isNull);
      expect(restore.message, contains('computer is still missing'));
      expect(replacement.submissions.single['id'], p['id']);
      expect(
        await replacement.evidence.complete(
          (p['values'] as Json)['photo'] as String,
        ),
        isFalse,
      );
    },
  );
  test(
    'Expired unsent enrollment can use a fresh invitation without rotating its credential',
    () async {
      final invite = server.invitation('127.0.0.1');
      final parsed = jsonDecode(invite) as Json;
      phone.setSetting('pairing', {
        ...parsed,
        'device': phone.device,
        'label': 'Phone',
        'token': secret(),
      });
      final token = sync.pairing!['token'];
      office.db.execute("UPDATE invites SET expires='2000-01-01T00:00:00Z'");
      await expectLater(sync.enroll(invite), throwsStateError);
      await sync.enroll(server.invitation('127.0.0.1'));
      expect(sync.pairing!['token'], token);
      server.authority.confirm(phone.device);
      await sync.sync();
      final saved = canonical(sync.pairing);
      await expectLater(
        sync.enroll(canonical({...parsed, 'fingerprint': '0' * 64})),
        throwsStateError,
      );
      expect(canonical(sync.pairing), saved);
      server.authority.revoke(phone.device);
      await expectLater(
        sync.enroll(server.invitation('127.0.0.1')),
        throwsStateError,
      );
      expect(server.authority.phones.single['status'], 'revoked');
    },
  );
}
