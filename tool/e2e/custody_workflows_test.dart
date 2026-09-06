import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/features/assurance/assurance_screen.dart';
import 'package:vortice_app/features/assurance/assurance_form.dart';
import 'package:vortice_app/features/assurance/assurance_repository.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'E2E-010 actual native screens and hosted persistence',
    (tester) async {
      await tester.runAsync(() async {
        HttpOverrides.global = null;
        // Connected test host; stored preferences are deliberately disposable.
        // ignore: invalid_use_of_visible_for_testing_member
        SharedPreferences.setMockInitialValues({});
        final config =
            jsonDecode(
                  File(
                    Platform.environment['VORTICE_E2E_CONFIG']!,
                  ).readAsStringSync(),
                )
                as Map;
        if (config['SUPABASE_URL'] !=
            'https://hkjpojobdbbtjkhaudki.supabase.co') {
          throw StateError('Wrong target');
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
        final repo = SupabaseAssuranceRepository(supabase);
        final asset = const Uuid().v4();
        final manifest = <String, dynamic>{
          'asset': asset,
          'marker': 'E2E-010',
          'objects': <String>[],
        };
        void record() {
          File(
            'outputs/NOW-010-custody-live-manifest.json',
          ).writeAsStringSync(jsonEncode(manifest));
          File(
            'outputs/NOW-010-custody-live-$asset.json',
          ).writeAsStringSync(jsonEncode(manifest));
        }

        record();
        Future<void> login(String email) async {
          await supabase.auth.signInWithPassword(
            email: email,
            password: passwords[email] as String,
          );
        }

        await login('paradise@vortice.dev');
        final workspace = await supabase.rpc('maintenance_workspace') as Map;
        await supabase.rpc(
          'save_maintenance_setup',
          params: {
            'p_operation': const Uuid().v4(),
            'p_kind': 'asset',
            'p_id': asset,
            'p_revision': 0,
            'p_data': {
              'name': 'E2E-010 Custody inspection crane',
              'location': 'E2E-010 Initial dock',
              'asset_type_id': (workspace['asset_types'] as List).first['id'],
            },
          },
        );
        final container = ProviderContainer(
          overrides: [
            inspectionPhotoPickerProvider.overrideWithValue(
              () async => XFile('tool/e2e/fixtures/evidence.png'),
            ),
          ],
        );
        final router = GoRouter(
          initialLocation: '/assurance/assets/$asset',
          routes: [
            GoRoute(
              path: '/assurance',
              builder: (_, __) => const AssuranceScreen(),
            ),
            GoRoute(
              path: '/assurance/assets/:id',
              builder: (_, state) =>
                  AssuranceScreen(asset: state.pathParameters['id']!),
            ),
          ],
        );
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp.router(
              routerConfig: router,
              theme: AppTheme.darkNavyTheme,
              locale: const Locale('en'),
              supportedLocales: const [Locale('en'), Locale('es')],
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
            ),
          ),
        );
        Future<void> waitFor(Finder finder) async {
          for (var n = 0; n < 150; n++) {
            await tester.pump(const Duration(milliseconds: 40));
            if (finder.evaluate().isNotEmpty) return;
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          throw StateError('Visible control not found: $finder');
        }

        Future<void> tap(Finder finder) async {
          if (finder.evaluate().isEmpty &&
              find.byType(Scrollable).evaluate().isNotEmpty) {
            await tester.scrollUntilVisible(
              finder,
              200,
              scrollable: find.byType(Scrollable).first,
              maxScrolls: 25,
            );
          }
          await waitFor(finder);
          await tester.ensureVisible(finder.last);
          await tester.pump();
          await tester.tap(finder.last);
          for (var n = 0; n < 8; n++) {
            await tester.pump(const Duration(milliseconds: 100));
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
        }

        Future<void> settle() async {
          for (var n = 0; n < 15; n++) {
            await tester.pump(const Duration(milliseconds: 100));
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
        }

        Future<void> field(String key, String value) async {
          final finder = find.byKey(ValueKey(key));
          await waitFor(finder);
          await tester.ensureVisible(finder);
          await tester.enterText(finder, value);
          await tester.pump();
        }

        Future<void> refresh() async {
          container.invalidate(assuranceContextProvider);
          container.invalidate(inspectionRegisterProvider);
          await settle();
        }

        Future<void> switchAccount(String email) async {
          await login(email);
          container.invalidate(profileProvider);
          await refresh();
        }

        Future<void> review(String action, String note) async {
          final header = find.text('Evidence & review history');
          if (find.text(action).evaluate().isEmpty) {
            await tap(header);
            await settle();
          }
          await tap(find.text(action));
          await field('note', note);
          await tap(find.widgetWithText(FilledButton, action));
          await settle();
        }

        await waitFor(find.text('Record transfer'));
        await tap(find.text('Record transfer'));
        await field('site', 'E2E-010 North workshop');
        await tap(find.byType(DropdownButtonFormField<String>).first);
        final context = await repo.context(asset);
        final person = (context['people'] as List).first as Map;
        await tap(find.text(person['name'] as String).last);
        await field('reason', 'E2E-010 Move for annual inspection');
        await tap(find.widgetWithText(FilledButton, 'Record transfer'));
        await settle();
        final saved = await repo.context(asset);
        expect((saved['custody'] as Map)['site'], 'E2E-010 North workshop');
        expect((saved['transfers'] as List).length, 1);
        await waitFor(find.text('E2E-010 North workshop'));
        await tap(find.text('Record transfer'));
        await waitFor(find.byKey(const ValueKey('site')));
        expect(
          tester
              .widget<TextFormField>(find.byKey(const ValueKey('site')))
              .controller!
              .text,
          'E2E-010 North workshop',
        );
        Navigator.of(tester.element(find.byType(AssuranceForm))).pop();
        await settle();
        stdout.writeln(
          'PASS connected transfer submit, persisted journal and reopened form',
        );
        await tap(find.text('Add inspection'));
        await field('title', 'E2E-010 Annual lifting certificate');
        await tap(find.widgetWithText(FilledButton, 'Add inspection'));
        await settle();
        var items = await repo.inspections(asset);
        expect(items.length, 1);
        manifest['inspection'] = items.single['id'];
        record();
        stdout.writeln('PASS connected inspection registration and reopen');
        await switchAccount('client_mechanic@vortice.dev');
        expect(find.text('Record transfer'), findsNothing);
        Future<void> submit(String result, String expiry) async {
          await tap(find.text('Submit renewal'));
          await field('inspected_on', '2026-09-01');
          await field('expires_on', expiry);
          await field('procedure_notes', 'E2E-010 Load test procedure v1');
          await field('result_notes', result);
          await tap(find.text('Add evidence photo'));
          await settle();
          await tap(find.widgetWithText(FilledButton, 'Submit renewal'));
          await settle();
          items = await repo.inspections(asset);
          final pending = items.single['pending'] as Map;
          (manifest['objects'] as List).add(pending['evidence_path']);
          record();
          expect(pending['result_notes'], result);
          final bytes = await supabase.storage
              .from('inspection-evidence')
              .download(pending['evidence_path'] as String);
          expect(
            bytes,
            File('tool/e2e/fixtures/evidence.png').readAsBytesSync(),
          );
        }

        await submit('E2E-010 Initial load test passed', '2026-09-05');
        expect(find.text('Approve renewal'), findsNothing);
        stdout.writeln(
          'PASS connected mechanic submits evidence; saved object bytes match',
        );
        await switchAccount('paradise@vortice.dev');
        await review('Return renewal', 'E2E-010 Include test pressure');
        items = await repo.inspections(asset);
        expect((items.single['versions'] as List).single['status'], 'returned');
        await switchAccount('client_mechanic@vortice.dev');
        await submit(
          'E2E-010 Corrected result: pressure 100 psi passed',
          '2026-09-05',
        );
        await switchAccount('paradise@vortice.dev');
        await review(
          'Approve renewal',
          'E2E-010 Pressure and evidence reviewed',
        );
        items = await repo.inspections(asset);
        expect(items.single['approved'], isNotNull);
        expect((items.single['versions'] as List).length, 2);
        expect(inspectionState(items.single, DateTime(2026, 9, 6)), 'expired');
        stdout.writeln(
          'PASS connected return, resubmit and manager approval; old versions retained',
        );
        await submit('E2E-010 Renewed full inspection passed', '2027-09-01');
        items = await repo.inspections(asset);
        expect((items.single['approved'] as Map)['expires_on'], '2026-09-05');
        await review('Approve renewal', 'E2E-010 Renewal evidence verified');
        items = await repo.inspections(asset);
        expect((items.single['approved'] as Map)['expires_on'], '2027-09-01');
        expect((items.single['versions'] as List).length, 3);
        stdout.writeln(
          'PASS connected second renewal updates current certificate only after approval',
        );
        await switchAccount('operator@vortice.dev');
        expect(find.text('Record transfer'), findsNothing);
        expect(find.text('Submit renewal'), findsNothing);
        expect((await repo.inspections(asset)).length, 1);
        stdout.writeln(
          'PASS connected operator reads records with no mutation controls',
        );
        final owningClient = supabase.auth.currentUser!.id;
        await switchAccount('client@vortice.dev');
        expect((await repo.inspections(asset)), isEmpty);
        await expectLater(
          repo.context(asset),
          throwsA(isA<PostgrestException>()),
        );
        for (final path in manifest['objects'] as List) {
          await expectLater(
            supabase.storage
                .from('inspection-evidence')
                .download(path as String),
            throwsA(isA<StorageException>()),
          );
        }
        expect(supabase.auth.currentUser!.id, isNot(owningClient));
        stdout.writeln(
          'PASS connected other-company record, direct-link and evidence denial',
        );
        manifest['passed'] = true;
        record();
        await tester.pumpWidget(const SizedBox());
        container.dispose();
        router.dispose();
        await supabase.auth.signOut();
        await Supabase.instance.dispose();
      });
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
