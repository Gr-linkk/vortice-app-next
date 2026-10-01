import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/agent_service/access_models.dart';
import 'package:maintenance_local/agent_service/agent_host.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/model.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';
import 'package:maintenance_local/ui/agent_connections_page.dart';
import 'package:maintenance_local/ui/common.dart';

import 'support/native_widget_cleanup.dart';

const _boundaryKey = Key('agent-connections-render-boundary');

void _phoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(
    tester.takeException(),
    isNull,
    reason: 'Connection screens must have no framework or overflow errors.',
  );
}

Future<void> _show(WidgetTester tester, Finder finder) async {
  expect(finder, findsOneWidget);
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.15);
  await tester.pump(const Duration(milliseconds: 250));
  expect(
    finder.hitTestable(),
    findsOneWidget,
    reason: 'Connection actions must remain reachable.',
  );
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _show(tester, finder);
  await tester.tap(finder);
  await _settle(tester);
}

Future<void> _capture(WidgetTester tester, String name) async {
  final output = Platform.environment['VORTICE_RENDER_OUTPUT'];
  if (output == null || output.isEmpty) return;
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_boundaryKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$output/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
    } finally {
      image.dispose();
    }
  });
}

ThemeData _theme() => ThemeData(
  useMaterial3: true,
  fontFamily: 'Roboto',
  scaffoldBackgroundColor: const Color(0xfff7f4ed),
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xff103d3c),
    primary: const Color(0xff103d3c),
    surface: const Color(0xfff7f4ed),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xfff7f4ed),
    foregroundColor: Color(0xff103d3c),
  ),
  inputDecorationTheme: const InputDecorationTheme(
    border: OutlineInputBorder(),
    filled: true,
    fillColor: Colors.white,
  ),
  cardTheme: const CardThemeData(
    color: Colors.white,
    elevation: 0,
    margin: EdgeInsets.symmetric(vertical: 8),
  ),
);

class _Fixture {
  _Fixture(this.root, this.store, this.host, this.equipment, this.jobs);
  final Directory root;
  final LabStore store;
  final OfficeAgentHost host;
  final List<Json> equipment, jobs;

