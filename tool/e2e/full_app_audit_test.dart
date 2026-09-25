// Explicit connected audit: flutter test tool/e2e/full_app_audit_test.dart.
// Requires VORTICE_E2E_CONFIG pointing to the existing isolated Next config.
import 'dart:convert';
import 'dart:ffi' show DynamicLibrary;
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/open.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vortice_app/core/app_navigation.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/router.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/db/database.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'connected_harness.dart' show loadAuditFonts, AuditApp;
import 'audit_output.dart';

class _AuditFailures extends ProviderObserver {
  final failures = <String>[];

  @override
  void providerDidFail(
    ProviderBase<Object?> provider,
    Object error,
    StackTrace stackTrace,
    ProviderContainer container,
  ) {
    failures.add('${provider.name ?? provider.runtimeType}: $error');
    stdout.writeln(
      'PROVIDER FAILURE ${provider.name ?? provider.runtimeType}: $error\n$stackTrace',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (Platform.isLinux) {
    open.overrideFor(
      OperatingSystem.linux,
      () => DynamicLibrary.open('libsqlite3.so.0'),
    );
  }
  testWidgets(
    'connected whole-app role and route audit',
    (tester) async {
      await tester.runAsync(() async {
        HttpOverrides.global = null;
        final locale = Platform.environment['VORTICE_AUDIT_LOCALE'] ?? 'en';
        final textScale = double.tryParse(
          Platform.environment['VORTICE_AUDIT_TEXT_SCALE'] ?? '1',
        );
        if (!['en', 'es', 'fr'].contains(locale) ||
            textScale == null ||
            !textScale.isFinite ||
            textScale <= 0) {
          throw StateError(
            'Audit requires locale en/es/fr and a positive text scale',
          );
        }
        // Connected test host; stored preferences are deliberately disposable.
        // ignore: invalid_use_of_visible_for_testing_member
        SharedPreferences.setMockInitialValues({
          AppConstants.prefLocale: locale,
        });
        await loadAuditFonts();
        final config =
            jsonDecode(
                  File(
                    Platform.environment['VORTICE_E2E_CONFIG']!,
                  ).readAsStringSync(),
                )
                as Map;
        if (config['SUPABASE_URL'] !=
            'https://hkjpojobdbbtjkhaudki.supabase.co') {
          throw StateError('Wrong backend');
        }
        final passwords =
            jsonDecode(config['DEV_LOGIN_PASSWORDS'] as String) as Map;
        await Supabase.initialize(
          url: config['SUPABASE_URL'] as String,
          anonKey: config['SUPABASE_ANON_KEY'] as String,
          authOptions: const FlutterAuthClientOptions(
            autoRefreshToken: false,
            detectSessionInUri: false,
          ),
        );
        final databases = <String, AppDatabase>{};
        final observer = _AuditFailures();
        final container = ProviderContainer(
          observers: [observer],
          overrides: [
            databaseProvider.overrideWith((ref) {
              final account =
                  ref.watch(sessionProvider)?.user.id ?? 'signed_out';
              return databases.putIfAbsent(
                account,
                () => AppDatabase.forAccount(
                  account,
                  executor: NativeDatabase.memory(),
                ),
              );
            }),
          ],
        );
        final appearance =
            Platform.environment['VORTICE_AUDIT_APPEARANCE'] ?? 'system';
        final output = Directory(
          auditOutputPath('route-audit/$appearance/$locale-${textScale}x'),
        )..createSync(recursive: true);
        final boundary = GlobalKey();
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = textScale;
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: RepaintBoundary(key: boundary, child: const AuditApp()),
          ),
        );
        final router = container.read(routerProvider);
        final results = <Map<String, dynamic>>[];
        final caught = <String>[];
        final originalError = FlutterError.onError;
        FlutterError.onError = (details) {
          caught.add(details.exceptionAsString());
        };
        Future<void> settle() async {
          // Cold live data can exceed 3.5 s; keep a bounded 10 s wait and record timing.
          for (var n = 0; n < 100; n++) {
            await tester.pump(const Duration(milliseconds: 100));
            await Future<void>.delayed(const Duration(milliseconds: 100));
            if (n > 7 &&
                find.byType(CircularProgressIndicator).evaluate().isEmpty) {
              break;
            }
          }
        }

        void save() {
          File('${output.path}/routes.json').writeAsStringSync(
            const JsonEncoder.withIndent('  ').convert(results),
          );
        }

        try {
          for (final email in [
            'owner@vortice.dev',
            'tech@vortice.dev',
            'paradise@vortice.dev',
            'client_mechanic@vortice.dev',
            'operator@vortice.dev',
            'client@vortice.dev',
          ]) {
            await supabase.auth.signInWithPassword(
              email: email,
              password: passwords[email] as String,
            );
            await settle();
            final profile = await container.read(profileProvider.future);
            if (profile == null) throw StateError('Profile absent');
            final role = profile.role;
            final prefix = roleRoutePrefix(role);
            final assets = await supabase.from('assets').select('id').limit(1);
            final routes = <String>{
              ...primaryDestinations(
                role,
                operationalChecklistsEnabled: true,
              ).map((e) => e.route),
              ...toolDestinations(role).map((e) => e.route),
              '/notifications',
              if (prefix == '/owner' || prefix == '/employee')
                '$prefix/work-orders/create',
              if (prefix == '/client' &&
                  (email == 'paradise@vortice.dev' ||
                      email == 'client@vortice.dev'))
                '/client/service-requests/new',
            };
            if (role.name == 'client' || role.name == 'clientAdmin') {
              routes.add('/checklist-assignments');
            }
            if (assets.isNotEmpty) {
              final id = assets.first['id'];
              routes.addAll([
                '$prefix/assets/$id',
                '/history/assets/$id',
                '/assurance/assets/$id',
                '/fleet/assets/$id',
                '$prefix/assets/$id/checklist-history',
                '/telemetry/vessel/$id',
                '/telemetry/assets/$id/history',
              ]);
              if (prefix == '/owner') {
                routes.addAll([
                  '/owner/assets/$id/engines',
                  '/owner/assets/$id/service-intervals',
                ]);
              }
              if (email == 'paradise@vortice.dev') {
                routes.addAll([
                  '/maintenance/assets/$id',
                  '/client/assets/$id/pre-trip',
                  '/client/assets/$id/flags',
                ]);
              }
            }
            for (final route in routes) {
              caught.clear();
              final failureStart = observer.failures.length;
              final routeTimer = Stopwatch()..start();
              router.go(route);
              await settle();
              final labels = tester
                  .widgetList<Text>(find.byType(Text))
                  .map((e) => e.data ?? '')
                  .where((e) => e.isNotEmpty)
                  .toList();
              final errors = labels
                  .where(
                    (e) => RegExp(
                      r'exception|does not exist|permission denied|error|failed|could not|try again|excepción|permiso denegado|no se pudo|reintentar',
                      caseSensitive: false,
                    ).hasMatch(e),
                  )
                  .toList();
              results.add({
                'locale': Localizations.localeOf(
                  tester.element(find.byType(Scaffold).first),
                ).languageCode,
                'textScale':
                    MediaQuery.textScalerOf(
                      tester.element(find.byType(Scaffold).first),
                    ).scale(10) /
                    10,
                'role': role.name,
                'account': email,
                'requested': route,
                'settleMilliseconds': routeTimer.elapsedMilliseconds,
                'actual': router.routeInformationProvider.value.uri.path,
                'errors': errors,
                'frameworkErrors': List<String>.from(caught),
                'providerErrors': observer.failures.skip(failureStart).toList(),
                'loading': find
                    .byType(CircularProgressIndicator)
                    .evaluate()
                    .length,
                'labels': labels.take(60).toList(),
              });
              final picture = await tester
                  .renderObject<RenderRepaintBoundary>(find.byKey(boundary))
                  .toImage(pixelRatio: 1);
              final bytes = await picture.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final screenshot =
                  '${results.length.toString().padLeft(3, '0')}-${role.name}-${route.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}.png';
              await File(
                '${output.path}/$screenshot',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              picture.dispose();
              results.last['screenshot'] = screenshot;
              results.last['appearance'] = appearance;
              save();
              stdout.writeln(
                'ROUTE ${role.name} $route -> ${errors.length} error texts, ${caught.length} framework errors',
              );
            }
          }
        } finally {
          FlutterError.onError = originalError;
          await tester.pumpWidget(const SizedBox());
          container.dispose();
          for (final db in databases.values) {
            await db.close();
          }
          await supabase.auth.signOut(scope: SignOutScope.local);
          await Supabase.instance.dispose();
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
        }
        expect(results, isNotEmpty);
        expect(
          observer.failures,
          isEmpty,
          reason: 'No hidden provider failures',
        );
        expect(
          results.every(
            (row) =>
                row['locale'] == locale &&
                ((row['textScale'] as double) - textScale).abs() < 0.000001,
          ),
          isTrue,
          reason: 'Every screen must use the requested locale and text scale',
        );
        expect(
          results.where((row) => (row['frameworkErrors'] as List).isNotEmpty),
          isEmpty,
        );
        expect(results.where((row) => row['loading'] != 0), isEmpty);
        expect(
          results.where((row) => (row['errors'] as List).isNotEmpty),
          isEmpty,
        );
        stdout.writeln(
          'AUDIT ${results.length} routes saved to ${output.path}/routes.json',
        );
      });
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}
