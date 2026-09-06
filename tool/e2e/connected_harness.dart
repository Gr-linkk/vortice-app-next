import 'dart:convert';
import 'dart:ffi' show DynamicLibrary;
import 'dart:io';
import 'dart:ui' as ui;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/open.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vortice_app/app.dart';
import 'package:vortice_app/core/router.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/db/database.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';

Future<void> loadAuditFonts() async {
  final root = Platform.environment['VORTICE_FLUTTER_FONTS'];
  if (root == null) {
    throw StateError('VORTICE_FLUTTER_FONTS required for visual audit');
  }
  for (final family in ['Roboto', 'monospace', 'MaterialIcons']) {
    final font = FontLoader(family);
    for (final name
        in family != 'MaterialIcons'
            ? ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']
            : ['MaterialIcons-Regular.otf']) {
      font.addFont(
        Future.value(
          ByteData.sublistView(await File('$root/$name').readAsBytes()),
        ),
      );
    }
    await font.load();
  }
}

// Use the production app's router, locale and localization configuration. The
// only host adjustment is an explicit Android font instead of test-only Ahem.
class AuditApp extends ConsumerWidget {
  const AuditApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = const VorticeApp().build(context, ref) as MaterialApp;
    final theme = AppTheme.darkNavyTheme;
    return MaterialApp.router(
      routerConfig: app.routerConfig,
      locale: app.locale,
      supportedLocales: app.supportedLocales,
      localizationsDelegates: app.localizationsDelegates,
      debugShowCheckedModeBanner: false,
      theme: theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: 'Roboto'),
        primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: 'Roboto'),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: theme.elevatedButtonTheme.style?.copyWith(
            textStyle: WidgetStatePropertyAll(
              theme.elevatedButtonTheme.style?.textStyle
                  ?.resolve({})
                  ?.copyWith(fontFamily: 'Roboto'),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: theme.textButtonTheme.style?.copyWith(
            textStyle: WidgetStatePropertyAll(
              theme.textButtonTheme.style?.textStyle
                  ?.resolve({})
                  ?.copyWith(fontFamily: 'Roboto'),
            ),
          ),
        ),
        chipTheme: theme.chipTheme.copyWith(
          labelStyle: theme.chipTheme.labelStyle?.copyWith(
            fontFamily: 'Roboto',
          ),
        ),
        appBarTheme: theme.appBarTheme.copyWith(
          titleTextStyle: theme.appBarTheme.titleTextStyle?.copyWith(
            fontFamily: 'Roboto',
          ),
        ),
      ),
    );
  }
}

