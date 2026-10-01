import 'dart:async';
import 'dart:io';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:maintenance_local/agent_service/agent_service.dart';
import 'package:maintenance_local/agent_service/grants.dart';
import 'package:maintenance_local/agent_service/unix_transport.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/model.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';

// Deliberately public synthetic test credential. This is not an issuer and must
// never open an existing workspace or become a normal application launcher.
const syntheticFixtureToken = 'synthetic-agent-token';
const syntheticFixtureWorkspaceId = 'synthetic-agent-workspace';

class _FixtureGrants implements GrantProvider {
  _FixtureGrants(this.grant);
  final AgentGrant grant;
  @override
  Future<AgentGrant?> resolve(String token) async =>
      token == syntheticFixtureToken ? grant : null;
}

Future<void> main(List<String> args) async {
  LabStore? store;
  UnixAgentTransport? transport;
  var initialized = false;
  final subscriptions = <StreamSubscription<ProcessSignal>>[];
  try {
    if (!Platform.isLinux ||
        args.length != 9 ||
        args.first != '--synthetic-fixture') {
      throw StateError('fixture');
    }
    final options = <String, String>{};
    for (var i = 1; i < args.length; i += 2) {
      if (!{
            '--workspace',
            '--socket',
            '--ready',
            '--native-library',
          }.contains(args[i]) ||
          options.containsKey(args[i])) {
        throw StateError('fixture');
      }
      options[args[i]] = args[i + 1];
    }
    if (options.length != 4) throw StateError('fixture');
    final workspace = Directory(options['--workspace']!);
    final socket = File(options['--socket']!);
    final ready = File(options['--ready']!);
    final library = File(options['--native-library']!);
    // Validate every destination before native init, DB open, mkdir or chmod.
    if (workspace.path != workspace.absolute.path ||
        FileSystemEntity.typeSync(workspace.path, followLinks: false) !=
            FileSystemEntityType.notFound ||
        FileSystemEntity.typeSync(workspace.parent.path, followLinks: false) !=
            FileSystemEntityType.directory ||
        workspace.parent.resolveSymbolicLinksSync() != workspace.parent.path ||
        socket.path != socket.absolute.path ||
        ready.path != ready.absolute.path ||
        socket.path == ready.path ||
        ready.parent.path != socket.parent.path ||
        FileSystemEntity.typeSync(socket.parent.path, followLinks: false) !=
            FileSystemEntityType.directory ||
        socket.parent.resolveSymbolicLinksSync() != socket.parent.path ||
        (socket.parent.statSync().mode & 0xfff) != 0x1c0 ||
        FileSystemEntity.typeSync(socket.path, followLinks: false) !=
            FileSystemEntityType.notFound ||
        FileSystemEntity.typeSync(ready.path, followLinks: false) !=
            FileSystemEntityType.notFound ||
        library.path != library.absolute.path ||
        FileSystemEntity.typeSync(library.path, followLinks: false) !=
            FileSystemEntityType.file) {
      throw StateError('fixture');
    }
    await RustLib.init(externalLibrary: ExternalLibrary.open(library.path));
    initialized = true;
    store = await LabStore.open(workspace, office: true, maintenanceOnly: true);
    await store.createCompany('Synthetic agent company');
    final equipment = <Json>[];
    final jobs = <Json>[];
    final procedure = await store.publishChecklist(
      title: 'Synthetic inspection',
      items: [
        {'id': 'guard', 'label': 'Inspect guard', 'input_type': 'check'},
      ],
    );
    for (var i = 1; i <= 2; i++) {
      final item = await store.addEquipment(
        name: 'Synthetic equipment $i',
        meterUnit: 'none',
      );
      equipment.add(item);
      jobs.add(
        await store.prepareWork(
          equipmentId: item['id'] as String,
          templateId: procedure['id'] as String,
          title: 'Synthetic inspection $i',
        ),
      );
    }
    final grant = AgentGrant(
      id: 'synthetic-grant',
      actorId: 'synthetic-external-agent',
      workspaceId: syntheticFixtureWorkspaceId,
      companyId: store.catalog!['companyId'] as String,
      deviceId: store.device,
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      commands: AgentService.commands,
    );
    final service = AgentService(
      store: store,
      workspaceId: syntheticFixtureWorkspaceId,
      serviceDeviceId: store.device,
      grants: _FixtureGrants(grant),
    );
    transport = await UnixAgentTransport.start(
      socketPath: socket.path,
      handler: service.handle,
    );
    await ready.writeAsString(
      canonical({
        'synthetic_fixture': true,
        'protocol_version': 1,
        'workspace_id': syntheticFixtureWorkspaceId,
        'company_id': grant.companyId,
        'device_id': grant.deviceId,
        'equipment_ids': equipment.map((item) => item['id']).toList(),
        'job_ids': jobs.map((job) => job['id']).toList(),
        'procedure_ids': [procedure['id']],
      }),
      flush: true,
    );
    final permission = await Process.run('/usr/bin/chmod', [
      '600',
      '--',
      ready.path,
    ]);
    if (permission.exitCode != 0) throw StateError('fixture');
    final stop = Completer<void>();
    for (final signal in [ProcessSignal.sigterm, ProcessSignal.sigint]) {
      subscriptions.add(
        signal.watch().listen((_) {
          if (!stop.isCompleted) stop.complete();
        }),
      );
    }
    await stop.future;
  } catch (_) {
    stderr.writeln(
      'Synthetic fixture refused or could not start. Use explicit fixture mode, new absent workspace, private socket directory and absent ready file. Existing files were retained.',
    );
    exitCode = 1;
  } finally {
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    await transport?.close();
    await store?.close();
    if (initialized) RustLib.dispose();
  }
}
