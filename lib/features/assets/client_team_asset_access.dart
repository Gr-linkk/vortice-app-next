import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
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
    final orgRow = await supabase
        .from(AppConstants.tClientOrgs)
        .select('owner_profile_id')
        .eq('id', orgId)
        .maybeSingle();

    return orgRow?['owner_profile_id'] as String?;
  }

  return switch (profile.role) {
    UserRole.client || UserRole.clientAdmin => profile.id,
    UserRole.clientMechanic ||
    UserRole.clientOperator ||
    UserRole.operator =>
      null,
    UserRole.owner || UserRole.employee => null,
  };
});

/// Assets visible to the current client-side team context.
///
/// This is the shared seam for operator/mechanic/client-admin asset pickers.
final currentClientFleetAssetsProvider =
    FutureProvider<List<Asset>>((ref) async {
  final ownerId = await ref.watch(currentClientFleetOwnerIdProvider.future);
  if (ownerId == null || ownerId.isEmpty) return [];

  final remote = await supabase
      .from(AppConstants.tAssets)
      .select()
      .eq('client_id', ownerId)
      .order('name');

  return (remote as List)
      .map((e) => Asset.fromJson(e as Map<String, dynamic>))
      .toList();
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
