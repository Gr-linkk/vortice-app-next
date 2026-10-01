import 'dart:io';

import 'package:maintenance_local/agent_service/access_scope.dart';
import 'package:maintenance_local/agent_service/grant_store.dart';

/// A synthetic subprocess that owns a real OS lease; it never issues tokens.
Future<void> main(List<String> args) async {
  OfficeAgentGrantStore? store;
  try {
    store = await OfficeAgentGrantStore.open(
      workspaceRoot: Directory(args[0]),
      scope: const AgentAccessScope(
        workspaceId: 'ws-synthetic',
        companyId: 'company-synthetic',
        deviceId: 'office-synthetic',
      ),
    );
    if (args[1] == 'hold') {
      stdout.writeln('ready');
      await stdout.flush();
      await stdin.drain<void>();
    } else {
      stdout.writeln('opened');
    }
  } catch (_) {
    stdout.writeln('refused');
    exitCode = 3;
  } finally {
    await store?.close();
  }
}
