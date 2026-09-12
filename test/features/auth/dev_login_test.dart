import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/auth/dev_login_accounts.dart';
import 'package:vortice_app/features/auth/dev_login_credentials.dart';
import 'package:vortice_app/features/auth/dev_login_switch.dart';
import 'package:vortice_app/features/auth/login_screen.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import '../fleet/fleet_test_support.dart'
    show captureFleet, loadFleetScreenshotFonts;

class RecordingAuthController extends AuthController {
  final calls = <String>[];
  String? selectedPassword;
  bool failSignOut = false, failSignIn = false;
  VoidCallback? afterSignOut;
  Completer<void>? pendingSignOut;
  Completer<void>? pendingSignIn;

  @override
  Future<void> signOut() async {
    calls.add('signOut');
    state = const AsyncLoading();
    if (pendingSignOut != null) await pendingSignOut!.future;
    state = failSignOut
        ? AsyncError(StateError('Fixture sign-out failure'), StackTrace.current)
        : const AsyncData(null);
    if (!failSignOut) afterSignOut?.call();
  }

  @override
  Future<void> signIn(String email, String password) async {
    calls.add('signIn:$email');
    selectedPassword = password;
    state = const AsyncLoading();
    if (pendingSignIn != null) await pendingSignIn!.future;
    state = failSignIn
        ? AsyncError(StateError('Fixture sign-in failure'), StackTrace.current)
        : const AsyncData(null);
  }
}

Session signedIn(String email) => Session(
  accessToken: 'fixture',
  tokenType: 'bearer',
  user: User(
    id: 'fixture-user',
    email: email,
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    createdAt: '2026-09-12T00:00:00Z',
  ),
);

