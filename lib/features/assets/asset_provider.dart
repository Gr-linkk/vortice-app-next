import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/db/database.dart';
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
    final remote = await supabase
        .from(AppConstants.tAssets)
        .select()
        .order('name');

    final assets = (remote as List)
        .map((e) => Asset.fromJson(e as Map<String, dynamic>))
        .toList();

    if (assets.isEmpty) {
      final cached = await cachedAssets();
      if (cached.isNotEmpty) return cached;
    }

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

/// For operators/client_mechanics: assets scoped to their org's owner.
/// Falls back to assetsProvider for other roles.
final operatorScopedAssetsProvider = FutureProvider<List<Asset>>((ref) async {
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return [];

  final profileRow = await supabase
      .from('profiles')
      .select('org_id, role')
      .eq('id', userId)
      .maybeSingle();

  final orgId = profileRow?['org_id'] as String?;
  if (orgId == null) {
    // No org — fall back to all accessible assets (RLS handles scoping)
    return ref.watch(assetsProvider).valueOrNull ?? [];
  }

  // Find org owner
  final orgRow = await supabase
      .from('client_orgs')
      .select('owner_profile_id')
      .eq('id', orgId)
      .maybeSingle();

  final ownerId = orgRow?['owner_profile_id'] as String?;
  if (ownerId == null) return [];

  final remote = await supabase
      .from('assets')
      .select()
      .eq('client_id', ownerId)
      .order('name');

  return (remote as List)
      .map((e) => Asset.fromJson(e as Map<String, dynamic>))
      .toList();
});

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
