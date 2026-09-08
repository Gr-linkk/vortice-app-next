import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vortice_app/features/parts/parts_readiness_repository.dart';

Map<String, dynamic> _session(String actor) {
  final payload = base64Url
      .encode(
        utf8.encode(
          jsonEncode({
            'sub': actor,
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
    'refresh_token': 'fixture',
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
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'concurrent saves cannot replace an in-flight operation and input is frozen',
    () async {
      final gate = Completer<void>();
      final requests = <Map<String, dynamic>>[];
      final client = SupabaseClient(
        'https://example.invalid',
        'fixture',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          requests.add(
            Map<String, dynamic>.from(jsonDecode(request.body) as Map),
          );
          await gate.future;
          return http.Response(
            '{}',
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      await client.auth.recoverSession(jsonEncode(_session('manager-a')));
      final repository = SupabasePartsReadinessRepository(client, 'manager-a');
      final input = <String, dynamic>{'quantity': 1};
      final first = repository.change('job-a', 'reserve', input);
      input['quantity'] = 9;
      await expectLater(
        repository.change('job-a', 'reserve', {'quantity': 2}),
        throwsStateError,
      );
      gate.complete();
      await first;
      expect(requests, hasLength(1));
      expect((requests.single['p_data'] as Map)['quantity'], 1);
      await client.dispose();
    },
  );
  test(
    'lost receipt acknowledgement survives repository restart and reuses exact operation',
    () async {
      final requests = <Map<String, dynamic>>[];
      final client = SupabaseClient(
        'https://example.invalid',
        'fixture',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          requests.add(
            Map<String, dynamic>.from(jsonDecode(request.body) as Map),
          );
          if (requests.length == 1) {
            throw const SocketException('lost acknowledgement');
          }
          return http.Response(
            '{}',
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      await client.auth.recoverSession(jsonEncode(_session('manager-a')));
      final first = SupabasePartsReadinessRepository(client, 'manager-a');
      await expectLater(
        first.change('job-a', 'receive', {'quantity': 1}),
        throwsA(isA<SocketException>()),
      );
      expect(await first.pending(), isNotNull);
      final restarted = SupabasePartsReadinessRepository(client, 'manager-a');
      await restarted.retry();
      expect(requests, hasLength(2));
      expect(requests[1], requests[0]);
      expect(await restarted.pending(), isNull);
      await client.dispose();
    },
  );
  test(
    'account switch cannot replay another company pending operation',
    () async {
      var calls = 0;
      final client = SupabaseClient(
        'https://example.invalid',
        'fixture',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          calls++;
          throw const SocketException('offline');
        }),
      );
      await client.auth.recoverSession(jsonEncode(_session('manager-a')));
      final old = SupabasePartsReadinessRepository(client, 'manager-a');
      await expectLater(
        old.change('job-a', 'reserve', {'quantity': 1}),
        throwsA(isA<SocketException>()),
      );
      await client.auth.recoverSession(jsonEncode(_session('manager-b')));
      await expectLater(old.retry(), throwsStateError);
      expect(
        await SupabasePartsReadinessRepository(client, 'manager-b').pending(),
        isNull,
      );
      expect(calls, 1);
      await client.dispose();
    },
  );
  test(
    'SQL rejection clears pending input but gateway failure retains replay identity',
    () async {
      var databaseError = true;
      final client = SupabaseClient(
        'https://example.invalid',
        'fixture',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'message': databaseError ? 'Not enough stock' : 'Gateway timeout',
              'code': databaseError ? 'P0001' : '504',
            }),
            databaseError ? 400 : 504,
            request: request,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      await client.auth.recoverSession(jsonEncode(_session('manager-a')));
      final repository = SupabasePartsReadinessRepository(client, 'manager-a');
      await expectLater(
        repository.change('job-a', 'reserve', {'quantity': 2}),
        throwsA(isA<PostgrestException>()),
      );
      expect(await repository.pending(), isNull);
      databaseError = false;
      await expectLater(
        repository.change('job-a', 'reserve', {'quantity': 1}),
        throwsA(isA<PostgrestException>()),
      );
      expect(await repository.pending(), isNotNull);
      await client.dispose();
    },
  );
}
