import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/agent_service/access_scope.dart';
import 'package:maintenance_local/agent_service/agent_host.dart';
import 'package:maintenance_local/app.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';
import 'package:maintenance_local/ui/agent_connections_page.dart';

import 'support/native_widget_cleanup.dart';

class _PausedHost extends OfficeAgentHost {
  _PausedHost(LabStore store) : super(store: store);
  final ready = Completer<void>();
  var closes = 0;
  @override
  Future<void> initialize() => ready.future;
  @override
  Future<void> close() async {
    closes++;
  }
}

Future<void> settle(WidgetTester tester) async {
  for (var attempt = 0; attempt < 8; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 30));
  }
  expect(tester.takeException(), isNull);
}

void main() {
  setUpAll(
    () => RustLib.init(
      externalLibrary: ExternalLibrary.open(
        Platform.environment['MAINTENANCE_NATIVE_LIBRARY']!,
      ),
    ),
  );

  testWidgets(
    'disposing during host startup never starts a late office server',
    (tester) async {
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('agent-nav-dispose-'),
      ))!;
      final store = (await tester.runAsync(
        () => LabStore.open(
          Directory('${root.path}/office'),
          office: true,
          maintenanceOnly: true,
        ),
      ))!;
      final host = _PausedHost(store);
      await tester.pumpWidget(
        LabApp(store: store, officePort: 0, agentHostFactory: (_) => host),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      expect(host.closes, 1);
      host.ready.complete();
      await settle(tester);
      expect(store.setting('officeFingerprint'), isNull);
      expect(File('${store.root.path}/office-cert.pem').existsSync(), isFalse);
      await finishNativeWidgetCleanup(tester, () async {
        await store.close();
        await root.delete(recursive: true);
      });
    },
  );

  testWidgets(
    'the phone never constructs an office agent host or management route',
    (tester) async {
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('agent-nav-phone-'),
      ))!;
      final phone = (await tester.runAsync(
        () => LabStore.open(
          Directory('${root.path}/phone'),
          office: false,
          maintenanceOnly: true,
        ),
      ))!;
      var constructed = 0;
      await tester.pumpWidget(
        LabApp(
          store: phone,
          agentHostFactory: (store) {
            constructed++;
            return OfficeAgentHost(store: store);
          },
        ),
      );
      await settle(tester);
      expect(constructed, 0);
      expect(AgentAccessScope.forOffice(phone), isNull);
      expect(find.text('Agent connections'), findsNothing);
      expect(
        Directory('${phone.root.path}/agent-access-v1').existsSync(),
        isFalse,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
      await finishNativeWidgetCleanup(tester, () async {
        await phone.close();
        await root.delete(recursive: true);
      });
    },
  );

  testWidgets('the normal office entry opens disabled connection controls', (
    tester,
  ) async {
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('agent-nav-office-'),
    ))!;
    final store = (await tester.runAsync(
      () => LabStore.open(
        Directory('${root.path}/office'),
        office: true,
        maintenanceOnly: true,
      ),
    ))!;
    await tester.runAsync(
      () => store.createCompany('Synthetic navigation company'),
    );
    final host = OfficeAgentHost(
      store: store,
      runtimeDirectory: Directory('${root.path}/runtime'),
    );
    await tester.pumpWidget(
      LabApp(store: store, officePort: 0, agentHostFactory: (_) => host),
    );
    await settle(tester);
    final entry = find.widgetWithText(OutlinedButton, 'Agent connections');
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await settle(tester);
    expect(find.byType(AgentConnectionsPage), findsOneWidget);
    expect(host.snapshot.enabled, isFalse);
    expect(host.snapshot.socketPath, isNull);
    expect(host.grants, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
    await finishNativeWidgetCleanup(tester, () async {
      await host.close();
      await store.close();
      await root.delete(recursive: true);
    });
  });
}
