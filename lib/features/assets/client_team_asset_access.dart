import 'package:drift/drift.dart' show Value;
import 'package:vortice_app/core/account_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/db/database.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/models/asset.dart';
import 'package:vortice_app/models/profile.dart';

/// Resolves the client profile whose fleet the current client-side user can see.
///
/// Client owners see their own fleet. Client staff inherit fleet visibility from
/// the client org they belong to:
/// profiles.org_id -> client_orgs.id -> client_orgs.owner_profile_id.
///
/// No org means no inherited fleet visibility. Do not fall back to all assets.
final currentClientFleetOwnerIdProvider = FutureProvider<String?>((ref) async {
  final profile = await ref.watch(profileProvider.future);
  if (profile == null || _isVorticeStaffRole(profile.role)) return null;

  final orgId = profile.orgId;
  if (orgId != null && orgId.isNotEmpty) {
    final orgRow =
        await AccountJsonCache(
          profile.id,
          () => supabase.auth.currentUser?.id,
        ).readThrough(
          'fleet_owner:$orgId',
          () => supabase
              .from(AppConstants.tClientOrgs)
              .select('owner_profile_id')
              .eq('id', orgId)
              .maybeSingle()
              .timeout(const Duration(seconds: 6)),
        );

    return orgRow?['owner_profile_id'] as String?;
  }

  return switch (profile.role) {
    UserRole.client || UserRole.clientAdmin => profile.id,
    UserRole.clientMechanic ||
    UserRole.clientOperator ||
    UserRole.operator => null,
    UserRole.owner || UserRole.employee => null,
  };
});

/// Assets visible to the current client-side team context.
///
/// This is the shared seam for operator/mechanic/client-admin asset pickers.
final currentClientFleetAssetsProvider = FutureProvider<List<Asset>>((
  ref,
) async {
  final ownerId = await ref.watch(currentClientFleetOwnerIdProvider.future);
  if (ownerId == null || ownerId.isEmpty) return [];

  final db = ref.watch(databaseProvider);
  final account = ref.watch(sessionProvider)?.user.id;

  Future<List<Asset>> cachedFleet() async {
    final cached = await db.assetsDao.getAll();
    return cached
        .where((asset) => asset.clientId == ownerId)
        .map(
          (asset) => Asset(
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
          ),
        )
        .toList();
  }

  try {
    final remote = await supabase
        .from(AppConstants.tAssets)
        .select()
        .eq('client_id', ownerId)
        .order('name');

    final assets = (remote as List)
        .map((e) => Asset.fromJson(e as Map<String, dynamic>))
        .toList();

    for (final asset in assets) {
      if (!db.belongsTo(account) || supabase.auth.currentUser?.id != account) {
        throw const AccountChangedException();
      }
      await db.assetsDao.upsert(
        AssetsTableCompanion(
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
        ),
      );
    }

    return assets;
  } catch (error) {
    if (!isConnectionFailure(error) ||
        !db.belongsTo(account) ||
        supabase.auth.currentUser?.id != account) {
      rethrow;
    }
    final cached = await cachedFleet();
    if (cached.isNotEmpty) return cached;
    rethrow;
  }
});

Map<String, dynamic> clientTeamAssetRow(Asset asset) => {
  'id': asset.id,
  'client_id': asset.clientId,
  'name': asset.name,
  'make': asset.make,
  'model': asset.model,
};

bool _isVorticeStaffRole(UserRole role) =>
    role == UserRole.owner || role == UserRole.employee;
