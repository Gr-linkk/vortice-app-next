import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/auth/dev_login_credentials.dart';
import 'package:vortice_app/features/auth/login_screen.dart';
import 'package:vortice_app/l10n/app_localizations.dart';

class RecordingAuthController extends AuthController {
  String? email, password;
  @override
  Future<void> signIn(String email, String password) async {
    this.email = email;
    this.password = password;
  }
}

void main() {
  const nextUrl = 'https://hkjpojobdbbtjkhaudki.supabase.co';
  const fixture = '{"owner@vortice.dev":"fixture-password"}';

  test('dev passwords are restricted to debug builds on Next', () {
    expect(
      parseDevLoginPasswords(
        fixture,
        debugBuild: true,
        supabaseUrl: nextUrl,
      )['owner@vortice.dev'],
      'fixture-password',
    );
    expect(
      parseDevLoginPasswords(fixture, debugBuild: false, supabaseUrl: nextUrl),
      isEmpty,
    );
    expect(
      parseDevLoginPasswords(
        fixture,
        debugBuild: true,
        supabaseUrl: 'https://example.invalid',
      ),
      isEmpty,
    );
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
        '{"owner@vortice.dev":null}',
        debugBuild: true,
        supabaseUrl: nextUrl,
      ),
      isEmpty,
    );
  });

  testWidgets('logo persona selection fills credentials and submits them', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final auth = RecordingAuthController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith((ref) => auth),
          devLoginPasswordsProvider.overrideWithValue({
            'owner@vortice.dev': 'fixture-owner-password',
            'tech@vortice.dev': 'fixture-tech-password',
          }),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: LoginScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final account in ['owner', 'tech']) {
      await tester.ensureVisible(find.byIcon(Icons.engineering));
      await tester.tap(find.byIcon(Icons.engineering));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('$account@vortice.dev'));
      await tester.tap(find.text('$account@vortice.dev'));
      await tester.pumpAndSettle();
      final fields = tester
          .widgetList<TextFormField>(find.byType(TextFormField))
          .toList();
      expect(fields[0].controller!.text, '$account@vortice.dev');
      expect(fields[1].controller!.text, 'fixture-$account-password');
      await tester.ensureVisible(find.byType(ElevatedButton));
      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();
      expect(auth.email, '$account@vortice.dev');
      expect(auth.password, 'fixture-$account-password');
    }
    expect(tester.takeException(), isNull);
  });
}
