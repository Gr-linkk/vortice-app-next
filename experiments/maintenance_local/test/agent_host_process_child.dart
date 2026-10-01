import 'dart:convert';
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:maintenance_local/agent_service/agent_host.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';

/// Standalone child for synthetic lock/crash acceptance. It cannot operate on a
/// live workspace: the parent must provide an ordinary private temp fixture and
/// its exact test marker. No credential is created or printed by this child.
Future<void> main(List<String> args) async {
  LabStore? store;
  OfficeAgentHost? host;
  var initialized = false;
  var phase = 'fixture';
  try {
    if (args.length != 2 || !{'hold', 'probe'}.contains(args[1])) {
      throw StateError('Synthetic host fixture required.');
    }
    final root = Directory(args[0]);
    final marker = File('${root.path}/agent-host-synthetic.txt');
    if (!root.path.startsWith('/tmp/host-test-') ||
        root.resolveSymbolicLinksSync() != root.path ||
        (root.statSync().mode & 0xfff) != 0x1c0 ||
        FileSystemEntity.typeSync(marker.path, followLinks: false) !=
            FileSystemEntityType.file ||
        marker.readAsStringSync() != 'Synthetic agent host fixture only.') {
      throw StateError('Synthetic host fixture required.');
    }
    phase = 'native';
    await RustLib.init(
      externalLibrary: ExternalLibrary.open(
        Platform.environment['MAINTENANCE_NATIVE_LIBRARY']!,
      ),
    );
    initialized = true;
    phase = 'workspace';
    store = await LabStore.open(
      Directory('${root.path}/office'),
      office: true,
      maintenanceOnly: true,
    );
    phase = 'host';
    host = OfficeAgentHost(
      store: store,
      runtimeDirectory: Directory('${root.path}/runtime'),
      now: () => DateTime.utc(2026, 10, 1, 12),
    );
    await host.initialize();
    stdout.writeln(
      jsonEncode({
        'state': host.snapshot.state.name,
        'enabled': host.snapshot.enabled,
        'socket_path': host.snapshot.socketPath,
      }),
    );
    await stdout.flush();
    if (args[1] == 'hold') await stdin.drain<void>();
  } catch (_) {
    stderr.writeln('Synthetic host child could not complete ($phase).');
    exitCode = 1;
  } finally {
    await host?.close();
    await store?.close();
    if (initialized) RustLib.dispose();
  }
}