void main() {
  const nextUrl = 'https://hkjpojobdbbtjkhaudki.supabase.co';
  const credentials = {
    'owner@vortice.dev': 'fixture-owner',
    'tech@vortice.dev': 'fixture-tech',
  };
  setUpAll(loadFleetScreenshotFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('release and wrong-backend builds reject developer credentials', () {
    for (final debug in [false, true]) {
      for (final url in [nextUrl, 'https://example.invalid']) {
        final allowed = debug && url == nextUrl;
        expect(
          isDevLoginEnvironment(debugBuild: debug, supabaseUrl: url),
          allowed,
        );
        expect(
          parseDevLoginPasswords(
            '{"owner@vortice.dev":"fixture"}',
            debugBuild: debug,
            supabaseUrl: url,
          ).isNotEmpty,
          allowed,
        );
      }
    }
    expect(
      parseDevLoginPasswords(
        'malformed',
        debugBuild: true,
        supabaseUrl: nextUrl,
      ),
      isEmpty,
    );
    expect(
      parseDevLoginPasswords(
        '{"a@outside.test":"fixture","bad@x@vortice.dev":"fixture","owner@vortice.dev":null}',
        debugBuild: true,
        supabaseUrl: nextUrl,
      ),
      isEmpty,
    );
  });

  test('new configured accounts appear without inventing a working role', () {
    final accounts = devLoginAccounts([
      ...credentials.keys,
      'new_profile@vortice.dev',
    ]);
    final extra = accounts.singleWhere(
      (account) => account.email == 'new_profile@vortice.dev',
    );
    expect(extra.en, 'Additional test profile');
    expect(extra.role, isEmpty);
    expect(
      accounts.where((account) => account.email == 'owner@vortice.dev'),
      hasLength(1),
    );
  });

  Future<void> pumpApp(
    WidgetTester tester,
    RecordingAuthController auth, {
    bool environment = true,
    Map<String, String> passwords = credentials,
    Session? session,
    ValueNotifier<Widget>? route,
    String locale = 'en',
    double scale = 1,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith((ref) => auth),
          sessionProvider.overrideWithValue(session),
          devLoginEnvironmentProvider.overrideWithValue(environment),
          devLoginPasswordsProvider.overrideWithValue(passwords),
        ],
        child: RepaintBoundary(
          key: const Key('fleet-capture'),
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            locale: Locale(locale),
            debugShowCheckedModeBanner: false,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: route == null
                ? const LoginScreen()
                : ValueListenableBuilder<Widget>(
                    valueListenable: route,
                    builder: (_, screen, _) => screen,
                  ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openPicker(WidgetTester tester, {bool more = false}) async {
    final button = find.byKey(
      ValueKey(more ? 'dev-switch-account' : 'dev-sign-in'),
    );
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  Future<void> selectAccount(WidgetTester tester, String email) async {
    final row = find.byKey(ValueKey('dev-account:$email'));
    await tester.ensureVisible(row);
    await tester.tap(row);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'both visible entry and logo shortcut stay hidden outside the guarded environment',
    (tester) async {
      await pumpApp(tester, RecordingAuthController(), environment: false);
      expect(find.byKey(const ValueKey('dev-sign-in')), findsNothing);
      await tester.tap(find.byIcon(Icons.engineering));
      await tester.pumpAndSettle();
      expect(find.byType(DevLoginAccountSheet), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpApp(tester, RecordingAuthController(), passwords: {});
      expect(find.byKey(const ValueKey('dev-sign-in')), findsNothing);
    },
  );

  testWidgets(
    'selection directly signs in using configured credentials without showing a password',
    (tester) async {
      final auth = RecordingAuthController();
      await pumpApp(tester, auth);
      await openPicker(tester);
      await selectAccount(tester, 'tech@vortice.dev');
      await tester.pumpAndSettle();
      expect(auth.calls, ['signIn:tech@vortice.dev']);
      expect(auth.selectedPassword, 'fixture-tech');
      expect(
        tester
            .widgetList<TextFormField>(find.byType(TextFormField))
            .last
            .controller!
            .text,
        isEmpty,
      );
    },
  );

  testWidgets(
    'unconfigured known account is disabled and never authenticates',
    (tester) async {
      final auth = RecordingAuthController();
      await pumpApp(
        tester,
        auth,
        passwords: {'tech@vortice.dev': 'fixture-tech'},
      );
      await openPicker(tester);
      final row = tester.widget<ListTile>(
        find.byKey(const ValueKey('dev-account:owner@vortice.dev')),
      );
      expect(row.enabled, isFalse);
      expect(row.onTap, isNull);
      expect(
        find.textContaining('Sign-in is not configured in this build.'),
        findsWidgets,
      );
      expect(auth.calls, isEmpty);
    },
  );

  testWidgets(
    'switch signs out before sign-in and survives the originating route being disposed',
    (tester) async {
      final auth = RecordingAuthController()..pendingSignIn = Completer<void>();
      final route = ValueNotifier<Widget>(
        const Scaffold(body: DevAccountSwitchEntry()),
      );
      addTearDown(route.dispose);
      auth.afterSignOut = () => route.value = const LoginScreen();
      await pumpApp(
        tester,
        auth,
        session: signedIn('owner@vortice.dev'),
        route: route,
      );
      await openPicker(tester, more: true);
      expect(
        tester
            .widget<ListTile>(
              find.byKey(const ValueKey('dev-account:owner@vortice.dev')),
            )
            .enabled,
        isFalse,
      );
      final row = find.byKey(const ValueKey('dev-account:tech@vortice.dev'));
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(DevAccountSwitchEntry), findsNothing);
      auth.pendingSignIn!.complete();
      await tester.pumpAndSettle();
      expect(auth.calls, ['signOut', 'signIn:tech@vortice.dev']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed sign-out stops switching and shows an error on the current screen',
    (tester) async {
      final auth = RecordingAuthController()..failSignOut = true;
      final route = ValueNotifier<Widget>(
        const Scaffold(body: DevAccountSwitchEntry()),
      );
      addTearDown(route.dispose);
      await pumpApp(
        tester,
        auth,
        session: signedIn('owner@vortice.dev'),
        route: route,
      );
      await openPicker(tester, more: true);
      await selectAccount(tester, 'tech@vortice.dev');
      await tester.pumpAndSettle();
      expect(auth.calls, ['signOut']);
      expect(
        find.text('Could not switch to tech@vortice.dev.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'target sign-in failure survives navigation and is visible on Login',
    (tester) async {
      final auth = RecordingAuthController()..failSignIn = true;
      final route = ValueNotifier<Widget>(
        const Scaffold(body: DevAccountSwitchEntry()),
      );
      addTearDown(route.dispose);
      auth.afterSignOut = () => route.value = const LoginScreen();
      await pumpApp(
        tester,
        auth,
        session: signedIn('owner@vortice.dev'),
        route: route,
      );
      await openPicker(tester, more: true);
      await selectAccount(tester, 'tech@vortice.dev');
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(
        find.text('Could not switch to tech@vortice.dev.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  test('duplicate switch requests do not overlap', () async {
    final auth = RecordingAuthController()..pendingSignOut = Completer<void>();
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith((ref) => auth),
        sessionProvider.overrideWithValue(signedIn('owner@vortice.dev')),
        devLoginEnvironmentProvider.overrideWithValue(true),
        devLoginPasswordsProvider.overrideWithValue(credentials),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(devAccountSwitchProvider.notifier);
    final first = controller.switchTo('tech@vortice.dev');
    await controller.switchTo('tech@vortice.dev');
    expect(auth.calls, ['signOut']);
    auth.pendingSignOut!.complete();
    await first;
    expect(auth.calls, ['signOut', 'signIn:tech@vortice.dev']);
  });

  testWidgets('Spanish picker supports narrow large text and extra profiles', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpApp(
      tester,
      RecordingAuthController(),
      locale: 'es',
      scale: 2,
      passwords: {...credentials, 'new_profile@vortice.dev': 'fixture-extra'},
    );
    await openPicker(tester);
    await captureFleet(tester, 'dev-account-picker-es-large');
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('dev-account:new_profile@vortice.dev')),
      250,
      scrollable: find.descendant(
        of: find.byType(DevLoginAccountSheet),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('Otro perfil de prueba'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'modern demos lead, old profiles expand, and current company is explicit',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: DevLoginAccountSheet(
                configuredEmails: const {
                  'demo_fleet_owner@vortice.dev',
                  'demo_fleet_mechanic@vortice.dev',
                  'owner@vortice.dev',
                },
                currentEmail: 'demo_fleet_owner@vortice.dev',
                currentCompany: 'Next Demo Fleet',
                currentRoles: const ['company_owner'],
                onSelected: (email) => selected = email,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Next Demo Fleet'), findsOneWidget);
      expect(find.text('Company Owner'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('dev-account:owner@vortice.dev')),
        findsNothing,
      );
      final other = find.text('Other test accounts');
      await tester.scrollUntilVisible(other, 180);
      await tester.pumpAndSettle();
      await tester.tap(other);
      await tester.pumpAndSettle();
      final old = find.byKey(const ValueKey('dev-account:owner@vortice.dev'));
      await tester.scrollUntilVisible(old, 180);
      await tester.pumpAndSettle();
      await tester.tap(old);
      expect(selected, 'owner@vortice.dev');
      expect(tester.takeException(), isNull);
    },
  );
}
