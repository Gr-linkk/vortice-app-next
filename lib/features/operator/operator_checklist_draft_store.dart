import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:vortice_app/core/account_storage.dart';
import 'operator_checklist_support.dart';

/// One account-owned record per run. Starting another run cannot replace it.
class OperatorChecklistDraftStore {
  OperatorChecklistDraftStore(this.account, this.currentAccount);
  final String account;
  final String? Function() currentAccount;

  String get _prefix => accountStorageKey(account, 'operator_checklist_run:');
  void _checkAccount() {
    if (currentAccount() != account) throw const AccountChangedException();
  }

  Future<List<Map<String, dynamic>>> list() async {
    _checkAccount();
    final prefs = await SharedPreferences.getInstance();
    _checkAccount();
    final legacy = accountStorageKey(account, operatorChecklistDraftKey);
    // Also imports corrected outbox drafts, which still use the legacy key.
    for (final key
        in prefs
            .getKeys()
            .where((key) => key == legacy || key.startsWith('$legacy:'))
            .toList()) {
      final raw = prefs.getString(key);
      if (raw == null) continue;
      try {
        final data = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        if (data['assetId'] == null || data['templateId'] == null) continue;
        data['operation_id'] ??= const Uuid().v4();
        if (key != legacy) {
          data['assignment_id'] ??= key.substring(legacy.length + 1);
        }
        final target = '$_prefix${data['operation_id']}';
        if (!prefs.containsKey(target)) {
          _checkAccount();
          if (!await prefs.setString(target, jsonEncode(data))) {
            throw StateError('Checklist draft could not be saved.');
          }
        } else {
          // Never discard a differing legacy payload under the same replay ID.
          final saved = jsonDecode(prefs.getString(target)!) as Map;
          if (jsonEncode(saved) != jsonEncode(data)) continue;
        }
        _checkAccount();
        // A late legacy writer may have replaced it while storage was pending.
        if (prefs.getString(key) == raw) await prefs.remove(key);
      } on FormatException {
        // Keep unreadable data for recovery; one bad draft cannot erase others.
      } on TypeError {
        // Likewise preserve older unsupported shapes without auto-opening them.
      }
    }
    final drafts = <Map<String, dynamic>>[];
    for (final key in prefs.getKeys().where((key) => key.startsWith(_prefix))) {
      try {
        final data = Map<String, dynamic>.from(
          jsonDecode(prefs.getString(key)!) as Map,
        );
        if (data['assetId'] != null && data['templateId'] != null) {
          drafts.add(data);
        }
      } on FormatException {
        continue;
      } on TypeError {
        continue;
      }
    }
    _checkAccount();
    drafts.sort(
      (a, b) => '${b['started_at'] ?? b['completedAt']}'.compareTo(
        '${a['started_at'] ?? a['completedAt']}',
      ),
    );
    return drafts;
  }

  Future<void> save(Map<String, dynamic> data) async {
    _checkAccount();
    if (data['assetId'] == null || data['templateId'] == null) return;
    final operation = data['operation_id'] as String;
    final raw = jsonEncode(data); // Freeze before any asynchronous work.
    final prefs = await SharedPreferences.getInstance();
    _checkAccount();
    if (!await prefs.setString('$_prefix$operation', raw)) {
      throw StateError('Checklist draft could not be saved.');
    }
  }

  Future<void> remove(String operation) async {
    _checkAccount();
    final prefs = await SharedPreferences.getInstance();
    _checkAccount();
    await prefs.remove('$_prefix$operation');
  }
}
