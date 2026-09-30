import 'dart:io';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
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
  test(
    'Surviving phone reconnects to restored same office only after fresh invitation and owner confirmation',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'sync-lab-restored-network-',
      );
      var office = await LabStore.open(
        Directory('${root.path}/office'),
        office: true,
      );
      await office.createWorkspace();
      final phone = await LabStore.open(
        Directory('${root.path}/phone'),
        office: false,
      );
      var server = await OfficeServer.start(office, port: 0);
      final sync = PhoneSync(phone);
      try {
        await sync.enroll(server.invitation('127.0.0.1'));
        server.authority.confirm(phone.device);
        await sync.sync();
        await phone.update({
          'fluid': 'pass',
          'guards': 'attention',
          'meter': 712.5,
          'notes': 'Synthetic received work before office loss.',
        });
        final photo = await phone.attach(List.generate(700000, (i) => i % 251));
        final first = await phone.submit();
        await sync.sync();
        final receipt = await office.decide(
          first['id'] as String,
          approve: true,
        );
        await sync.sync();
        final revokedToken = secret();
        server.authority.request({
          'device': 'revoked-phone',
          'label': 'Lost phone',
          'token': revokedToken,
          'invitation': server.authority.invite(),
        });
        server.authority.revoke('revoked-phone');
        final backup = Directory('${root.path}/backup'),
            target = Directory('${root.path}/restored');
        final summary = await OfficeBackup.create(office, backup);
        final device = office.device, oldToken = sync.pairing!['token'];
        // This later revocation is unknown to the stale snapshot: restore must fence it.
        server.authority.revoke(phone.device);
        await server.close();
        await office.close();
        await Directory(
          '${root.path}/office',
        ).rename('${root.path}/lost-office-retained');
        await phone.update({
          'meter': 713,
          'notes': 'Synthetic queued work after backup.',
        });
        final queued = await phone.submit();
        await OfficeBackup.restore(
          backup,
          target,
          expectedFingerprint: summary.fingerprint,
        );
        office = await LabStore.open(target, office: true);
        server = await OfficeServer.start(office, port: 0);
        expect(office.device, device);
        expect(server.identity.fingerprint, summary.fingerprint);
        expect(office.receipts.single, receipt);
        expect(await office.evidence.complete(photo), isTrue);
        final blocked = PinnedConnection({
          ...sync.pairing!,
          'url': 'https://127.0.0.1:${server.port}',
        });
        try {
          await expectLater(blocked.request('/bundle', {}), throwsStateError);
        } finally {
          blocked.close();
        }
        await sync.enroll(server.invitation('127.0.0.1'));
        expect(sync.pairing!['token'], oldToken);
        await sync.sync();
        expect(sync.message, contains('Confirm code'));
        expect(phone.submissions.last['_state'], 'queued');
        expect(office.submissions.length, 1);
        server.authority.confirm(phone.device);
        await sync.sync();
        await sync.sync();
        expect(office.submissions.map((p) => p['id']), [
          first['id'],
          queued['id'],
        ]);
        expect(office.receipts.single, receipt);
        expect(phone.receipts.single, receipt);
        expect(phone.submissions.last['_state'], 'received');
        expect(valuesOf(await office.fields())['meter'], 713);
        expect(sync.message, 'Saved on the computer. Photos verified.');
        final revoked = PinnedConnection({
          ...sync.pairing!,
          'token': revokedToken,
        });
        try {
          await expectLater(revoked.request('/bundle', {}), throwsStateError);
        } finally {
          revoked.close();
        }
        expect(phone.db.select('SELECT * FROM phones'), isEmpty);
        expect(
          await File('${phone.root.path}/office-key.pem').exists(),
          isFalse,
        );
      } finally {
        await server.close();
        await office.close();
        await phone.close();
        await root.delete(recursive: true);
      }
    },
  );
}
