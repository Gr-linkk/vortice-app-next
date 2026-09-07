import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vortice_app/features/agent_access/agent_mfa.dart';

Map<String, dynamic> session(String actor, {bool mfa = false}) {
  final payload = base64Url
      .encode(
        utf8.encode(
          jsonEncode({
            'sub': actor,
            'aal': mfa ? 'aal2' : 'aal1',
            'amr': [],
            'exp':
                DateTime.now()
                    .add(const Duration(hours: 1))
                    .millisecondsSinceEpoch ~/
                1000,
          }),
        ),
      )
      .replaceAll('=', '');
  return {
    'access_token': 'e30.$payload.signature',
    'refresh_token': 'fixture-refresh-$actor',
    'token_type': 'bearer',
    'expires_in': 3600,
    'user': {
      'id': actor,
      'app_metadata': {},
      'user_metadata': {},
      'aud': 'authenticated',
      'created_at': '2026-09-07T12:00:00Z',
    },
  };
}

void main() {
  late SupabaseClient client;
  setUp(() async {
    client = SupabaseClient(
      'https://hkjpojobdbbtjkhaudki.supabase.co',
      'public-fixture',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    await client.auth.recoverSession(jsonEncode(session('owner-a')));
  });
  tearDown(() => client.dispose());

  test('existing verified factor is reused without enrollment', () async {
    final paths = <String>[];
    final mfa = AgentMfa(
      client,
      'owner-a',
      transport: MockClient((request) async {
        paths.add(request.url.path);
        expect(request.followRedirects, false);
        expect(request.headers['apikey'], 'public-fixture');
        return http.Response(
          jsonEncode({
            'factors': [
              {'id': 'existing', 'factor_type': 'totp', 'status': 'verified'},
            ],
          }),
          200,
        );
      }),
    );
    expect(await mfa.prepare(), {'id': 'existing'});
    expect(paths, ['/auth/v1/user']);
  });

  test('setup removes only this flow’s abandoned unverified factor', () async {
    final requests = <http.Request>[];
    final mfa = AgentMfa(
      client,
      'owner-a',
      transport: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/user')) {
          return http.Response(
            jsonEncode({
              'factors': [
                {
                  'id': 'abandoned',
                  'status': 'unverified',
                  'friendly_name': 'Vortice agent access',
                },
                {
                  'id': 'unrelated',
                  'status': 'unverified',
                  'friendly_name': 'Another flow',
                },
              ],
            }),
            200,
          );
        }
        if (request.method == 'DELETE') {
          return http.Response('{"id":"abandoned"}', 200);
        }
        return http.Response(
          '{"id":"new","totp":{"secret":"SETUP-ONLY"}}',
          200,
        );
      }),
    );
    expect(await mfa.prepare(), {'id': 'new', 'secret': 'SETUP-ONLY'});
    expect(
      requests.where((r) => r.method == 'DELETE').single.url.path,
      '/auth/v1/factors/abandoned',
    );
    expect(jsonDecode(requests.last.body)['factor_type'], 'totp');
  });

  test(
    'verification installs a fresh session for the same account only',
    () async {
      final mfa = AgentMfa(
        client,
        'owner-a',
        transport: MockClient((request) async {
          if (request.url.path.endsWith('/challenge')) {
            return http.Response('{"id":"challenge"}', 200);
          }
          expect(jsonDecode(request.body), {
            'challenge_id': 'challenge',
            'code': '123456',
          });
          return http.Response(jsonEncode(session('owner-a', mfa: true)), 200);
        }),
      );
      expect(mfa.verified, false);
      await mfa.verify('factor', '123456');
      expect(mfa.verified, true);
    },
  );

  test(
    'late verification cannot restore an account after switching users',
    () async {
      final verifyStarted = Completer<void>();
      final delayed = Completer<http.Response>();
      final mfa = AgentMfa(
        client,
        'owner-a',
        transport: MockClient((request) async {
          if (request.url.path.endsWith('/challenge')) {
            return http.Response('{"id":"challenge"}', 200);
          }
          verifyStarted.complete();
          return delayed.future;
        }),
      );
      final result = expectLater(
        mfa.verify('factor', '123456'),
        throwsStateError,
      );
      await verifyStarted.future;
      await client.auth.recoverSession(jsonEncode(session('owner-b')));
      delayed.complete(
        http.Response(jsonEncode(session('owner-a', mfa: true)), 200),
      );
      await result;
      expect(client.auth.currentUser!.id, 'owner-b');
      expect(mfa.verified, false);
    },
  );

  test(
    'invalid code or rejected network response cannot authorize a connection',
    () async {
      var requests = 0;
      final mfa = AgentMfa(
        client,
        'owner-a',
        transport: MockClient((_) async {
          requests++;
          return http.Response('private backend message', 400);
        }),
      );
      await expectLater(mfa.verify('factor', 'bad'), throwsStateError);
      expect(requests, 0);
      await expectLater(mfa.verify('factor', '123456'), throwsStateError);
      expect(mfa.verified, false);
    },
  );
}
