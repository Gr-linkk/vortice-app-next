import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/agent_service/access_scope.dart';
import 'package:maintenance_local/agent_service/agent_host.dart';
import 'package:maintenance_local/app.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';
import 'package:maintenance_local/ui/agent_connections_page.dart';
import 'package:maintenance_local/ui/agent_proposals_page.dart';

import 'support/native_widget_cleanup.dart';

const renderKey = ValueKey('normal-office-agent-entry');

Future<void> capture(WidgetTester tester, String name) async {
  final output = Platform.environment['VORTICE_RENDER_OUTPUT'];
  if (output == null || output.isEmpty) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(renderKey),
  );
  await tester.runAsync(() async {
    final raster = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await raster.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$output/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
    } finally {
      raster.dispose();
    }
  });
}

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
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await RustLib.init(
      externalLibrary: ExternalLibrary.open(
        Platform.environment['MAINTENANCE_NATIVE_LIBRARY']!,
      ),
    );
    await (FontLoader('Roboto')
          ..addFont(
            File(
              '../../assets/fonts/Roboto-Regular.ttf',
            ).readAsBytes().then(ByteData.sublistView),
          )
          ..addFont(
            File(
              '../../assets/fonts/Roboto-Bold.ttf',
            ).readAsBytes().then(ByteData.sublistView),
          ))
        .load();
  });

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
      expect(find.text('Agent suggestions'), findsNothing);
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

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'normal office entries open controls and trusted review at ${scale}x',
      (tester) async {
        tester.view.physicalSize = const Size(412, 915);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
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
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await finishNativeWidgetCleanup(tester, () async {
            await host.close();
            await store.close();
            await root.delete(recursive: true);
          });
        });
        await tester.pumpWidget(
          RepaintBoundary(
            key: renderKey,
            child: LabApp(
              store: store,
              officePort: 0,
              textScale: scale,
              agentHostFactory: (_) => host,
            ),
          ),
        );
        await settle(tester);
        final entry = find.widgetWithText(OutlinedButton, 'Agent connections');
        await tester.ensureVisible(entry);
        await tester.pump();
        expect(entry.hitTestable(), findsOneWidget);
        await capture(tester, 'normal-office-agent-entry-${scale}x');
        await tester.tap(entry);
        await settle(tester);
        expect(find.byType(AgentConnectionsPage), findsOneWidget);
        expect(host.snapshot.enabled, isFalse);
        expect(host.snapshot.socketPath, isNull);
        expect(host.grants, isEmpty);
        await capture(tester, 'normal-office-agent-controls-${scale}x');
        await tester.pageBack();
        await tester.pump(const Duration(milliseconds: 400));
        await settle(tester);
        final suggestions = find.widgetWithText(
          OutlinedButton,
          'Agent suggestions',
        );
        await tester.ensureVisible(suggestions);
        await tester.pump();
        expect(suggestions.hitTestable(), findsOneWidget);
        await tester.tap(suggestions);
        await settle(tester);
        expect(find.byType(AgentProposalsPage), findsOneWidget);
        final reviewPage = tester.widget<AgentProposalsPage>(
          find.byType(AgentProposalsPage),
        );
        expect(
          reviewPage.reviewer.workspaceId,
          AgentAccessScope.forOffice(store)!.workspaceId,
        );
        expect(reviewPage.reviewer.serviceDeviceId, store.device);
        expect(host.snapshot.enabled, isFalse);
        await capture(tester, 'normal-office-agent-suggestions-${scale}x');
      },
    );
  }
}
