import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/auth/hosted_profile_adapter.dart';
import 'package:vortice_app/features/membership/membership_models.dart';
import 'package:vortice_app/models/profile.dart';

void main() {
  const row = {
    'id': 'actor',
    'email': 'fixture@example.invalid',
    'full_name': 'Fixture',
    'role': 'member',
  };
  test('legacy profile remains readable without inventing membership', () {
    final profile = hostedProfile({
      ...row,
      'role': 'client_mechanic',
      'org_id': 'legacy',
    });
    expect(profile.role, UserRole.clientMechanic);
    expect(profile.orgId, 'legacy');
    expect(profile.membershipManaged, isFalse);
    expect(profile.canInOrganization('approve_work'), isFalse);
  });
  test('route compatibility never grants modern membership capabilities', () {
    final profile = hostedProfile(
      row,
      membership: {
        'route_role': 'owner',
        'active_organization_id': 'company',
        'roles': ['operator'],
        'permissions': [],
      },
    );
    expect(profile.role, UserRole.owner);
    expect(profile.orgId, 'company');
    expect(profile.canInOrganization('preop'), isTrue);
    expect(profile.canInOrganization('approve_work'), isFalse);
    expect(profile.canInOrganization('billing'), isFalse);
    expect(row['role'], 'member');
  });
  test('onboarding and absent context cannot gain access', () {
    expect(() => hostedProfile(row), throwsStateError);
    final profile = hostedProfile(
      row,
      membership: {
        'route_role': 'client',
        'onboarding_required': true,
        'roles': ['company_owner'],
        'permissions': ['billing'],
      },
    );
    expect(profile.canInOrganization('billing'), isFalse);
  });
}
