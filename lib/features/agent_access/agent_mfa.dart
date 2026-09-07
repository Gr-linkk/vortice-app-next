import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Account-bound MFA calls. A delayed response must never replace another user's
/// session. The shared SDK's challengeAndVerify saves its response immediately,
/// so perform the network requests first and install a verified session only
/// after rechecking the active account.
class AgentMfa {
  AgentMfa(this.client, this.actorId, {this.transport});
  final SupabaseClient client;
  final String actorId;
  final http.Client? transport;
  static const _base = 'https://hkjpojobdbbtjkhaudki.supabase.co/auth/v1';
  static const _name = 'Vortice agent access';

  bool get verified {
    try {
      return client.auth.currentUser?.id == actorId &&
          client.auth.mfa.getAuthenticatorAssuranceLevel().currentLevel ==
              AuthenticatorAssuranceLevels.aal2;
    } catch (_) {
      return false;
    }
  }

  void _checkAccount() {
    if (client.auth.currentUser?.id != actorId) {
      throw StateError('Account changed');
    }
  }

  Future<Map<String, dynamic>> _request(
    String path,
    String method, [
    Map<String, dynamic>? body,
  ]) async {
    _checkAccount();
    final connection = transport ?? http.Client();
    try {
      final request = http.Request(method, Uri.parse('$_base$path'))
        ..followRedirects = false
        ..headers.addAll({
          'apikey': client.auth.headers['apikey'] ?? '',
          'Authorization': 'Bearer ${client.auth.currentSession!.accessToken}',
          'Content-Type': 'application/json',
        });
      if (body != null) request.body = jsonEncode(body);
      final response = await connection
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 20));
      _checkAccount();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('Verification request failed');
      }
      return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    } finally {
      if (transport == null) connection.close();
    }
  }

  Future<Map<String, dynamic>> prepare() async {
    final user = await _request('/user', 'GET');
    final factors = (user['factors'] as List?) ?? [];
    final existing = factors.where(
      (f) => f['factor_type'] == 'totp' && f['status'] == 'verified',
    );
    if (existing.isNotEmpty) return {'id': existing.first['id']};
    // Only discard abandoned, unverified enrollments owned by this exact flow.
    for (final factor in factors.where(
      (f) => f['status'] == 'unverified' && f['friendly_name'] == _name,
    )) {
      await _request(
        '/factors/${Uri.encodeComponent(factor['id'] as String)}',
        'DELETE',
      );
    }
    final enrolled = await _request('/factors', 'POST', {
      'factor_type': 'totp',
      'friendly_name': _name,
      'issuer': 'Vortice Next',
    });
    return {
      'id': enrolled['id'],
      'secret': (enrolled['totp'] as Map)['secret'],
    };
  }

  Future<void> verify(String factor, String code) async {
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      throw StateError('Enter six digits');
    }
    final path = '/factors/${Uri.encodeComponent(factor)}';
    final challenge = await _request('$path/challenge', 'POST', {});
    final response = await _request('$path/verify', 'POST', {
      'challenge_id': challenge['id'],
      'code': code,
    });
    final session = Session.fromJson(response);
    if (session == null || session.user.id != actorId || session.isExpired) {
      throw StateError('Invalid verified session');
    }
    _checkAccount();
    // The public installation method has no network wait: after our validation
    // it synchronously installs the session and emits the persistence event.
    await client.auth.setInitialSession(jsonEncode(session.toJson()));
  }
}
