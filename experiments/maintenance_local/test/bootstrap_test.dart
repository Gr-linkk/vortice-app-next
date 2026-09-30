import 'dart:io';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/lab_bootstrap.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/local_sync.dart';
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
  setUp(
    () async =>
        root = await Directory.systemTemp.createTemp('sync-lab-bootstrap-'),
  );
  tearDown(() async => root.delete(recursive: true));
  test(
    'Restored office reopens from the original empty launcher without identity rotation',
    () async {
      final source = await LabStore.open(
        Directory('${root.path}/source'),
        office: true,
      );
      await source.createWorkspace();
      final identity = await OfficeIdentity.load(source);
      await source.update({'notes': 'Restored synthetic work'});
      final backup = Directory('${root.path}/backup'),
          target = Directory('${root.path}/restored');
      await OfficeBackup.create(source, backup);
      await OfficeBackup.restore(
        backup,
        target,
        expectedFingerprint: identity.fingerprint,
      );
      final launcherRoot = Directory('${root.path}/launcher');
      final launcher = await LabStore.open(launcherRoot, office: true);
      launcher.setSetting('officeRestoredTo', {
        'path': target.path,
        'device': source.device,
        'fingerprint': identity.fingerprint,
      });
      await launcher.close();
      final reopened = await openLabWorkspace(launcherRoot, office: true);
      expect(reopened.root.path, target.path);
      expect(reopened.device, source.device);
      expect(await reopened.fields(), await source.fields());
      expect(
        (await OfficeIdentity.load(reopened)).fingerprint,
        identity.fingerprint,
      );
      await reopened.close();
      await source.close();
    },
  );
  test(
    'Unavailable or mismatched restore pointers retain files and fail closed',
    () async {
      final launcherRoot = Directory('${root.path}/launcher'),
          missing = Directory('${root.path}/absent');
      final launcher = await LabStore.open(launcherRoot, office: true);
      launcher.setSetting('officeRestoredTo', {
        'path': missing.path,
        'device': 'retained-id',
        'fingerprint': '0' * 64,
      });
      await launcher.close();
      await expectLater(
        openLabWorkspace(launcherRoot, office: true),
        throwsStateError,
      );
      expect(await missing.exists(), isFalse);
      final retained = await LabStore.open(launcherRoot, office: true);
      expect(retained.setting('officeRestoredTo')['device'], 'retained-id');
      retained.setSetting('officeRestoredTo', {
        'path': launcherRoot.path,
        'device': retained.device,
        'fingerprint': '0' * 64,
      });
      await retained.close();
      await expectLater(
        openLabWorkspace(launcherRoot, office: true),
        throwsStateError,
      );
      expect(
        await File('${launcherRoot.path}/office-key.pem').exists(),
        isFalse,
      );
    },
  );
}
