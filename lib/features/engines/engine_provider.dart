import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/models/asset_engine.dart';

// ── Fetch a single engine by ID ────────────────────────────────────────────

final engineByIdProvider =
    FutureProvider.family<AssetEngine?, String>((ref, engineId) async {
  final data = await supabase
      .from(AppConstants.tAssetEngines)
      .select()
      .eq('id', engineId)
      .maybeSingle();

  if (data == null) return null;
  return AssetEngine.fromJson(data as Map<String, dynamic>);
});

// ── Fetch engines for a specific asset ─────────────────────────────────────

final enginesForAssetProvider =
    FutureProvider.family<List<AssetEngine>, String>((ref, assetId) async {
  final remote = await supabase
      .from(AppConstants.tAssetEngines)
      .select()
      .eq('asset_id', assetId)
      .order('label');

  return (remote as List)
      .map((e) => AssetEngine.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ── Engine controller ──────────────────────────────────────────────────────

class EngineController extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;
  EngineController(this._ref) : super(const AsyncData(null));

  Future<bool> addEngine(Map<String, dynamic> data) async {
    state = const AsyncLoading();
    bool success = false;
    state = await AsyncValue.guard(() async {
      await supabase.from(AppConstants.tAssetEngines).insert(data);
      _ref.invalidate(enginesForAssetProvider(data['asset_id'] as String));
      success = true;
    });
    return success;
  }

  Future<bool> updateEngine(
      String id, String assetId, Map<String, dynamic> data) async {
    state = const AsyncLoading();
    bool success = false;
    state = await AsyncValue.guard(() async {
      await supabase.from(AppConstants.tAssetEngines).update(data).eq('id', id);
      _ref.invalidate(enginesForAssetProvider(assetId));
      success = true;
    });
    return success;
  }

  Future<bool> deleteEngine(String id, String assetId) async {
    state = const AsyncLoading();
    bool success = false;
    state = await AsyncValue.guard(() async {
      await supabase.from(AppConstants.tAssetEngines).delete().eq('id', id);
      _ref.invalidate(enginesForAssetProvider(assetId));
      success = true;
    });
    return success;
  }
}

final engineControllerProvider =
    StateNotifierProvider<EngineController, AsyncValue<void>>((ref) {
  return EngineController(ref);
});
