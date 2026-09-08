import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'parts_readiness_models.dart';

abstract class PartsReadinessRepository {
  Future<PartsWorkspace> load(String? jobId);
  Future<Map<String, dynamic>?> pending();
  Future<void> change(String? jobId, String action, Map<String, dynamic> data);
  Future<void> retry();
}

class SupabasePartsReadinessRepository implements PartsReadinessRepository {
  SupabasePartsReadinessRepository(this.client, this.accountId);
  final SupabaseClient client;
  final String accountId;
  bool _changing = false;
  String get _key => 'parts-pending-v1:$accountId';
  void _checkAccount() {
    if (client.auth.currentUser?.id != accountId) {
      throw StateError('Account changed. Reopen parts.');
    }
  }

  @override
  Future<PartsWorkspace> load(String? jobId) async {
    _checkAccount();
    final result = await client
        .rpc('parts_workspace', params: {'p_job': jobId})
        .timeout(const Duration(seconds: 15));
    _checkAccount();
    return PartsWorkspace(Map<String, dynamic>.from(result as Map));
  }

  @override
  Future<Map<String, dynamic>?> pending() async {
    _checkAccount();
    final text = (await SharedPreferences.getInstance()).getString(_key);
    return text == null
        ? null
        : Map<String, dynamic>.from(jsonDecode(text) as Map);
  }

  @override
  Future<void> change(
    String? jobId,
    String action,
    Map<String, dynamic> data,
  ) async {
    if (_changing) {
      throw StateError('A parts change is already in progress.');
    }
    final payload = jsonDecode(jsonEncode(data));
    _changing = true;
    try {
      _checkAccount();
      if (await pending() != null) {
        throw StateError('Retry the unconfirmed change first.');
      }
      final operation = <String, dynamic>{
        'p_job': jobId,
        'p_operation': const Uuid().v4(),
        'p_action': action,
        'p_data': payload,
      };
      final saved = await (await SharedPreferences.getInstance()).setString(
        _key,
        jsonEncode(operation),
      );
      if (!saved) {
        throw StateError('Could not preserve this change for safe retry.');
      }
      await _send(operation);
    } finally {
      _changing = false;
    }
  }

  @override
  Future<void> retry() async {
    if (_changing) {
      throw StateError('A parts change is already in progress.');
    }
    _changing = true;
    try {
      final operation = await pending();
      if (operation != null) await _send(operation);
    } finally {
      _changing = false;
    }
  }

  Future<void> _send(Map<String, dynamic> operation) async {
    _checkAccount();
    try {
      await client
          .rpc('parts_change', params: operation)
          .timeout(const Duration(seconds: 20));
    } on PostgrestException catch (error) {
      // Only a SQLSTATE rejection proves rollback. Gateway errors can arrive
      // after commit, so keep their identity just like a lost connection.
      if (RegExp(r'^[0-9A-Z]{5}$').hasMatch(error.code ?? '')) {
        await (await SharedPreferences.getInstance()).remove(_key);
      }
      rethrow;
    }
    await (await SharedPreferences.getInstance()).remove(_key);
  }
}

final partsReadinessRepositoryProvider = Provider<PartsReadinessRepository>((
  ref,
) {
  final account = ref.watch(profileProvider).valueOrNull?.id ?? '';
  return SupabasePartsReadinessRepository(supabase, account);
});
final partsWorkspaceProvider = FutureProvider.autoDispose
    .family<PartsWorkspace, String?>(
      (ref, jobId) => ref.watch(partsReadinessRepositoryProvider).load(jobId),
    );

final partsReadinessSummaryProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
      final account = ref.watch(profileProvider).valueOrNull;
      if (account == null) return {};
      final result = await supabase
          .rpc('parts_readiness_summary')
          .timeout(const Duration(seconds: 15));
      return Map<String, dynamic>.from(result as Map);
    });
