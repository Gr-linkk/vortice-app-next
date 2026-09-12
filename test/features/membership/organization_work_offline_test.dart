import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqlite3/open.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vortice_app/db/database.dart';
import 'package:vortice_app/features/membership/organization_work_provider.dart';
import 'package:vortice_app/sync/field_work_queue.dart';
import 'package:vortice_app/core/account_storage.dart';

void main() {
  if (Platform.isLinux) {
    open.overrideFor(
      OperatingSystem.linux,
      () => DynamicLibrary.open('libsqlite3.so.0'),
    );
  }
  test(
    'production provider repository captures offline and sends report only after photo acknowledgement',
    () async {
      var online = false;
      final uploaded = <String>[];
      final rpcCalls = <Map<String, dynamic>>[];
      final client = SupabaseClient(
        'https://example.invalid',
        'fixture',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          expect(request.url.path, '/rest/v1/rpc/change_organization_work');
          expect(uploaded, hasLength(1));
          rpcCalls.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response(
            '{}',
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final expiry =
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
          1000;
      final token = base64Url
          .encode(utf8.encode(jsonEncode({'sub': 'actor', 'exp': expiry})))
          .replaceAll('=', '');
      await client.auth.recoverSession(
        jsonEncode({
          'access_token': 'e30.$token.signature',
          'refresh_token': 'fixture',
          'token_type': 'bearer',
          'expires_in': 3600,
          'user': {
            'id': 'actor',
            'aud': 'authenticated',
            'app_metadata': {},
            'user_metadata': {},
            'created_at': '2026-09-12T00:00:00Z',
          },
        }),
      );
      final db = AppDatabase.forAccount(
        'actor',
        executor: NativeDatabase.memory(),
      );
      final queue = FieldWorkQueue(
        db,
        account: 'actor',
        currentAccount: () => client.auth.currentUser?.id,
        send: (row) async {
          if (!online) throw const SocketException('Offline');
          uploaded.add(row.payload['path'] as String);
        },
      );
      final repository = OrganizationWorkRepository(
        client: client,
        queue: queue,
      );
      try {
        final bytes = Uint8List.fromList([3, 1, 4, 1, 5]);
        final path = await repository.uploadEvidence('work', 'actor', bytes);
        expect(path, startsWith('work/actor/'));
        await queue.flush();
        expect(await repository.evidence(path), bytes);
        final data = {
          'diagnosis': 'Seal failed',
          'repair': 'Replaced seal',
          'evidence_paths': [path],
        };
        await expectLater(
          repository.changeOperation('work', 3, 'operation', 'submit', data),
          throwsStateError,
        );
        expect(rpcCalls, isEmpty);
        online = true;
        await repository.changeOperation(
          'work',
          3,
          'operation',
          'submit',
          data,
        );
        expect(rpcCalls.single['p_operation'], 'operation');
        expect(rpcCalls.single['p_revision'], 3);
        expect(rpcCalls.single['p_data'], data);
        await expectLater(
          repository.uploadEvidence('work', 'other', bytes),
          throwsA(isA<AccountChangedException>()),
        );
      } finally {
        queue.close();
        await db.close();
        await client.dispose();
      }
    },
  );
}
