import 'dart:io';
import 'lab_store.dart';
import 'local_sync.dart';
import 'model.dart';

/// A restore chosen from an empty office keeps opening on later launches.
/// The original empty directory is retained as a launcher, never overwritten.
Future<LabStore> openLabWorkspace(
  Directory root, {
  required bool office,
  bool maintenanceOnly = false,
}) async {
  final original = await LabStore.open(
    root,
    office: office,
    maintenanceOnly: maintenanceOnly,
  );
  LabStore? restored;
  try {
    final pointer = original.setting('officeRestoredTo');
    if (pointer == null) return original;
    if (!office ||
        original.workspace != null ||
        pointer is! Json ||
        pointer['path'] is! String ||
        pointer['device'] is! String ||
        pointer['fingerprint'] is! String ||
        !hashPattern.hasMatch(pointer['fingerprint'] as String)) {
      throw StateError(
        'The saved office recovery location is invalid. Files have been retained.',
      );
    }
    final target = Directory(pointer['path'] as String);
    if (await FileSystemEntity.type(target.path, followLinks: false) !=
            FileSystemEntityType.directory ||
        await FileSystemEntity.type(
              '${target.path}/workspace.sqlite',
              followLinks: false,
            ) !=
            FileSystemEntityType.file ||
        !await File('${target.path}/office-key.pem').exists() ||
        !await File('${target.path}/office-cert.pem').exists()) {
      throw StateError(
        'The restored office folder is unavailable. Reconnect its storage or use another verified backup. Existing files have been retained.',
      );
    }
    restored = await LabStore.open(
      target,
      office: true,
      maintenanceOnly: maintenanceOnly,
    );
    final marker = restored.setting('officeRestore');
    if (restored.device != pointer['device'] ||
        marker is! Json ||
        marker['fingerprint'] != pointer['fingerprint'] ||
        (await OfficeIdentity.load(restored)).fingerprint !=
            pointer['fingerprint']) {
      throw StateError(
        'The restored office identity changed. Existing files have been retained.',
      );
    }
    await original.close();
    return restored;
  } catch (_) {
    await restored?.close();
    await original.close();
    rethrow;
  }
}
