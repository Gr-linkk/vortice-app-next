import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/agent_access/agent_access_repository.dart';
import 'package:vortice_app/features/agent_access/agent_access_screen.dart';
import '../fleet/fleet_test_support.dart';

class FixtureAgentRepository implements AgentAccessRepository {
  @override
  bool ownerVerified = true;
  @override
  Future<Map<String, dynamic>> prepareOwnerVerification() async => {
    'id': 'factor',
    'secret': 'TEST_SETUP_SECRET',
  };
  @override
  Future<void> verifyOwner(String factor, String code) async {
    if (code != '123456') throw StateError('Invalid code');
    ownerVerified = true;
    data['owner_verification_required'] = false;
  }

  Map<String, dynamic> data = {
    'fleets': [
      {'id': 'fleet-a', 'name': 'Harbour Marine'},
    ],
    'connections': <Map<String, dynamic>>[],
    'activity': <Map<String, dynamic>>[],
  };
  Object? error;
  Completer<Map<String, dynamic>>? pending;
  final creations = <Map<String, dynamic>>[];
  final revocations = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> load() async {
    if (error != null) throw error!;
    return data;
  }

  @override
  Future<Map<String, dynamic>> create(
    String fleet,
    String name,
    bool drafts,
  ) async {
    creations.add({'fleet': fleet, 'name': name, 'drafts': drafts});
    if (error != null) throw error!;
    if (pending != null) return pending!.future;
    data['connections'] = [
      {
        'id': 'connection-a',
        'label': name,
        'client_id': fleet,
        'allow_drafts': drafts,
        'expires_at': '2099-09-14T12:00:00Z',
        'revoked_at': null,
      },
    ];
    return {'token': 'vna_test_key_shown_once'};
  }

  @override
  Future<void> revoke({
    String? connection,
    String? fleet,
    bool all = false,
  }) async {
    revocations.add({'connection': connection, 'fleet': fleet, 'all': all});
    if (error != null) throw error!;
    for (final c in data['connections'] as List) {
      c['revoked_at'] = '2026-09-07T12:00:00Z';
    }
  }
}

Widget app(
  FixtureAgentRepository repository, {
  String account = 'a',
  bool spanish = false,
  bool dark = false,
  double scale = 1,
}) => RepaintBoundary(
  key: const Key('fleet-capture'),
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
    locale: Locale(spanish ? 'es' : 'en'),
    supportedLocales: const [Locale('en'), Locale('es')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: AgentAccessPanel(
      key: ValueKey(account),
      repository: repository,
      isOwner: true,
    ),
  ),
);

