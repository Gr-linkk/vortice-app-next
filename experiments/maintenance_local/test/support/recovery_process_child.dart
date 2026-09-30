import 'dart:io';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/office_backup.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';

/// Synthetic test driver for the create API (the owner CLI offers restore).
Future<void> main(List<String> args) async {
  LabStore? store;
  try {
    await RustLib.init(
      externalLibrary: ExternalLibrary.open(
        File('rust/target/debug/librust_lib_sync_lab.so').absolute.path,
      ),
    );
    store = await LabStore.open(Directory(args[0]), office: true);
    await OfficeBackup.create(store, Directory(args[1]));
    stdout.writeln('created');
  } catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  } finally {
    await store?.close();
    RustLib.dispose();
  }
}
