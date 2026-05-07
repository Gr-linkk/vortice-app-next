import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/orgs/org_provider.dart';
import 'package:vortice_app/models/profile.dart';

/// Resolves the current client owner profile id for client-side capability gates.
///
/// Asset-scoped screens should still prefer an explicit `asset.clientId`. This
/// provider is for dashboard/nav/workflow contexts where the current user may be
/// a client-org member rather than the owning client profile.
final currentClientIdProvider = FutureProvider<String?>((ref) async {
  final profile = await ref.watch(profileProvider.future);
  if (profile == null || isVorticeStaffRole(profile.role)) return null;

  final org = await ref.watch(currentUserOrgProvider.future);
  if (org != null) return org.ownerProfileId;

  return switch (profile.role) {
    UserRole.client || UserRole.clientAdmin => profile.id,
    UserRole.clientMechanic ||
    UserRole.clientOperator ||
    UserRole.operator =>
      null,
    UserRole.owner || UserRole.employee => null,
  };
});

bool isVorticeStaffRole(UserRole role) =>
    role == UserRole.owner || role == UserRole.employee;
