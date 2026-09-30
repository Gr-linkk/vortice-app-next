import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:vortice_app/core/account_storage.dart';
import 'package:vortice_app/core/rpc_failure.dart';
import 'package:vortice_app/domain/report_command.dart';
import 'package:vortice_app/sync/field_evidence.dart';

/// Hosted provider-report persistence. Widgets own fields and navigation; this
/// controller owns durable drafts and exact retries. The local-first transport
/// can use ReportCommand without this SharedPreferences/Supabase adapter.
class ProviderReportDraft {
  ProviderReportDraft({
    required this.account,
    required String organizationId,
    required String workOrderId,
    required this.currentAccount,
    required this.send,
  }) : storageKey = accountStorageKey(
         account,
         'provider_report:$organizationId:$workOrderId',
       );

  final String account, storageKey;
  final String? Function() currentAccount;
  final Future<void> Function(ReportCommand command) send;
  ReportCommand? _pending;
  ReportCommand? get pending => _pending;
  bool _ready = false, _cleared = false, _sending = false;
  Future<void> _writes = Future.value();
  Future<void> get flushed => _writes;

  void _checkAccount() {
    if (account.isEmpty || currentAccount() != account) {
      throw const AccountChangedException();
    }
  }

  Future<Map<String, dynamic>?> load() async {
    _checkAccount();
    final raw = (await SharedPreferences.getInstance()).getString(storageKey);
    _checkAccount();
    Map<String, dynamic>? data;
    if (raw != null) {
      // Parsing must succeed before enabling writes. A broken draft is retained
      // for recovery rather than silently overwritten by the server's old copy.
      final saved = jsonDecode(raw) as Map;
      data = Map<String, dynamic>.from(saved['data'] as Map);
      _pending = saved['pending'] == null
          ? null
          : ReportCommand.fromJson(
              Map<String, dynamic>.from(saved['pending'] as Map),
            );
    }
    _ready = true;
    return data;
  }

  Future<void> save(Map<String, dynamic> data) {
    if (!_ready || _cleared) return _writes;
    final raw = jsonEncode({'data': data, 'pending': _pending?.toJson()});
    // A failed disk write must not poison every subsequent attempt.
    _writes = _writes.catchError((Object _) {}).then((_) async {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(storageKey, raw)) {
        throw StateError('Could not save this draft on the device');
      }
    });
    return _writes;
  }

  Future<void> submit({
    required int revision,
    required String action,
    required Map<String, dynamic> data,
  }) async {
    if (!_ready || _cleared || _sending) {
      throw StateError('This report is not ready to send.');
    }
    _checkAccount();
    _sending = true;
    final retrying = _pending != null;
    _pending ??= ReportCommand(
      id: const Uuid().v4(),
      revision: revision,
      action: action,
      data: data,
    );
    var requestStarted = false;
    try {
      await save(data);
      _checkAccount();
      requestStarted = true;
      await send(_pending!);
      _checkAccount();
      await _writes;
      if (!await (await SharedPreferences.getInstance()).remove(storageKey)) {
        throw StateError('Could not clear the saved retry on this device.');
      }
      _cleared = true;
      _pending = null;
    } catch (error) {
      if ((!requestStarted && !retrying) ||
          rpcWriteWasRejected(error) ||
          (error is FieldEvidencePendingException && !retrying)) {
        _pending = null;
      }
      // A later local/preflight failure cannot disprove an earlier commit.
      await save(data);
      rethrow;
    } finally {
      _sending = false;
    }
  }
}
