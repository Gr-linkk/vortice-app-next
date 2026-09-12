import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/account_storage.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/models/asset_engine.dart';

// ── Fetch a single engine by ID ────────────────────────────────────────────

final engineByIdProvider = FutureProvider.family<AssetEngine?, String>((
  ref,
  engineId,
) async {
  if (await ref.watch(profileProvider.future) == null) return null;
  final account = supabase.auth.currentUser!.id;
  final data =
      await AccountJsonCache(
        account,
        () => supabase.auth.currentUser?.id,
      ).readThrough(
        'engine:$engineId',
        () => supabase
            .from(AppConstants.tAssetEngines)
            .select()
            .eq('id', engineId)
            .maybeSingle()
            .timeout(const Duration(seconds: 6)),
      );

  if (data == null) return null;
  return AssetEngine.fromJson(Map<String, dynamic>.from(data as Map));
});

// ── Fetch engines for a specific asset ─────────────────────────────────────

final enginesForAssetProvider =
    FutureProvider.family<List<AssetEngine>, String>((ref, assetId) async {
      if (await ref.watch(profileProvider.future) == null) return [];
      final account = supabase.auth.currentUser!.id;
      final remote =
          await AccountJsonCache(
            account,
            () => supabase.auth.currentUser?.id,
          ).readThrough(
            'asset_engines:$assetId',
            () => supabase
                .from(AppConstants.tAssetEngines)
                .select()
                .eq('asset_id', assetId)
                .order('label')
                .timeout(const Duration(seconds: 6)),
            derivedValues: (data) => {
              for (final row in data as List) 'engine:${row['id']}': row,
            },
          );

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
    String id,
    String assetId,
    Map<String, dynamic> data,
  ) async {
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
