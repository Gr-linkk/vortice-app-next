import 'dart:convert';
import 'dart:io';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/evidence_store.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/local_sync.dart';
import 'package:maintenance_local/model.dart';
import 'package:maintenance_local/office_backup.dart';
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
  late PhoneSync sync;
  OfficeServer? server;
  final stores = <LabStore>[];
  Directory path(String name) => Directory('${root.path}/$name');
  Future<LabStore> open(String name, bool isOffice) async {
    final store = await LabStore.open(path(name), office: isOffice);
    stores.add(store);
    return store;
  }

  Future<void> close(LabStore store) async {
    await store.close();
    stores.remove(store);
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sync-lab-recovery-restart-');
    office = await open('office', true);
    await office.createWorkspace();
    phone = await open('phone', false);
    server = await OfficeServer.start(office, port: 0);
    sync = PhoneSync(phone);
    await sync.enroll(server!.invitation('127.0.0.1'));
    server!.authority.confirm(phone.device);
    await sync.sync();
  });
  tearDown(() async {
    await server?.close();
    server = null;
    for (final store in stores) {
      await store.close();
    }
    stores.clear();
    await root.delete(recursive: true);
  });
  Future<({Json submission, String hash, List<int> bytes})> queued() async {
    await phone.update({
      'fluid': 'pass',
      'guards': 'pass',
      'meter': 801.5,
      'notes': 'Synthetic queued work retained through interruption.',
    });
    final bytes = List.generate(600000, (i) => (i + 23) % 251);
    final hash = await phone.attach(bytes);
    return (submission: await phone.submit(), hash: hash, bytes: bytes);
  }

  Future<void> denyWithoutPromotion(
    PinnedConnection connection,
    String hash,
  ) async {
    await expectLater(
      connection.request('/blob/status', {'hash': hash}),
      throwsStateError,
    );
    expect(await office.evidence.file(hash).exists(), isFalse);
  }

  test(
    'Restored old authority fences queued replay; restarted phone publishes its complete pending photo',
    () async {
      final summary = await OfficeBackup.create(office, path('backup'));
      // Model a separately stored older copy that did not retain private modes.
      expect(
        (await Process.run('chmod', [
          '-R',
          'a+rX',
          path('backup').path,
        ])).exitCode,
        0,
      );
      final work = await queued();
      final connection = PinnedConnection(sync.pairing!);
      try {
        await connection.request('/submit', work.submission);
        await connection.request('/blob/put', {
          'hash': work.hash,
          'offset': 0,
          'total': work.bytes.length,
          'bytes': base64Encode(
            work.bytes.sublist(0, EvidenceStore.chunkBytes),
          ),
        });
      } finally {
        connection.close();
      }
      expect(phone.submissions.single['_state'], 'queued');
      // This flushed full partial models a process interruption before rename.
      await phone.evidence
          .file(work.hash)
          .rename('${phone.evidence.file(work.hash).path}.part');
      final token = sync.pairing!['token'], device = phone.device;
      server!.authority.revoke(device); // Unknown to the older snapshot.
      await server!.close();
      server = null;
      await close(office);
      await close(phone);
      await path('office').rename('${root.path}/unavailable-original-retained');
      await OfficeBackup.restore(
        path('backup'),
        path('restored'),
        expectedFingerprint: summary.fingerprint,
      );
      // Restore re-applies private modes instead of trusting copied backup modes.
      expect((await path('restored').stat()).mode & 0x3f, 0);
      await for (final item in path(
        'restored',
      ).list(recursive: true, followLinks: false)) {
        expect((await item.stat()).mode & 0x3f, 0, reason: item.path);
      }
      office = await open('restored', true);
      phone = await open('phone', false);
      sync = PhoneSync(phone);
      server = await OfficeServer.start(office, port: 0);
      expect(phone.device, device);
      expect(sync.pairing!['token'], token);
      expect(office.submissions, isEmpty);
      expect(
        await File('${office.evidence.file(work.hash).path}.part').exists(),
        isFalse,
      );
      final stale = PinnedConnection({
        ...sync.pairing!,
        'url': 'https://127.0.0.1:${server!.port}',
      });
      try {
        await denyWithoutPromotion(stale, work.hash);
        await expectLater(
          stale.request('/submit', work.submission),
          throwsStateError,
        );
      } finally {
        stale.close();
      }
      expect(office.submissions, isEmpty);
      await sync.enroll(server!.invitation('127.0.0.1'));
      await sync.sync();
      expect(sync.message, contains('Confirm code'));
      expect(phone.submissions.single['_state'], 'queued');
      server!.authority.confirm(device);
      await sync.sync();
      await sync.sync();
      expect(office.submissions.single['id'], work.submission['id']);
      expect(phone.submissions.single['_state'], 'received');
      expect(
        await office.evidence.file(work.hash).readAsBytes(),
        orderedEquals(work.bytes),
      );
      expect(
        await phone.evidence.file(work.hash).readAsBytes(),
        orderedEquals(work.bytes),
      );
      expect(
        await File('${phone.evidence.file(work.hash).path}.part').exists(),
        isFalse,
      );
      expect(sync.message, 'Saved on the computer. Photos verified.');
      final receipt = await office.decide(
        work.submission['id'] as String,
        approve: true,
      );
      await sync.sync();
      expect(phone.receipts.single, receipt);
      expect(office.receipts, hasLength(1));
    },
  );

  test(
    'Revoked credentials after both stores restart cannot publish a complete partial or replay queued work',
    () async {
      final work = await queued();
      final connection = PinnedConnection(sync.pairing!);
      try {
        await connection.request('/submit', work.submission);
      } finally {
        connection.close();
      }
      await office.evidence.root.create(recursive: true);
      final partial = File('${office.evidence.file(work.hash).path}.part');
      await partial.writeAsBytes(work.bytes, flush: true);
      server!.authority.revoke(phone.device);
      final pin = server!.identity.fingerprint;
      await server!.close();
      server = null;
      await close(office);
      await close(phone);
      office = await open('office', true);
      phone = await open('phone', false);
      sync = PhoneSync(phone);
      server = await OfficeServer.start(office, port: 0);
      expect(server!.identity.fingerprint, pin);
      final stale = PinnedConnection({
        ...sync.pairing!,
        'url': 'https://127.0.0.1:${server!.port}',
      });
      try {
        await denyWithoutPromotion(stale, work.hash);
        await expectLater(
          stale.request('/submit', work.submission),
          throwsStateError,
        );
      } finally {
        stale.close();
      }
      expect(await partial.readAsBytes(), orderedEquals(work.bytes));
      expect(await office.evidence.manifest(), isEmpty);
      expect(await office.approvalProblem(work.submission), isNotNull);
      await expectLater(
        OfficeBackup.create(office, path('incomplete-backup')),
        throwsStateError,
      );
      expect(await path('incomplete-backup').exists(), isFalse);
      expect(phone.submissions.single['_state'], 'queued');
      expect(office.submissions, hasLength(1));
      expect(office.receipts, isEmpty);
    },
  );
}
