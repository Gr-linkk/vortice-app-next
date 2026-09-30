import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/local_sync.dart';
import 'package:maintenance_local/model.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';
import 'package:maintenance_local/ui/common.dart';
import 'package:maintenance_local/ui/devices_page.dart';
import 'package:qr_flutter/qr_flutter.dart';

// Selectively adapted from setup_rendered_test.dart in candidate
// e6956ae8d3274142cc09fa23c6ced05eda4bac00 (Garrett Lindquist). This test uses
// real maintenance records and an ephemeral loopback office TLS server, with
// injected addresses rather than physical network interfaces.
const _boundaryKey = Key('maintenance-setup-devices-boundary');

Future<void> _settle(WidgetTester tester) async {
  // Start a newly pushed route before advancing its transition clock.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pump(const Duration(milliseconds: 250));
  expect(
    tester.takeException(),
    isNull,
    reason:
        'The connection steps must render without framework or overflow errors.',
  );
}

Future<void> _show(WidgetTester tester, Finder finder) async {
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 250));
  expect(
    finder.hitTestable(),
    findsOneWidget,
    reason:
        'The normal connection action must remain reachable at this text size.',
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

ThemeData _fieldNotesTheme() => ThemeData(
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
    final loader = FontLoader('Roboto')
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
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'normal office connection steps render at 412x915 ${scale}x text',
      (tester) async {
        tester.view.physicalSize = const Size(412, 915);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        late Directory root;
        late LabStore office;
        late OfficeServer server;
        await tester.runAsync(() async {
          root = await Directory.systemTemp.createTemp(
            'maintenance-setup-render-',
          );
          office = await LabStore.open(
            Directory('${root.path}/office'),
            office: true,
          );
          await office.createCompany(
            'Synthetic North Construction',
            coordinatorName: 'Sam Coordinator',
          );
          final equipment = await office.addEquipment(
            name: 'Synthetic tracked excavator',
            serial: 'SYNTHETIC-EX24',
            meterUnit: 'hours',
          );
          final checklist = await office.publishChecklist(
            title: 'Morning equipment inspection',
            items: [
              {
                'id': 'guard',
                'label': 'Inspect guards and visible leaks',
                'input_type': 'check',
                'required': true,
                'allow_na': false,
              },
            ],
          );
          await office.prepareWork(
            equipmentId: equipment['id'] as String,
            templateId: checklist['id'] as String,
            title: 'Start-of-shift inspection',
          );
          server = await OfficeServer.start(
            office,
            port: 0,
            address: InternetAddress.loopbackIPv4,
          );
        });
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(() async {
            await server.close();
            await office.close();
            await root.delete(recursive: true);
          });
        });
        final suffix = '${scale.toInt()}x';
        var addresses = ['192.168.40.2'];
        var addressFailure = false;
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
        await tester.pumpWidget(
          RepaintBoundary(
            key: _boundaryKey,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: _fieldNotesTheme(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Builder(
                builder: (context) => Scaffold(
                  appBar: AppBar(
                    title: const Text('Vortice · Local Maintenance'),
                  ),
                  body: page([
                    Text(
                      office.catalog!['company'] as String,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const Text(
                      'Synthetic tracked excavator · Start-of-shift inspection',
                    ),
                    FilledButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => DevicesPage(
                            server: server,
                            addressLoader: () async {
                              if (addressFailure) {
                                throw StateError(
                                  'Synthetic address read failure',
                                );
                              }
                              return addresses;
                            },
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.devices),
                      label: const Text('Connect or replace a phone'),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        );
        await _settle(tester);
        await _capture(tester, 'devices-entry-$suffix');
        await _tap(tester, find.text('Connect or replace a phone'));
        expect(find.text('192.168.40.2'), findsOneWidget);
        await _capture(tester, 'devices-address-$suffix');
        await _tap(tester, find.byKey(const ValueKey('create-invitation')));
        await _show(tester, find.byType(QrImageView));
        await _capture(tester, 'devices-invitation-$suffix');
        await _tap(tester, find.text('Copy invitation'));
        await _show(
          tester,
          find.textContaining('Invitation copied on this computer only.'),
        );
        await _capture(tester, 'devices-copy-guidance-$suffix');
        final invitation = jsonDecode(copied!) as Json;
        expect(invitation['companyId'], office.catalog!['companyId']);
        expect(Uri.parse(invitation['url'] as String).host, '192.168.40.2');
        expect(Uri.parse(invitation['url'] as String).port, server.port);
        final token = secret();
        final request = server.authority.request({
          'device': 'synthetic-mechanic-phone',
          'label': 'Synthetic mechanic phone',
          'token': token,
          'invitation': invitation['invitation'],
        });
        expect(request['status'], 'pending');
        await tester.pump(const Duration(seconds: 2));
        await _settle(tester);
        await _show(tester, find.text('Codes match — allow this phone'));
        expect(
          find.text('Compare with phone: ${request['code']}'),
          findsOneWidget,
        );
        await _show(tester, find.text('Synthetic mechanic phone'));
        expect(
          find.text('Codes match — allow this phone').hitTestable(),
          findsOneWidget,
        );
        expect(
          find.text('Compare with phone: ${request['code']}').hitTestable(),
          findsOneWidget,
        );
        await _capture(tester, 'devices-confirm-code-$suffix');
        await _tap(tester, find.text('Codes match — allow this phone'));
        expect(server.authority.phones.single['status'], 'active');
        expect(
          server.authority.authenticate('Bearer $token'),
          'synthetic-mechanic-phone',
        );
        await _show(tester, find.text('Allowed to connect'));
        await _show(tester, find.text('Synthetic mechanic phone'));
        await _capture(tester, 'devices-allowed-$suffix');
        await _tap(tester, find.text('Revoke phone'));
        await _show(tester, find.widgetWithText(FilledButton, 'Revoke phone'));
        await _capture(tester, 'devices-revoke-dialog-$suffix');
        await _tap(tester, find.widgetWithText(FilledButton, 'Revoke phone'));
        expect(server.authority.phones.single['status'], 'revoked');
        expect(
          () => server.authority.authenticate('Bearer $token'),
          throwsStateError,
        );
        await _show(tester, find.text('Revoked — connection blocked'));
        await _capture(tester, 'devices-revoked-$suffix');
        addresses = ['192.168.40.3'];
        await _tap(tester, find.byKey(const ValueKey('refresh-addresses')));
        expect(find.text('Copy invitation'), findsNothing);
        expect(
          find.textContaining('Invitation copied on this computer only.'),
          findsNothing,
        );
        expect(find.text('192.168.40.3'), findsOneWidget);
        await _show(
          tester,
          find.textContaining('The computer address changed.'),
        );
        await _capture(tester, 'devices-address-changed-$suffix');
        addressFailure = true;
        await _tap(tester, find.byKey(const ValueKey('refresh-addresses')));
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('create-invitation')),
              )
              .onPressed,
          isNull,
        );
        await _show(
          tester,
          find.textContaining('Could not check the computer address.'),
        );
        await _capture(tester, 'devices-address-error-$suffix');
        addressFailure = false;
        addresses = [];
        await _tap(tester, find.byKey(const ValueKey('refresh-addresses')));
        await _show(
          tester,
          find.text('Join a local Wi-Fi network to invite a phone.'),
        );
        await _capture(tester, 'devices-no-address-$suffix');
        await tester.pumpWidget(const SizedBox.shrink());
        await _settle(tester);
        final output = Platform.environment['VORTICE_RENDER_OUTPUT'];
        if (output != null && output.isNotEmpty) {
          await tester.runAsync(
            () => File('$output/devices-receipt-$suffix.txt').writeAsString(
              'Actual Flutter DevicesPage renders at 412x915, ${scale}x text with repository Roboto fonts and Field Notes theme.\n'
              'Harness enters through Connect or replace a phone; store contains a real synthetic company, equipment, published checklist and prepared inspection.\n'
              'Office uses ephemeral loopback TLS; addressLoader is injected, no physical interfaces are read. Clipboard is mocked. Confirmation and revocation use the actual office authority.\n'
              'Screens cover address selection, invitation, private clipboard guidance, exact confirmation code, Allowed to connect, revocation, stale invitation clearing, address failure and no local address.\n'
              'No framework/overflow exceptions; ordinary actions are scrollable and reachable at both text scales. Test invitation and phone credentials are synthetic and deleted with the temporary store.\n'
              'Physical Wi-Fi, native app installation and unassisted operator acceptance remain untested. Raster captures require separate visual inspection.\n',
            ),
          );
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
}
