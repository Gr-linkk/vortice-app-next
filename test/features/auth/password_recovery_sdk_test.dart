import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vortice_app/features/auth/password_recovery.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'SDK recovery exchanges PKCE, updates password, and rejects used links',
    () async {
      SharedPreferences.setMockInitialValues({});
      final requests = <http.Request>[];
      var used = false;
      const account = 'a0110000-0000-4000-8000-000000000001';
      final user = {
        'id': account,
        'aud': 'authenticated',
        'role': 'authenticated',
        'email': 'recovery@example.invalid',
        'created_at': '2026-01-01T00:00:00Z',
        'app_metadata': <String, dynamic>{},
        'user_metadata': <String, dynamic>{},
      };
      String segment(Object value) =>
          base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
      final jwt =
          '${segment({'alg': 'HS256'})}.${segment({'sub': account, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.synthetic';
      await Supabase.initialize(
        url: 'https://recovery.invalid',
        anonKey: 'synthetic',
        authOptions: const FlutterAuthClientOptions(
          autoRefreshToken: false,
          detectSessionInUri: false,
        ),
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('/recover')) {
            return http.Response('{}', 200);
          }
          if (request.url.path.endsWith('/token')) {
            expect(request.url.queryParameters['grant_type'], 'pkce');
            final body = jsonDecode(request.body) as Map;
            expect(body['code_verifier'], isNotEmpty);
            if (used) {
              return http.Response('{"msg":"Recovery code already used"}', 400);
            }
            used = true;
            return http.Response(
              jsonEncode({
                'access_token': jwt,
                'refresh_token': 'synthetic-refresh',
                'token_type': 'bearer',
                'expires_in': 3600,
                'user': user,
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/user')) {
            return http.Response(jsonEncode(user), 200);
          }
          if (request.url.path.endsWith('/logout')) {
            return http.Response('', 204);
          }
          throw StateError('Unexpected recovery request ${request.url.path}');
        }),
      );
      final controller = PasswordRecoveryController();
      try {
        await controller.request(' recovery@example.invalid ');
        final request = requests.single;
        expect(request.url.queryParameters['redirect_to'], recoveryRedirect);
        expect((jsonDecode(request.body) as Map)['code_challenge'], isNotEmpty);
        await controller.handleCallback(
          Uri.parse('$recoveryRedirect?code=synthetic-code'),
        );
        expect(controller.phase, RecoveryPhase.ready);
        expect(
          (await SharedPreferences.getInstance()).getString(
            'password_recovery_account',
          ),
          account,
        );
        await controller.updatePassword('a different password');
        final update = requests.singleWhere((r) => r.method == 'PUT');
        expect(
          (jsonDecode(update.body) as Map)['password'],
          'a different password',
        );
        expect(Supabase.instance.client.auth.currentSession, isNull);
        expect(
          (await SharedPreferences.getInstance()).getString(
            'password_recovery_account',
          ),
          isNull,
        );
        // A fresh request creates a verifier; a previously consumed server code
        // must never make the password form ready again.
        await controller.request('recovery@example.invalid');
        await controller.handleCallback(
          Uri.parse('$recoveryRedirect?code=used-code'),
        );
        expect(controller.phase, RecoveryPhase.failed);
        await expectLater(
          controller.updatePassword('another password'),
          throwsA(isA<AuthException>()),
        );
      } finally {
        controller.dispose();
        await Supabase.instance.dispose();
      }
    },
  );
}
