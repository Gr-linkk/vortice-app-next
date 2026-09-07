import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:uuid/uuid.dart';
import 'package:vortice_app/core/account_storage.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';

/// Retains the operation identity until the server acknowledges the transaction.
/// Reopening a form and retrying identical input also resolves a lost response.
class RetryableRpc {
  RetryableRpc({
    required this.account,
    required this.currentAccount,
    required this.send,
  });
  final String account;
  final String? Function() currentAccount;
  final Future<dynamic> Function(String, Map<String, dynamic>) send;
  static final Map<String, Future<dynamic>> _running = {};

  Future<dynamic> call(
    String method,
    Map<String, dynamic> input, {
    bool captureTime = false,
  }) {
    final normalized = _canonical(input);
    final digest = sha256.convert(utf8.encode(jsonEncode(normalized)));
    final key = accountStorageKey(account, 'rpc:$method:$digest');
    return _running.putIfAbsent(
      key,
      () =>
          _call(
            key,
            method,
            Map<String, dynamic>.from(normalized as Map),
            captureTime,
          ).whenComplete(() {
            _running.remove(key);
          }),
    );
  }

  void _check() {
    if (currentAccount() != account) throw const AccountChangedException();
  }

  Future<dynamic> _call(
    String key,
    String method,
    Map<String, dynamic> input,
    bool captureTime,
  ) async {
    _check();
    final prefs = await SharedPreferences.getInstance();
    _check();
    final stored = prefs.getString(key);
    final params = stored == null
        ? {
            ...input,
            'p_operation': const Uuid().v4(),
            if (captureTime)
              'p_captured_at': DateTime.now().toUtc().toIso8601String(),
          }
        : Map<String, dynamic>.from(jsonDecode(stored) as Map);
    if (stored == null && !await prefs.setString(key, jsonEncode(params))) {
      throw StateError('Could not preserve the save for retry.');
    }
    _check();
    final result = await send(method, params);
    _check();
    await prefs.remove(key);
    return result;
  }
}

dynamic _canonical(dynamic value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: _canonical(value[key])};
  }
  if (value is List) return value.map(_canonical).toList();
  return value;
}

RetryableRpc authenticatedRetryableRpc() {
  final session = supabase.auth.currentSession;
  if (session == null) throw const AccountChangedException();
  // Capture authorization before I/O; an account switch cannot send this work
  // under the next user's credentials. Tokens are never stored in the receipt.
  final token = session.accessToken;
  return RetryableRpc(
    account: session.user.id,
    currentAccount: () => supabase.auth.currentUser?.id,
    send: (method, params) async {
      final response = await http
          .post(
            Uri.parse('${AppConstants.supabaseUrl}/rest/v1/rpc/$method'),
            headers: {
              'apikey': AppConstants.supabaseAnonKey,
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(params),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode >= 500 || response.statusCode == 429) {
        throw http.ClientException(
          'Service temporarily unavailable. Retry the same save.',
        );
      }
      if (response.statusCode >= 400) {
        Map<String, dynamic> error = {};
        try {
          error = jsonDecode(response.body) as Map<String, dynamic>;
        } catch (_) {}
        throw PostgrestException(
          message: error['message']?.toString() ?? 'Save rejected',
          code: error['code']?.toString(),
        );
      }
      return response.body.isEmpty ? null : jsonDecode(response.body);
    },
  );
}
