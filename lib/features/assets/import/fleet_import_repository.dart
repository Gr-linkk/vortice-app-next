import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:vortice_app/core/account_storage.dart';
import 'package:vortice_app/core/retryable_rpc.dart';
import 'package:vortice_app/core/supabase_client.dart';

final fleetImportRepositoryProvider = Provider(
  (ref) => FleetImportRepository(),
);

class FleetImportRepository {
  String get account => supabase.auth.currentUser!.id;
  Future<Map<String, dynamic>> context(String? client) async =>
      Map<String, dynamic>.from(
        await supabase.rpc('fleet_import_context', params: {'p_client': client})
            as Map,
      );
  Future<Map<String, dynamic>> preview(
    String client,
    List<Map<String, dynamic>> assets,
  ) async => Map<String, dynamic>.from(
    await supabase.rpc(
          'import_fleet',
          params: {
            'p_operation': const Uuid().v4(),
            'p_client': client,
            'p_assets': assets,
            'p_preview': true,
          },
        )
        as Map,
  );
  String _key(String actor) => accountStorageKey(actor, 'fleet-import-pending');
  void _check(String actor) {
    if (actor != account) throw const AccountChangedException();
  }

  Future<Map<String, dynamic>?> pending() async {
    final actor = account;
    final prefs = await SharedPreferences.getInstance();
    _check(actor);
    final json = prefs.getString(_key(actor));
    return json == null ? null : jsonDecode(json) as Map<String, dynamic>;
  }

  Future<void> discard() async {
    final actor = account;
    final prefs = await SharedPreferences.getInstance();
    _check(actor);
    await prefs.remove(_key(actor));
  }

  Future<Map<String, dynamic>> commit(
    String client,
    List<Map<String, dynamic>> assets,
  ) async {
    final actor = account;
    final rpc = authenticatedRetryableRpc();
    final prefs = await SharedPreferences.getInstance();
    _check(actor);
    final input = {'p_client': client, 'p_assets': assets, 'p_preview': false};
    final old = prefs.getString(_key(actor));
    if (old != null && jsonEncode(jsonDecode(old)) != jsonEncode(input)) {
      throw StateError(
        'Resolve the pending import before importing another table.',
      );
    }
    if (!await prefs.setString(_key(actor), jsonEncode(input))) {
      throw StateError('Could not preserve the import for retry.');
    }
    _check(actor);
    final result = Map<String, dynamic>.from(
      await rpc.call('import_fleet', input) as Map,
    );
    _check(actor);
    await prefs.remove(_key(actor));
    return result;
  }
}