  static Future<_Fixture> open({
    bool office = true,
    bool prepared = true,
    bool unsafeRuntime = false,
  }) async {
    final root = await Directory.systemTemp.createTemp('ac-ui-');
    final store = await LabStore.open(
      Directory('${root.path}/office'),
      office: office,
      maintenanceOnly: true,
    );
    final equipment = <Json>[];
    final jobs = <Json>[];
    if (office && prepared) {
      await store.createCompany(
        'Synthetic North Construction',
        coordinatorName: 'Synthetic Coordinator',
      );
      final procedure = await store.publishChecklist(
        title: 'Synthetic guard inspection',
        items: [
          {'id': 'guard', 'label': 'Inspect guard', 'input_type': 'check'},
        ],
      );
      for (var i = 1; i <= 2; i++) {
        final item = await store.addEquipment(
          name: 'Synthetic excavator $i',
          serial: 'SYNTHETIC-$i',
          meterUnit: 'hours',
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
    }
    final runtime = Directory('${root.path}/run');
    if (unsafeRuntime) {
      await File(
        runtime.path,
      ).writeAsString('Synthetic foreign runtime marker');
    }
    final host = OfficeAgentHost(store: store, runtimeDirectory: runtime);
    await host.initialize();
    return _Fixture(root, store, host, equipment, jobs);
  }

  Future<void> close() async {
    await host.close();
    await store.close();
    await root.delete(recursive: true);
  }
}

Future<void> _mount(
  WidgetTester tester,
  OfficeAgentHost host, {
  double scale = 1,
  bool entry = false,
}) => tester.pumpWidget(
  RepaintBoundary(
    key: _boundaryKey,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _theme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: entry
          ? Builder(
              builder: (context) => Scaffold(
                appBar: AppBar(title: const Text('Office workspace')),
                body: page([
                  const Text('Synthetic North Construction'),
                  FilledButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => AgentConnectionsPage(host: host),
                      ),
                    ),
                    child: const Text('Agent connections'),
                  ),
                ]),
              ),
            )
          : AgentConnectionsPage(host: host),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await RustLib.init(
      externalLibrary: ExternalLibrary.open(
        File(
          Platform.environment['MAINTENANCE_NATIVE_LIBRARY'] ??
              'rust/target/debug/librust_lib_sync_lab.so',
        ).absolute.path,
      ),
    );
    final fonts = FontLoader('Roboto')
      ..addFont(
        File(
          '../../assets/fonts/Roboto-Regular.ttf',
        ).readAsBytes().then(ByteData.sublistView),
      )
      ..addFont(
        File(
          '../../assets/fonts/Roboto-Bold.ttf',
        ).readAsBytes().then(ByteData.sublistView),
      );
    await fonts.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'actual office connection lifecycle and creation render at 412x915 ${scale}x',
      (tester) async {
        _phoneSize(tester);
        addTearDown(tester.view.resetViewInsets);
        late _Fixture fixture;
        await tester.runAsync(() async => fixture = await _Fixture.open());
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await finishNativeWidgetCleanup(tester, fixture.close);
        });
        String? copied;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String;
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        final suffix = '${scale.toInt()}x';
        await _mount(tester, fixture.host, scale: scale, entry: true);
        await _settle(tester);
        await _tap(
          tester,
          find.widgetWithText(FilledButton, 'Agent connections'),
        );
        expect(find.text('Disabled'), findsOneWidget);
        expect(fixture.host.snapshot.enabled, isFalse);
        expect(fixture.host.grants, isEmpty);
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('new-agent-connection')),
              )
              .onPressed,
          isNull,
        );
        await _capture(tester, 'agent-connections-disabled-$suffix');
        await _tap(
          tester,
          find.byKey(const ValueKey('enable-agent-connections')),
        );
        expect(fixture.host.snapshot.state, OfficeAgentHostState.listening);
        expect(fixture.host.grants, isEmpty);
        await _capture(tester, 'agent-connections-listening-$suffix');
        await _tap(tester, find.byKey(const ValueKey('new-agent-connection')));
        expect(find.text('1 hour'), findsOneWidget);
        expect(
          tester
              .widget<CheckboxListTile>(
                find.byKey(const ValueKey('agent-allow-notes')),
              )
              .value,
          isFalse,
        );
        await _tap(
          tester,
          find.byKey(const ValueKey('review-agent-connection')),
        );
        expect(find.text('Enter a name you will recognize.'), findsOneWidget);
        expect(
          find.text('Select at least one piece of equipment.'),
          findsOneWidget,
        );
        expect(fixture.host.grants, isEmpty);
        final name = find.byKey(const ValueKey('agent-connection-name'));
        await _show(tester, name);
        await tester.tap(name);
        await tester.enterText(name, 'Synthetic read agent');
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await _settle(tester);
        await _show(tester, name);
        await _capture(tester, 'agent-connections-name-keyboard-$suffix');
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final input = tester.widget<EditableText>(
          find.descendant(of: name, matching: find.byType(EditableText)),
        );
        expect(
          input.focusNode.hasFocus,
          isFalse,
          reason: 'Tab must leave the name field.',
        );
        await tester.tap(name);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        expect(
          input.focusNode.hasFocus,
          isFalse,
          reason: 'Done must close the name input.',
        );
        tester.view.resetViewInsets();
        await _settle(tester);
        final equipmentId = fixture.equipment.first['id'] as String;
        final jobId = fixture.jobs.first['id'] as String;
        final equipment = find.byKey(ValueKey('agent-equipment-$equipmentId'));
        final job = find.byKey(ValueKey('agent-job-$jobId'));
        await _tap(tester, equipment);
        expect(
          find.byKey(ValueKey('agent-job-${fixture.jobs.last['id']}')),
          findsNothing,
        );
        await _tap(tester, job);
        await _tap(tester, equipment);
        expect(job, findsNothing);
        await _tap(tester, equipment);
        expect(
          tester.widget<CheckboxListTile>(job).value,
          isFalse,
          reason: 'Removing equipment must also remove its selected jobs.',
        );
        await _show(tester, job);
        await _capture(tester, 'agent-connections-selections-$suffix');
        await _tap(
          tester,
          find.byKey(const ValueKey('review-agent-connection')),
        );
        expect(find.text('None — no access'), findsOneWidget);
        expect(
          fixture.host.grants,
          isEmpty,
          reason: 'Review does not create a credential.',
        );
        await _show(
          tester,
          find.byKey(const ValueKey('confirm-create-agent-connection')),
        );
        await _capture(tester, 'agent-connections-review-no-jobs-$suffix');
        await _tap(tester, find.byKey(const ValueKey('edit-agent-connection')));
        await _tap(tester, job);
        await _tap(
          tester,
          find.byKey(const ValueKey('review-agent-connection')),
        );
        expect(find.text('• Synthetic excavator 1'), findsOneWidget);
        expect(find.text('• Synthetic inspection 1'), findsOneWidget);
        expect(find.text('• Synthetic inspection 2'), findsNothing);
        expect(find.text('Read selected records only'), findsOneWidget);
        await _capture(tester, 'agent-connections-reviewed-$suffix');
        final before = DateTime.now().toUtc();
        await _tap(
          tester,
          find.byKey(const ValueKey('confirm-create-agent-connection')),
        );
        expect(fixture.host.grants, hasLength(1));
        final summary = fixture.host.grants.single;
        expect(summary.grant.equipmentIds, {equipmentId});
        expect(summary.grant.jobIds, {jobId});
        expect(summary.grant.commands.contains('proposals.create'), isFalse);
        expect(
          summary.grant.expiresAt.difference(before).inMinutes,
          inInclusiveRange(58, 60),
        );
        await _show(
          tester,
          find.byKey(const ValueKey('agent-created-credential')),
        );
        await _capture(
          tester,
          'agent-connections-synthetic-credential-$suffix',
        );
        await _tap(tester, find.byKey(const ValueKey('copy-agent-credential')));
        final credential = copied!;
        expect(credential, isNotEmpty);
        await _tap(tester, find.byKey(const ValueKey('done-agent-credential')));
        expect(
          find.byKey(const ValueKey('agent-created-credential')),
          findsNothing,
        );
        expect(find.text(credential), findsNothing);
        await _tap(
          tester,
          find.byKey(const ValueKey('agent-connection-settings')),
        );
        await _tap(tester, find.byKey(const ValueKey('copy-agent-settings')));
        final settings = jsonDecode(copied!) as Json;
        expect(settings['socket_path'], fixture.host.snapshot.socketPath);
        expect(settings['scope'], fixture.host.scope!.toJson());
        expect(settings['protocol_version'], 1);
        expect(copied!.contains(credential), isFalse);
        await _show(tester, find.byKey(const ValueKey('copy-agent-settings')));
        await _capture(tester, 'agent-connections-current-settings-$suffix');
        await _show(tester, find.text('Connection settings for this session'));
        await _capture(tester, 'agent-connections-settings-start-$suffix');
        await _tap(
          tester,
          find.byKey(const ValueKey('disable-agent-connections')),
        );
        expect(fixture.host.snapshot.state, OfficeAgentHostState.disabled);
        expect(
          find.byKey(const ValueKey('agent-connection-settings')),
          findsNothing,
        );
        await _show(tester, find.text('Paused — connections disabled'));
        await _capture(tester, 'agent-connections-paused-$suffix');
        await _tap(
          tester,
          find.byKey(const ValueKey('enable-agent-connections')),
        );
        await _show(tester, find.text('Active'));
        await _capture(tester, 'agent-connections-active-$suffix');
        await _tap(
          tester,
          find.byKey(ValueKey('revoke-agent-${summary.grant.id}')),
        );
        await _capture(tester, 'agent-connections-revoke-confirm-$suffix');
        await _tap(tester, find.byKey(const ValueKey('confirm-revoke-agent')));
        expect(fixture.host.grants.single.grant.revoked, isTrue);
        await _show(tester, find.text('Revoked — access blocked'));
        await _capture(tester, 'agent-connections-revoked-$suffix');
        expect(find.text(credential), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        await _settle(tester);
        final output = Platform.environment['VORTICE_RENDER_OUTPUT'];
        if (output != null && output.isNotEmpty) {
          await tester.runAsync(
            () => File('$output/agent-connections-receipt-$suffix.txt').writeAsString(
              'Actual Flutter AgentConnectionsPage renders at 412x915, ${scale}x text, repository Roboto/Material icons and Field Notes theme.\n'
              'Entry is an office navigation harness; coordinator-owned workspace navigation is verified separately during integration.\n'
              'Real synthetic native LabStore with prepared company, two equipment records/two jobs; actual OfficeAgentHost/private Unix listener and persisted synthetic grants. Fresh disabled state, explicit enable, no auto issuance, name/selection validation, simulated keyboard inset plus Tab/Done input, equipment/job filtering and selection clearing, review/edit/confirm, read-only one-hour default, one-time credential/copy/dismiss, credential-free current settings, disable/re-enable/revoke render without framework or overflow errors.\n'
              'Clipboard is mocked. Credential screenshot contains only a freshly created synthetic token and temporary workspace. Fixture deletes its workspace and credentials.\n'
              'Raster captures require visual inspection. Physical desktop/phone, installed app, real grant provisioning and unassisted acceptance are untested.\n',
            ),
          );
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }

  testWidgets(
    'unavailable host retains enabled intent and exposes no stale settings',
    (tester) async {
      _phoneSize(tester);
      late _Fixture fixture;
      await tester.runAsync(() async {
        fixture = await _Fixture.open(unsafeRuntime: true);
        await fixture.host.enable();
      });
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await finishNativeWidgetCleanup(tester, fixture.close);
      });
      await _mount(tester, fixture.host, scale: 2);
      await _settle(tester);
      expect(find.text('Unavailable'), findsOneWidget);
      expect(fixture.host.snapshot.enabled, isTrue);
      expect(
        find.byKey(const ValueKey('disable-agent-connections')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('agent-connection-settings')),
        findsNothing,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('new-agent-connection')),
            )
            .onPressed,
        isNull,
      );
      expect(find.textContaining('FileSystemException'), findsNothing);
      await _capture(tester, 'agent-connections-unavailable');
    },
  );

  for (final office in [false, true]) {
    testWidgets(
      '${office ? 'unprepared office' : 'phone'} cannot manage agent access',
      (tester) async {
        _phoneSize(tester);
        late _Fixture fixture;
        await tester.runAsync(
          () async =>
              fixture = await _Fixture.open(office: office, prepared: false),
        );
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await finishNativeWidgetCleanup(tester, fixture.close);
        });
        await _mount(tester, fixture.host, scale: 2);
        await _settle(tester);
        expect(
          find.textContaining('managed on the office computer'),
          findsOneWidget,
        );
        expect(find.byType(FilledButton), findsNothing);
        expect(find.byKey(const ValueKey('copy-agent-settings')), findsNothing);
        expect(fixture.host.grants, isEmpty);
        await _capture(
          tester,
          'agent-connections-${office ? 'unprepared' : 'phone-refused'}',
        );
      },
    );
  }

  testWidgets('expired synthetic connection displays blocked access', (
    tester,
  ) async {
    _phoneSize(tester);
    late _Fixture fixture;
    await tester.runAsync(() async {
      fixture = await _Fixture.open();
      await fixture.host.enable();
      await fixture.host.issue(
        AgentGrantRequest(
          label: 'Synthetic short connection',
          expiresAt: DateTime.now().toUtc().add(const Duration(seconds: 2)),
          jobIds: {},
          equipmentIds: {fixture.equipment.first['id'] as String},
        ),
      );
    });
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await finishNativeWidgetCleanup(tester, fixture.close);
    });
    await _mount(tester, fixture.host, scale: 2);
    await _settle(tester);
    expect(find.text('Active'), findsOneWidget);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2100)),
    );
    await tester.pump(const Duration(seconds: 2));
    await _show(tester, find.text('Expired — access blocked'));
    await _capture(tester, 'agent-connections-expired');
  });

  testWidgets(
    'notes and maximum expiry require explicit selection before creation',
    (tester) async {
      _phoneSize(tester);
      late _Fixture fixture;
      await tester.runAsync(() async {
        fixture = await _Fixture.open();
        await fixture.host.enable();
      });
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await finishNativeWidgetCleanup(tester, fixture.close);
      });
      await _mount(tester, fixture.host, scale: 2);
      await _settle(tester);
      await _tap(tester, find.byKey(const ValueKey('new-agent-connection')));
      await tester.enterText(
        find.byKey(const ValueKey('agent-connection-name')),
        'Synthetic notes agent',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await _settle(tester);
      await _tap(tester, find.byKey(const ValueKey('agent-connection-expiry')));
      await _tap(tester, find.text('7 days').last);
      await _tap(
        tester,
        find.byKey(
          ValueKey('agent-equipment-${fixture.equipment.first['id']}'),
        ),
      );
      await _tap(
        tester,
        find.byKey(ValueKey('agent-job-${fixture.jobs.first['id']}')),
      );
      await _tap(tester, find.byKey(const ValueKey('agent-allow-notes')));
      await _tap(tester, find.byKey(const ValueKey('review-agent-connection')));
      expect(fixture.host.grants, isEmpty);
      expect(
        find.text('Read selected records and suggest notes for office review'),
        findsOneWidget,
      );
      await _capture(tester, 'agent-connections-notes-review');
      final before = DateTime.now().toUtc();
      await _tap(
        tester,
        find.byKey(const ValueKey('confirm-create-agent-connection')),
      );
      expect(fixture.host.grants, hasLength(1));
      final grant = fixture.host.grants.single.grant;
      expect(grant.commands.contains('proposals.create'), isTrue);
      expect(
        grant.expiresAt.isAfter(before.add(const Duration(days: 7))),
        isFalse,
      );
      expect(
        grant.expiresAt.isAfter(before.add(const Duration(days: 6))),
        isTrue,
      );
      expect(
        grant.commands.any(
          (command) => command.contains('approve') || command.contains('apply'),
        ),
        isFalse,
      );
      await _tap(tester, find.byKey(const ValueKey('done-agent-credential')));
      await _show(
        tester,
        find.text('Read selected records and suggest notes for office review'),
      );
      await _capture(tester, 'agent-connections-notes-saved');
    },
  );

  testWidgets(
    'disable during review prevents issuance and presents safe guidance',
    (tester) async {
      _phoneSize(tester);
      late _Fixture fixture;
      await tester.runAsync(() async {
        fixture = await _Fixture.open();
        await fixture.host.enable();
      });
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await finishNativeWidgetCleanup(tester, fixture.close);
      });
      await _mount(tester, fixture.host, scale: 2);
      await _settle(tester);
      await _tap(tester, find.byKey(const ValueKey('new-agent-connection')));
      await tester.enterText(
        find.byKey(const ValueKey('agent-connection-name')),
        'Synthetic stale review',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await _settle(tester);
      await _tap(
        tester,
        find.byKey(
          ValueKey('agent-equipment-${fixture.equipment.first['id']}'),
        ),
      );
      await _tap(tester, find.byKey(const ValueKey('review-agent-connection')));
      await finishNativeWidgetAction(tester, fixture.host.disable);
      await _tap(
        tester,
        find.byKey(const ValueKey('confirm-create-agent-connection')),
      );
      expect(fixture.host.grants, isEmpty);
      expect(
        find.byKey(const ValueKey('agent-created-credential')),
        findsNothing,
      );
      expect(
        find.textContaining('Could not create this connection.'),
        findsOneWidget,
      );
      expect(find.textContaining('StateError'), findsNothing);
      await _show(tester, find.byKey(const ValueKey('edit-agent-connection')));
      await _capture(tester, 'agent-connections-stale-review-refused');
    },
  );
}
