import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/models/client_org.dart';
import 'package:vortice_app/models/profile.dart';

// ── List all client orgs (owner sees all) ────────────────────────────────────

final clientOrgsProvider = FutureProvider<List<ClientOrg>>((ref) async {
  final data = await supabase
      .from(AppConstants.tClientOrgs)
      .select()
      .order('created_at', ascending: false);
  return (data as List)
      .map((e) => ClientOrg.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ── Fetch a single org by ID ─────────────────────────────────────────────────

final orgByIdProvider =
    FutureProvider.family<ClientOrg?, String>((ref, id) async {
  final data = await supabase
      .from(AppConstants.tClientOrgs)
      .select()
      .eq('id', id)
      .maybeSingle();
  if (data == null) return null;
  return ClientOrg.fromJson(data);
});

// ── Fetch all profiles belonging to an org ───────────────────────────────────

final orgMembersProvider =
    FutureProvider.family<List<Profile>, String>((ref, orgId) async {
  final data = await supabase
      .from(AppConstants.tProfiles)
      .select()
      .eq('org_id', orgId);
  return (data as List)
      .map((e) => Profile.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ── Fetch the current user's org (as admin/owner or member) ──────────────────

final currentUserOrgProvider = FutureProvider<ClientOrg?>((ref) async {
  // Watch auth so this re-runs on sign-in/out
  ref.watch(profileProvider);

  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return null;

  // 1. Check if user owns an org
  final owned = await supabase
      .from(AppConstants.tClientOrgs)
      .select()
      .eq('owner_profile_id', userId)
      .maybeSingle();
  if (owned != null) return ClientOrg.fromJson(owned as Map<String, dynamic>);

  // 2. Check if user's profile has an org_id
  final profileRow = await supabase
      .from(AppConstants.tProfiles)
      .select('org_id')
      .eq('id', userId)
      .maybeSingle();
  final orgId = profileRow?['org_id'] as String?;
  if (orgId == null) return null;

  final org = await supabase
      .from(AppConstants.tClientOrgs)
      .select()
      .eq('id', orgId)
      .maybeSingle();
  if (org == null) return null;
  return ClientOrg.fromJson(org as Map<String, dynamic>);
});

// ── Org controller ───────────────────────────────────────────────────────────

class OrgController extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;
  OrgController(this._ref) : super(const AsyncData(null));

  /// Create a new org and link the owner's profile to it.
  Future<String?> createOrg(String name, String ownerProfileId) async {
    state = const AsyncLoading();
    String? orgId;
    state = await AsyncValue.guard(() async {
      final result = await supabase
          .from(AppConstants.tClientOrgs)
          .insert({'name': name, 'owner_profile_id': ownerProfileId})
          .select('id')
          .single();
      orgId = result['id'] as String;
      // Link owner profile to the new org
      await supabase
          .from(AppConstants.tProfiles)
          .update({'org_id': orgId}).eq('id', ownerProfileId);
      _ref.invalidate(clientOrgsProvider);
      _ref.invalidate(currentUserOrgProvider);
    });
    return orgId;
  }

  /// Add a member to an org by updating their profile's org_id.
  Future<bool> addMember(String orgId, String profileId) async {
    state = const AsyncLoading();
    bool success = false;
    state = await AsyncValue.guard(() async {
      await supabase
          .from(AppConstants.tProfiles)
          .update({'org_id': orgId}).eq('id', profileId);
      _ref.invalidate(orgMembersProvider(orgId));
      success = true;
    });
    return success;
  }

  /// Remove a member from their org by setting their org_id to null.
  Future<bool> removeMember(String profileId, {String? orgId}) async {
    state = const AsyncLoading();
    bool success = false;
    state = await AsyncValue.guard(() async {
      await supabase
          .from(AppConstants.tProfiles)
          .update({'org_id': null}).eq('id', profileId);
      if (orgId != null) _ref.invalidate(orgMembersProvider(orgId));
      success = true;
    });
    return success;
  }

  /// Delete an org and null out all members' org_id.
  Future<bool> renameOrg(String orgId, String newName) async {
    state = const AsyncLoading();
    bool success = false;
    state = await AsyncValue.guard(() async {
      await supabase
          .from(AppConstants.tClientOrgs)
          .update({'name': newName})
          .eq('id', orgId);
      _ref.invalidate(clientOrgsProvider);
      _ref.invalidate(orgByIdProvider(orgId));
      success = true;
    });
    return success;
  }

  Future<bool> deleteOrg(String orgId) async {
    state = const AsyncLoading();
    bool success = false;
    state = await AsyncValue.guard(() async {
      // First, null out all members' org_id
      await supabase
          .from(AppConstants.tProfiles)
          .update({'org_id': null}).eq('org_id', orgId);
      // Then delete the org
      await supabase
          .from(AppConstants.tClientOrgs)
          .delete()
          .eq('id', orgId);
      _ref.invalidate(clientOrgsProvider);
      _ref.invalidate(orgMembersProvider(orgId));
      _ref.invalidate(currentUserOrgProvider);
      success = true;
    });
    return success;
  }
}

final orgControllerProvider =
    StateNotifierProvider<OrgController, AsyncValue<void>>((ref) {
  return OrgController(ref);
});
