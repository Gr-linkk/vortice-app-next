import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show PostgrestException, AuthException;

String accountStorageKey(String account, String key) =>
    'account:${Uri.encodeComponent(account)}:$key';
String accountDatabaseName(String account) {
  if (!RegExp(r'^[a-zA-Z0-9_-]{1,100}$').hasMatch(account)) {
    throw ArgumentError('Invalid account ID');
  }
  return 'vortice_account_$account';
}

bool isConnectionFailure(Object error) =>
    error is TimeoutException ||
    error is SocketException ||
    error is http.ClientException;

bool isAccessDenial(Object error) =>
    error is AuthException ||
    (error is PostgrestException &&
        ['42501', 'PGRST301', 'PGRST302'].contains(error.code));

// A readiness refresh must prove server contact; cached fallback cannot move
// its last-updated time forward. Ordinary screen reads keep offline fallback.
const _requireFreshReads = #vorticeRequireFreshReads;
Future<T> withFreshAccountReads<T>(Future<T> Function() body) =>
    runZoned(body, zoneValues: {_requireFreshReads: true});

/// Invalidate read permissions without touching drafts, retries or the outbox.
Future<void> invalidateAccountReadCaches(String account) async {
  final prefs = await SharedPreferences.getInstance();
  final epochKey = accountStorageKey(account, 'read_epoch');
  await prefs.setInt(epochKey, (prefs.getInt(epochKey) ?? 0) + 1);
  final prefix = accountStorageKey(account, 'cache:');
  for (final key in prefs.getKeys().where((key) => key.startsWith(prefix))) {
    await prefs.remove(key);
  }
}

class AccountChangedException implements Exception {
  const AccountChangedException();
  @override
  String toString() => 'The signed-in account changed. Reopen this screen.';
}

/// A server denial never falls back to cache; late responses cannot cross users.
class AccountJsonCache {
  const AccountJsonCache(
    this.account,
    this.currentAccount, {
    this.maxAge = const Duration(hours: 24),
    this.now = DateTime.now,
  });
  final String account;
  final String? Function() currentAccount;
  final Duration maxAge;
  final DateTime Function() now;
  void checkAccount() {
    if (currentAccount() != account) throw const AccountChangedException();
  }

  Future<void> save(String key, dynamic data) async {
    checkAccount();
    final prefs = await SharedPreferences.getInstance();
    checkAccount();
    await prefs.setString(
      accountStorageKey(account, 'cache:$key'),
      jsonEncode({
        'value': data,
        'savedAt': now().toUtc().toIso8601String(),
        'epoch': prefs.getInt(accountStorageKey(account, 'read_epoch')) ?? 0,
      }),
    );
  }

  Future<dynamic> readThrough(
    String key,
    Future<dynamic> Function() fetch, {
    Map<String, dynamic> Function(dynamic)? derivedValues,
    String? replaceDerivedPrefix,
  }) async {
    checkAccount();
    final prefs = await SharedPreferences.getInstance();
    final storageKey = accountStorageKey(account, 'cache:$key');
    final epochKey = accountStorageKey(account, 'read_epoch');
    var epoch = prefs.getInt(epochKey) ?? 0;
    final previous = prefs.getString(storageKey);
    try {
      final data = await fetch();
      checkAccount();
      if ((prefs.getInt(epochKey) ?? 0) != epoch) {
        throw const AccountChangedException();
      }
      if (previous != null &&
          key != 'profile' &&
          key != 'current_org' &&
          key != 'organization_context' &&
          !key.startsWith('capabilities:')) {
        dynamic old;
        try {
          old = (jsonDecode(previous) as Map)['value'];
        } catch (_) {}
        final removed =
            old != null && data == null ||
            old is List &&
                data is List &&
                old.whereType<Map>().any(
                  (row) =>
                      row['id'] != null &&
                      !data.whereType<Map>().any(
                        (current) => current['id'] == row['id'],
                      ),
                );
        if (removed) {
          await invalidateAccountReadCaches(account);
          epoch = prefs.getInt(epochKey) ?? 0;
        }
      }
      if (previous != null &&
          (key == 'profile' ||
              key == 'current_org' ||
              key == 'organization_context' ||
              key.startsWith('capabilities:'))) {
        dynamic old;
        try {
          old = (jsonDecode(previous) as Map)['value'];
        } catch (_) {}
        final changed = key == 'profile'
            ? (old is Map &&
                  (data is! Map ||
                      old['role'] != data['role'] ||
                      old['org_id'] != data['org_id']))
            : jsonEncode(old) != jsonEncode(data);
        if (changed) {
          await invalidateAccountReadCaches(account);
          epoch = prefs.getInt(epochKey) ?? 0;
        }
      }
      final derived = derivedValues?.call(data) ?? const <String, dynamic>{};
      if (replaceDerivedPrefix != null) {
        final prefix = accountStorageKey(
          account,
          'cache:$replaceDerivedPrefix',
        );
        final keep = derived.keys
            .map((k) => accountStorageKey(account, 'cache:$k'))
            .toSet();
        for (final k in prefs.getKeys().where(
          (k) => k.startsWith(prefix) && !keep.contains(k),
        )) {
          await prefs.remove(k);
        }
      }
      for (final entry in {...derived, key: data}.entries) {
        checkAccount();
        if ((prefs.getInt(epochKey) ?? 0) != epoch) {
          throw const AccountChangedException();
        }
        await prefs.setString(
          accountStorageKey(account, 'cache:${entry.key}'),
          jsonEncode({
            'value': entry.value,
            'savedAt': now().toUtc().toIso8601String(),
            'epoch': epoch,
          }),
        );
      }
      return data;
    } catch (error) {
      checkAccount();
      if (isAccessDenial(error)) await invalidateAccountReadCaches(account);
      if (!isConnectionFailure(error)) rethrow;
      if (Zone.current[_requireFreshReads] == true) rethrow;
      final cached = prefs.getString(storageKey);
      if (cached == null) rethrow;
      Map<dynamic, dynamic> stored;
      try {
        stored = jsonDecode(cached) as Map;
      } catch (_) {
        await prefs.remove(storageKey);
        rethrow;
      }
      final savedAt = DateTime.tryParse(stored['savedAt']?.toString() ?? '');
      if (savedAt == null ||
          now().difference(savedAt).isNegative ||
          now().difference(savedAt) > maxAge ||
          (stored['epoch'] ?? 0) != (prefs.getInt(epochKey) ?? 0)) {
        await prefs.remove(storageKey);
        rethrow;
      }
      return stored['value'];
    }
  }
}
