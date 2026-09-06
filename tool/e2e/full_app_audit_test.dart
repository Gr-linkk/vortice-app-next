// Explicit connected audit: flutter test tool/e2e/full_app_audit_test.dart.
// Requires VORTICE_E2E_CONFIG pointing to the existing isolated Next config.
import 'dart:convert';
import 'dart:ffi' show DynamicLibrary;
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/open.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vortice_app/core/app_navigation.dart';
import 'package:vortice_app/core/router.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/db/database.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'connected_harness.dart' show loadAuditFonts, AuditApp;

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
        // Connected test host; stored preferences are deliberately disposable.
        // ignore: invalid_use_of_visible_for_testing_member
        SharedPreferences.setMockInitialValues({});
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
        final db = AppDatabase(NativeDatabase.memory());
        final container = ProviderContainer(
          overrides: [databaseProvider.overrideWithValue(db)],
        );
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const AuditApp(),
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
          for (var n = 0; n < 35; n++) {
            await tester.pump(const Duration(milliseconds: 100));
            await Future<void>.delayed(const Duration(milliseconds: 100));
            if (n > 7 &&
                find.byType(CircularProgressIndicator).evaluate().isEmpty) {
              break;
            }
          }
        }

        void save() {
          File('outputs/NOW-010-routes.json').writeAsStringSync(
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
                      r'exception|does not exist|permission denied|error|failed|could not|try again',
                      caseSensitive: false,
                    ).hasMatch(e),
                  )
                  .toList();
              results.add({
                'role': role.name,
                'account': email,
                'requested': route,
                'actual': router.routeInformationProvider.value.uri.path,
                'errors': errors,
                'frameworkErrors': List<String>.from(caught),
                'loading': find
                    .byType(CircularProgressIndicator)
                    .evaluate()
                    .length,
                'labels': labels.take(60).toList(),
              });
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
          await db.close();
          await supabase.auth.signOut(scope: SignOutScope.local);
          await Supabase.instance.dispose();
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        }
        expect(results, isNotEmpty);
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
          'AUDIT ${results.length} routes saved to outputs/NOW-010-routes.json',
        );
      });
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}
