import 'dart:io';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/local_sync.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';

void main() {
  setUpAll(
    () => RustLib.init(
      externalLibrary: ExternalLibrary.open(
        Platform.environment['MAINTENANCE_NATIVE_LIBRARY'] ??
            File('rust/target/debug/librust_lib_sync_lab.so').absolute.path,
      ),
    ),
  );
  late Directory root;
  late LabStore office, phone;
  late OfficeServer server;
  late PhoneSync sync;
  late String firstId, secondId;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('maintenance-phone-status-');
    office = await LabStore.open(
      Directory('${root.path}/office'),
      office: true,
    );
    await office.createCompany('Synthetic setup company');
    final equipment = await office.addEquipment(name: 'Synthetic generator');
    final template = await office.publishChecklist(
      title: 'Synthetic inspection',
      items: [
        {'id': 'guard', 'label': 'Inspect the guard', 'input_type': 'check'},
      ],
    );
    Future<String> prepare(String title) async =>
        (await office.prepareWork(
              equipmentId: equipment['id'] as String,
              templateId: template['id'] as String,
              title: title,
            ))['id']
            as String;
    firstId = await prepare('First synthetic inspection');
    secondId = await prepare('Second synthetic inspection');
    phone = await LabStore.open(Directory('${root.path}/phone'), office: false);
    server = await OfficeServer.start(
      office,
      port: 0,
      address: InternetAddress.loopbackIPv4,
    );
    sync = PhoneSync(phone);
    await sync.enroll(server.invitation('127.0.0.1'));
    server.authority.confirm(phone.device);
    await sync.sync();
  });
  tearDown(() async {
    await server.close();
    await phone.close();
    await office.close();
    await root.delete(recursive: true);
  });

  test(
    'selecting work preserves confirmation but nonselected edits do not',
    () async {
      expect(sync.visibleMessage, 'Saved on the computer. Photos verified.');
      phone.selectJob(firstId);
      expect(sync.visibleMessage, 'Saved on the computer. Photos verified.');
      phone.selectJob(secondId);
      expect(sync.visibleMessage, 'Saved on the computer. Photos verified.');
      await phone.update({
        'notes': 'New draft after the completed send',
      }, jobId: firstId);
      expect(sync.visibleMessage, 'Saved on this phone—waiting to send.');
      await sync.sync();
      expect(sync.visibleMessage, 'Saved on the computer. Photos verified.');
      expect(
        await office.fields(jobId: firstId),
        await phone.fields(jobId: firstId),
      );
    },
  );

  test(
    'queued work is visible after reopening and clears only after receipt',
    () async {
      await phone.update({
        'answer:guard': {'result': 'action', 'value': ''},
        'meter': 21.5,
        'notes': 'Synthetic queued inspection',
      }, jobId: firstId);
      await phone.attach([1, 2, 3, 4], jobId: firstId);
      final submission = await phone.submit(jobId: firstId);
      await phone.close();
      phone = await LabStore.open(
        Directory('${root.path}/phone'),
        office: false,
      );
      sync = PhoneSync(phone);
      expect(sync.visibleMessage, 'Saved on this phone—waiting to send.');
      await sync.sync();
      expect(sync.visibleMessage, 'Saved on the computer. Photos verified.');
      expect(phone.submissions.single['_state'], 'received');
      expect(office.submissions.single['id'], submission['id']);
    },
  );

  test(
    'missing required document or newly received work needs a send',
    () async {
      final retained = phone.documentFor(secondId)!;
      phone.db.execute('DELETE FROM documents WHERE id=?', [secondId]);
      expect(sync.visibleMessage, 'Saved on this phone—waiting to send.');
      phone.saveDocument(retained, jobId: secondId);
      expect(sync.visibleMessage, 'Saved on the computer. Photos verified.');

      await office.prepareWork(
        equipmentId: office.equipment.single['id'] as String,
        templateId: office.templates.single['id'] as String,
        title: 'New synthetic inspection',
      );
      await phone.importOfficeBundle(await office.publicBundle());
      expect(sync.visibleMessage, 'Saved on this phone—waiting to send.');
      await sync.sync();
      expect(sync.visibleMessage, 'Saved on the computer. Photos verified.');
    },
  );

  test('a queued version downgrades unchanged verified documents', () async {
    await phone.update({
      'answer:guard': {'result': 'pass', 'value': ''},
      'meter': 12,
      'notes': 'Synthetic inspection ready to submit',
    }, jobId: secondId);
    await phone.attach([5, 6, 7], jobId: secondId);
    await sync.sync();
    phone.selectJob(firstId);
    expect(sync.visibleMessage, 'Saved on the computer. Photos verified.');
    final document = phone.documentFor(secondId)!.toList();
    await phone.submit(jobId: secondId);
    expect(phone.documentFor(secondId), document);
    expect(sync.visibleMessage, 'Saved on this phone—waiting to send.');
    await sync.sync();
    expect(sync.visibleMessage, 'Saved on the computer. Photos verified.');
  });

  test(
    'unreachable computer retains local status with separate safe help',
    () async {
      await phone.update({
        'notes': 'Retained through a controlled interruption',
      });
      await server.close();
      await expectLater(sync.sync(), throwsA(isA<SocketException>()));
      expect(sync.visibleMessage, 'Saved on this phone—waiting to send.');
      expect(sync.lastGuidance!.message, 'Cannot reach the computer.');
      expect(sync.lastGuidance!.nextStep, contains('same Wi-Fi or hotspot'));
      final responses = sync.connectionResponses;
      ConnectionGuidance? retryHelp;
      sync.onChange = () {
        if (sync.busy) retryHelp ??= sync.lastGuidance;
      };
      await expectLater(sync.sync(), throwsA(isA<SocketException>()));
      expect(retryHelp, isNotNull);
      expect(sync.connectionResponses, responses);
      expect((await phone.fields())['notes'], [
        'Retained through a controlled interruption',
      ]);
    },
  );
  test(
    'fresh same-office pairing clears stale help and shows confirmation',
    () async {
      final token = sync.pairing!['token'];
      final responses = sync.connectionResponses;
      await server.close();
      await expectLater(sync.sync(), throwsA(isA<SocketException>()));
      expect(sync.lastGuidance, isNotNull);
      office.db.execute("UPDATE phones SET status='pending' WHERE id=?", [
        phone.device,
      ]);
      server = await OfficeServer.start(
        office,
        port: 0,
        address: InternetAddress.loopbackIPv4,
      );
      await sync.enroll(server.invitation('127.0.0.1'));
      expect(sync.lastGuidance, isNull);
      expect(sync.connectionResponses, responses + 1);
      expect(sync.visibleMessage, startsWith('Confirm code '));
      expect(sync.pairing!['token'], token);
    },
  );

  test('revoked response remains visible without generic retry help', () async {
    server.authority.revoke(phone.device);
    final responses = sync.connectionResponses;
    await sync.sync();
    expect(sync.connectionResponses, responses + 1);
    expect(sync.lastGuidance, isNull);
    expect(sync.visibleMessage, 'This phone has been revoked.');
  });
}
