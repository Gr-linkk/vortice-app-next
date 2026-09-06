import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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

class AccountChangedException implements Exception {
  const AccountChangedException();
  @override
  String toString() => 'The signed-in account changed. Reopen this screen.';
}

/// A server denial never falls back to cache; late responses cannot cross users.
class AccountJsonCache {
  const AccountJsonCache(this.account, this.currentAccount);
  final String account;
  final String? Function() currentAccount;
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
        'savedAt': DateTime.now().toUtc().toIso8601String(),
      }),
    );
  }

  Future<dynamic> readThrough(
    String key,
    Future<dynamic> Function() fetch,
  ) async {
    checkAccount();
    final prefs = await SharedPreferences.getInstance();
    final storageKey = accountStorageKey(account, 'cache:$key');
    try {
      final data = await fetch();
      checkAccount();
      await prefs.setString(
        storageKey,
        jsonEncode({
          'value': data,
          'savedAt': DateTime.now().toUtc().toIso8601String(),
        }),
      );
      return data;
    } catch (error) {
      checkAccount();
      if (!isConnectionFailure(error)) rethrow;
      final cached = prefs.getString(storageKey);
      if (cached == null) rethrow;
      return (jsonDecode(cached) as Map)['value'];
    }
  }
}
