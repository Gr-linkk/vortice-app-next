import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/local_sync.dart';
import 'package:maintenance_local/model.dart';

void main() {
  late Directory root;
  late LabStore office;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('sync-lab-identity-');
    office = await LabStore.open(
      Directory('${root.path}/office'),
      office: true,
    );
  });
  tearDown(() async {
    await office.close();
    await root.delete(recursive: true);
  });
  test(
    'A partial or missing established identity fails without replacing files',
    () async {
      final original = await OfficeIdentity.load(office);
      final key = File('${office.root.path}/office-key.pem');
      final keyHash = digest(await key.readAsBytes());
      await File('${office.root.path}/office-cert.pem').delete();
      await expectLater(OfficeIdentity.load(office), throwsStateError);
      expect(digest(await key.readAsBytes()), keyHash);
      expect(office.setting('officeFingerprint'), original.fingerprint);
      expect(
        await File('${office.root.path}/office-cert.pem').exists(),
        isFalse,
      );
      await key.delete();
      await expectLater(OfficeIdentity.load(office), throwsStateError);
      expect(await key.exists(), isFalse);
    },
  );
  test(
    'A corrupt key or changed stored pin gives a safe recovery error',
    () async {
      final original = await OfficeIdentity.load(office);
      final key = File('${office.root.path}/office-key.pem');
      await key.writeAsString(
        'synthetic secret must never be logged',
        flush: true,
      );
      Object? failure;
      try {
        await OfficeIdentity.load(office);
      } catch (error) {
        failure = error;
      }
      expect(failure, isA<StateError>());
      expect('$failure', contains('verified office backup'));
      expect('$failure', isNot(contains('synthetic secret')));
      expect(office.setting('officeFingerprint'), original.fingerprint);
      office.setSetting('officeFingerprint', '0' * 64);
      await expectLater(OfficeIdentity.load(office), throwsStateError);
      expect(await key.readAsString(), 'synthetic secret must never be logged');
    },
  );
  test(
    'Malformed saved connection leaves retries usable and gives safe guidance',
    () async {
      office.setSetting('pairing', {'url': 12});
      final sync = PhoneSync(office);
      await expectLater(sync.sync(), throwsA(isA<TypeError>()));
      expect(sync.busy, isFalse);
      expect(sync.message, contains('fresh complete invitation'));
      expect(
        connectionProblem(
          const SocketException('sensitive raw platform details'),
        ),
        contains('TCP 47831'),
      );
      expect(
        connectionProblem(
          const HandshakeException('sensitive certificate details'),
        ),
        contains('identity could not be verified'),
      );
      expect(
        connectionProblem(const FormatException('secret invitation content')),
        isNot(contains('secret invitation')),
      );
    },
  );
}
