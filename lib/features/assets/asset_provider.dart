import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/db/database.dart';
import 'package:vortice_app/features/assets/client_team_asset_access.dart';
import 'package:vortice_app/models/asset.dart';

// ── Remote fetch ───────────────────────────────────────────────────────────

final assetsProvider = FutureProvider<List<Asset>>((ref) async {
  final db = ref.watch(databaseProvider);
  final dao = db.assetsDao;

  Future<List<Asset>> cachedAssets() async {
    final cached = await dao.getAll();
    return cached
        .map((asset) => Asset(
              id: asset.id,
              clientId: asset.clientId,
              assetTypeId: asset.assetTypeId,
              name: asset.name,
              make: asset.make,
              model: asset.model,
              year: asset.year,
              serialNumber: asset.serialNumber,
              location: asset.location,
              notes: asset.notes,
              telemetryEnabled: asset.telemetryEnabled,
              telemetrySource: asset.telemetrySource,
              createdAt: asset.createdAt,
              updatedAt: asset.updatedAt,
            ))
        .toList();
  }

  try {
    final remote =
        await supabase.from(AppConstants.tAssets).select().order('name');

    final assets = (remote as List)
        .map((e) => Asset.fromJson(e as Map<String, dynamic>))
        .toList();

    // A successful empty remote result is authoritative for the current user.
    // Do not fall back to the unscoped local cache here, or a different login
    // can see stale assets from a previous account.

    // Persist to local cache
    for (final asset in assets) {
      await dao.upsert(AssetsTableCompanion(
        id: Value(asset.id),
        clientId: Value(asset.clientId),
        assetTypeId: Value(asset.assetTypeId),
        name: Value(asset.name),
        make: Value(asset.make),
        model: Value(asset.model),
        year: Value(asset.year),
        serialNumber: Value(asset.serialNumber),
        location: Value(asset.location),
        notes: Value(asset.notes),
        telemetryEnabled: Value(asset.telemetryEnabled),
        telemetrySource: Value(asset.telemetrySource),
        createdAt: Value(asset.createdAt),
        updatedAt: Value(asset.updatedAt),
      ));
    }

    return assets;
  } catch (_) {
    final cached = await cachedAssets();
    if (cached.isNotEmpty) return cached;
    rethrow;
  }
});

/// For client-side operators/mechanics/admins: assets scoped to their client org.
/// No org means no inherited fleet visibility.
final operatorScopedAssetsProvider = currentClientFleetAssetsProvider;

final assetByIdProvider =
    FutureProvider.family<Asset?, String>((ref, id) async {
  final data = await supabase
      .from(AppConstants.tAssets)
      .select()
      .eq('id', id)
      .maybeSingle();

  if (data == null) return null;
  return Asset.fromJson(data);
});

// ── Asset controller ───────────────────────────────────────────────────────

class AssetController extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;
  AssetController(this._ref) : super(const AsyncData(null));

  Future<bool> createAsset(Map<String, dynamic> data) async {
    state = const AsyncLoading();
    bool success = false;
    state = await AsyncValue.guard(() async {
      await supabase.from(AppConstants.tAssets).insert(data);
      _ref.invalidate(assetsProvider);
      success = true;
    });
    return success;
  }

  Future<bool> updateAsset(String id, Map<String, dynamic> data) async {
    state = const AsyncLoading();
    bool success = false;
    state = await AsyncValue.guard(() async {
      await supabase.from(AppConstants.tAssets).update(data).eq('id', id);
      _ref.invalidate(assetsProvider);
      _ref.invalidate(assetByIdProvider(id));
      success = true;
    });
    return success;
  }

  Future<bool> deleteAsset(String id) async {
    state = const AsyncLoading();
    bool success = false;
    state = await AsyncValue.guard(() async {
      await supabase.from(AppConstants.tAssets).delete().eq('id', id);
      _ref.invalidate(assetsProvider);
      success = true;
    });
    return success;
  }
}

final assetControllerProvider =
    StateNotifierProvider<AssetController, AsyncValue<void>>((ref) {
  return AssetController(ref);
});