Future<void> prepare(WidgetTester tester) async {
  await tester.tap(find.byType(DropdownButtonFormField<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Harbour Marine').last);
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), 'Maintenance helper');
  await tester.ensureVisible(find.byType(CheckboxListTile));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(CheckboxListTile));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await loadFleetScreenshotFonts();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  testWidgets('owner must verify before creating a key', (tester) async {
    final repository = FixtureAgentRepository()..ownerVerified = false;
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();
    expect(find.text('Verify owner access'), findsOneWidget);
    await tester.tap(find.text('Verify with authenticator'));
    await tester.pumpAndSettle();
    expect(find.text('TEST_SETUP_SECRET'), findsOneWidget);
    final code = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == 'Six-digit code',
    );
    await tester.enterText(code, '000000');
    await tester.ensureVisible(find.text('Verify code'));
    await tester.tap(find.text('Verify code'));
    await tester.pumpAndSettle();
    expect(repository.ownerVerified, false);
    await tester.enterText(code, '123456');
    await tester.ensureVisible(find.text('Verify code'));
    await tester.tap(find.text('Verify code'));
    await tester.pumpAndSettle();
    expect(repository.ownerVerified, true);
    expect(find.text('TEST_SETUP_SECRET'), findsNothing);
    expect(find.text('Verify owner access'), findsNothing);
  });
  testWidgets(
    'live factor removal offers verification despite an old MFA session',
    (tester) async {
      final repository = FixtureAgentRepository();
      repository.data['owner_verification_required'] = true;
      await tester.pumpWidget(app(repository));
      await tester.pumpAndSettle();
      expect(find.text('Verify owner access'), findsOneWidget);
      await tester.tap(find.text('Verify with authenticator'));
      await tester.pumpAndSettle();
      final code = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Six-digit code',
      );
      await tester.enterText(code, '123456');
      await tester.ensureVisible(find.text('Verify code'));
      await tester.tap(find.text('Verify code'));
      await tester.pumpAndSettle();
      expect(find.text('Verify owner access'), findsNothing);
      expect(repository.data['owner_verification_required'], false);
    },
  );
  testWidgets(
    'explicit consent, read-only default, one-time key and disconnect',
    (tester) async {
      final repository = FixtureAgentRepository();
      await tester.pumpWidget(app(repository));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Create connection key'),
            )
            .onPressed,
        isNull,
      );
      await prepare(tester);
      await tester.ensureVisible(find.text('Create connection key'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create connection key'));
      await tester.pumpAndSettle();
      expect(repository.creations.single, {
        'fleet': 'fleet-a',
        'name': 'Maintenance helper',
        'drafts': false,
      });
      await tester.drag(find.byType(ListView), const Offset(0, 1200));
      await tester.pumpAndSettle();
      expect(find.text('vna_test_key_shown_once'), findsOneWidget);
      await tester.tap(find.text('I saved the key'));
      await tester.pumpAndSettle();
      expect(find.text('vna_test_key_shown_once'), findsNothing);
      await tester.scrollUntilVisible(
        find.byTooltip('Disconnect'),
        350,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byTooltip('Disconnect'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Disconnect'));
      await tester.pumpAndSettle();
      expect(repository.revocations.single['connection'], 'connection-a');
      expect(find.textContaining('Disconnected'), findsWidgets);
    },
  );

  testWidgets(
    'account switch discards pending secret result and private state',
    (tester) async {
      final old = FixtureAgentRepository()..pending = Completer();
      await tester.pumpWidget(app(old));
      await tester.pumpAndSettle();
      await prepare(tester);
      await tester.ensureVisible(find.text('Create connection key'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create connection key'));
      await tester.pump();
      await tester.pumpWidget(app(FixtureAgentRepository(), account: 'b'));
      old.pending!.complete({'token': 'old_account_secret'});
      await tester.pumpAndSettle();
      expect(find.text('old_account_secret'), findsNothing);
      expect(find.text('Maintenance helper'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('load failure is recoverable without showing raw errors', (
    tester,
  ) async {
    final repository = FixtureAgentRepository()
      ..error = StateError('sensitive server detail');
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not load agent access'), findsOneWidget);
    expect(find.textContaining('sensitive server detail'), findsNothing);
    repository.error = null;
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not load agent access'), findsNothing);
    await prepare(tester);
    repository.error = StateError('connection uncertain');
    await tester.ensureVisible(find.text('Create connection key'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create connection key'));
    await tester.pumpAndSettle();
    expect(find.text('Maintenance helper'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, 1000));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Connection could not be confirmed'),
      findsOneWidget,
    );
  });

  for (final spanish in [false, true]) {
    for (final dark in [false, true]) {
      testWidgets('native layout at 320px and 200% text ($spanish/$dark)', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repository = FixtureAgentRepository();
        repository.data['connections'] = [
          {
            'id': 'c',
            'client_id': 'fleet-a',
            'label':
                'Long maintenance assistant connection name for the entire company',
            'allow_drafts': true,
            'expires_at': '2099-09-14T12:00:00Z',
            'revoked_at': null,
          },
        ];
        await tester.pumpWidget(
          app(repository, spanish: spanish, dark: dark, scale: 2),
        );
        await tester.pumpAndSettle();
        await captureFleet(
          tester,
          'agent-access-${spanish ? "es" : "en"}-${dark ? "dark" : "light"}',
        );
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(ListView), const Offset(0, -800));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await captureFleet(
          tester,
          'agent-access-scrolled-${spanish ? "es" : "en"}-${dark ? "dark" : "light"}',
        );
        await tester.drag(find.byType(ListView), const Offset(0, -800));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