class ConnectedHarness {
  ConnectedHarness(this.tester, {this.report = 'journeys'});
  final WidgetTester tester;
  final String report;
  late Map passwords;
  final _databases = <String, AppDatabase>{};
  AppDatabase get db => container.read(databaseProvider);
  late ProviderContainer container;
  final boundary = GlobalKey();
  final steps = <Map<String, dynamic>>[];
  final issues = <String>[];
  Future<void> start() async {
    HttpOverrides.global = null;
    // Connected test host; stored preferences are deliberately disposable.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    if (Platform.isLinux) {
      open.overrideFor(
        OperatingSystem.linux,
        () => DynamicLibrary.open('libsqlite3.so.0'),
      );
    }
    await loadAuditFonts();
    final config =
        jsonDecode(
              File(
                Platform.environment['VORTICE_E2E_CONFIG']!,
              ).readAsStringSync(),
            )
            as Map;
    if (config['SUPABASE_URL'] != 'https://hkjpojobdbbtjkhaudki.supabase.co') {
      throw StateError('Wrong target');
    }
    passwords = jsonDecode(config['DEV_LOGIN_PASSWORDS'] as String) as Map;
    await Supabase.initialize(
      url: config['SUPABASE_URL'] as String,
      anonKey: config['SUPABASE_ANON_KEY'] as String,
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
      ),
    );
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWith((ref) {
          final account = ref.watch(sessionProvider)?.user.id ?? 'signed_out';
          return _databases.putIfAbsent(
            account,
            () => AppDatabase.forAccount(
              account,
              executor: NativeDatabase.memory(),
            ),
          );
        }),
      ],
    );
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: RepaintBoundary(key: boundary, child: const AuditApp()),
      ),
    );
    await settle();
  }

  Future<void> settle([int minimum = 7]) async {
    for (var n = 0; n < 70; n++) {
      await tester.pump(const Duration(milliseconds: 80));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      if (n >= minimum &&
          find.byType(CircularProgressIndicator).evaluate().isEmpty &&
          find.byType(LinearProgressIndicator).evaluate().isEmpty) {
        return;
      }
    }
  }

  Future<void> login(String email) async {
    await supabase.auth.signInWithPassword(
      email: email,
      password: passwords[email] as String,
    );
    await settle();
    final profile = await container.read(profileProvider.future);
    expect(profile?.email, email);
  }

  Future<void> go(String route) async {
    container.read(routerProvider).go(route);
    await settle();
  }

  Future<void> reveal(Finder target) async {
    await settle(3);
    if (target.evaluate().isEmpty &&
        find.byType(Scrollable).evaluate().isNotEmpty) {
      // A preceding action can leave a lazily built control above the viewport.
      // Return to the start before searching downward through this scroll view.
      final scroll = tester.state<ScrollableState>(
        find.byType(Scrollable).last,
      );
      scroll.position.jumpTo(scroll.position.minScrollExtent);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.scrollUntilVisible(
        target,
        240,
        scrollable: find.byType(Scrollable).last,
        maxScrolls: 30,
      );
    }
    expect(target, findsWidgets);
    await tester.ensureVisible(target.last);
    await tester.pump(const Duration(milliseconds: 250));
  }

  Future<void> tap(Finder target) async {
    await reveal(target);
    if (target.last.hitTestable().evaluate().isEmpty) {
      // Let a preceding success snackbar expire before tapping behind it.
      await Future<void>.delayed(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 5));
      await settle(2);
      await tester.ensureVisible(target.last);
      await tester.pump();
    }
    expect(
      target.last.hitTestable(),
      findsOneWidget,
      reason: 'Control must actually receive the tap',
    );
    await tester.tap(target.last);
    await settle();
  }

  Finder field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  );
  Finder hint(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.hintText == label,
  );
  Future<void> fill(Finder target, String text) async {
    await reveal(target);
    await tester.enterText(target.last, text);
    await tester.pump();
  }

  Future<void> select(String label, String option) async {
    final input = find.byWidgetPredicate(
      (w) => w is InputDecorator && w.decoration.labelText == label,
    );
    await tap(input);
    await tap(find.text(option));
  }

  void check(bool passed, String detail) {
    if (!passed) {
      issues.add(detail);
      stdout.writeln('FINDING $detail');
    } else {
      stdout.writeln('PASS $detail');
    }
  }

  Future<void> step(String label, Future<void> Function() action) async {
    try {
      await action();
      steps.add({'step': label, 'completed': true});
      stdout.writeln('STEP PASS $label');
    } catch (error, stack) {
      issues.add('$label: $error');
      steps.add({
        'step': label,
        'error': error.toString(),
        'stack': stack.toString(),
      });
      stdout.writeln('STEP FAILED $label: $error');
      await screenshot('$report-failure-${steps.length}');
    }
    File('outputs/NOW-010-$report.json').writeAsStringSync(
      const JsonEncoder.withIndent(
        '  ',
      ).convert({'steps': steps, 'issues': issues}),
    );
  }

  Future<void> screenshot(String name) async {
    final render =
        boundary.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (render == null) return;
    final image = await render.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory('outputs/screenshots/audit010').createSync(recursive: true);
    File(
      'outputs/screenshots/audit010/$name.png',
    ).writeAsBytesSync(data!.buffer.asUint8List());
    image.dispose();
  }

  Future<void> close() async {
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    for (final database in _databases.values) {
      await database.close();
    }
    await supabase.auth.signOut(scope: SignOutScope.local);
    await Supabase.instance.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}
