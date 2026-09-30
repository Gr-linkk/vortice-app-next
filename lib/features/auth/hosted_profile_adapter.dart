import 'package:vortice_app/models/profile.dart';

/// Compatibility boundary for the hosted application's legacy route roles.
/// Organization membership remains the source of capabilities; a route role
/// only selects existing UI. This adapter is retired with the hosted runtime.
Profile hostedProfile(
  Map<String, dynamic> profile, {
  Map<String, dynamic>? membership,
}) {
  if (profile['role'] != 'member') return Profile.fromJson(profile);
  if (membership == null) {
    throw StateError('A member profile requires its organization context.');
  }
  return Profile.fromJson({
    ...profile,
    'role': membership['route_role'],
    'org_id': membership['active_organization_id'],
    'membership_managed': true,
    'onboarding_required': membership['onboarding_required'] == true,
    'organization_roles': membership['roles'] ?? <String>[],
    'organization_permissions': membership['permissions'] ?? <String>[],
  });
}
