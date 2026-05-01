import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/models/profile.dart';

// ── Fetch all client profiles ──────────────────────────────────────────────

final clientsProvider = FutureProvider<List<Profile>>((ref) async {
  final remote = await supabase
      .from(AppConstants.tProfiles)
      .select()
      .inFilter('role', ['client', 'client_admin'])
      .order('full_name');

  return (remote as List)
      .map((e) => Profile.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ── Client asset/work order counts ─────────────────────────────────────────

final clientAssetCountProvider =
    FutureProvider.family<int, String>((ref, clientId) async {
  final data = await supabase
      .from(AppConstants.tAssets)
      .select('id')
      .eq('client_id', clientId);
  return (data as List).length;
});

final clientWorkOrderCountProvider =
    FutureProvider.family<int, String>((ref, clientId) async {
  final data = await supabase
      .from(AppConstants.tWorkOrders)
      .select('id')
      .eq('client_id', clientId);
  return (data as List).length;
});

// ── Client controller ──────────────────────────────────────────────────────

class ClientController extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;
  ClientController(this._ref) : super(const AsyncData(null));

  Future<bool> updateClient(String id, Map<String, dynamic> data) async {
    state = const AsyncLoading();
    bool success = false;
    state = await AsyncValue.guard(() async {
      await supabase.from(AppConstants.tProfiles).update(data).eq('id', id);
      _ref.invalidate(clientsProvider);
      success = true;
    });
    return success;
  }
}

final clientControllerProvider =
    StateNotifierProvider<ClientController, AsyncValue<void>>((ref) {
  return ClientController(ref);
});
