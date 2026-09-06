import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/db/database.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'field_work_queue.dart';

final fieldWorkQueueProvider = Provider<FieldWorkQueue?>((ref) {
  final account = ref.watch(sessionProvider)?.user.id;
  if (account == null) return null;
  late final FieldWorkQueue queue;
  queue = FieldWorkQueue(
    ref.watch(databaseProvider),
    account: account,
    currentAccount: () => supabase.auth.currentUser?.id,
    send: (operation) async {
      queue.checkAccount();
      // Capture this account's token before starting I/O. A later sign-in must
      // never send the previous account's data with the new account's session.
      final token = supabase.auth.currentSession!.accessToken;
      final headers = {
        'apikey': AppConstants.supabaseAnonKey,
        'Authorization': 'Bearer $token',
      };
      final data = operation.payload;
      late http.Response response;
      if (operation.kind == 'upload') {
        final bucket = data['bucket'] as String;
        if (!['maintenance-evidence', 'operator-evidence'].contains(bucket)) {
          throw const FormatException('Unsupported evidence bucket');
        }
        final path = data['path'] as String;
        if (path.contains('..') || path.startsWith('/')) {
          throw const FormatException('Invalid evidence path');
        }
        final url = Uri.parse(
          '${AppConstants.supabaseUrl}/storage/v1/object/$bucket/$path',
        );
        final bytes = base64Decode(data['bytes'] as String);
        response = await http
            .post(
              url,
              headers: {
                ...headers,
                'Content-Type': data['contentType'] as String,
                'x-upsert': 'false',
              },
              body: bytes,
            )
            .timeout(const Duration(seconds: 25));
        // An accepted checklist closes its upload policy. Storage can then
        // return 403 before checking whether a retried object already exists.
        // Authenticated, byte-identical readback proves that upload succeeded.
        if ([400, 403, 409].contains(response.statusCode)) {
          final existing = await http
              .get(
                Uri.parse(
                  '${AppConstants.supabaseUrl}/storage/v1/object/authenticated/$bucket/$path',
                ),
                headers: headers,
              )
              .timeout(const Duration(seconds: 25));
          if (existing.statusCode == 200 &&
              base64Encode(existing.bodyBytes) == data['bytes']) {
            return;
          }
          throw StateError(
            'Evidence already exists with different content or is inaccessible.',
          );
        }
      } else {
        if (![
          'apply_maintenance_field_action',
          'submit_operations_checklist',
        ].contains(operation.kind)) {
          throw const FormatException('Unsupported field operation');
        }
        response = await http
            .post(
              Uri.parse(
                '${AppConstants.supabaseUrl}/rest/v1/rpc/${operation.kind}',
              ),
              headers: {...headers, 'Content-Type': 'application/json'},
              body: jsonEncode(data),
            )
            .timeout(const Duration(seconds: 15));
      }
      if (response.statusCode >= 500 || response.statusCode == 429) {
        throw http.ClientException('Service temporarily unavailable');
      }
      if (response.statusCode >= 400) {
        Map<String, dynamic> failure = {};
        try {
          failure = jsonDecode(response.body) as Map<String, dynamic>;
        } catch (_) {}
        throw PostgrestException(
          message:
              failure['message']?.toString() ??
              'Upload rejected (${response.statusCode})',
          code: failure['code']?.toString(),
        );
      }
    },
  );
  ref.onDispose(queue.close);
  return queue;
});

final fieldOperationsProvider = StreamProvider<List<FieldOperation>>(
  (ref) => ref.watch(fieldWorkQueueProvider)?.watch() ?? Stream.value([]),
);
