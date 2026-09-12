import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/auth/otp_auth_provider.dart';
import 'package:vortice_app/features/membership/membership_models.dart';

void main() {
  test('supervisor work rights do not imply sensitive delegation', () {
    expect(membershipAllows(['supervisor'], [], 'planning'), isTrue);
    for (final permission in OrganizationPermission.values) {
      expect(membershipAllows(['supervisor'], [], permission.key), isFalse);
    }
    expect(
      membershipAllows(
        ['supervisor'],
        ['inspection_manage'],
        'inspection_manage',
      ),
      isTrue,
    );
    expect(
      membershipAllows(['supervisor'], ['inspection_manage'], 'billing'),
      isFalse,
    );
  });
  test('multi-role mechanic/operator union preserves least privilege', () {
    expect(
      membershipAllows(['mechanic', 'operator'], [], 'work_assigned'),
      isTrue,
    );
    expect(membershipAllows(['mechanic', 'operator'], [], 'preop'), isTrue);
    expect(
      membershipAllows(['mechanic', 'operator'], [], 'assets_manage'),
      isFalse,
    );
    expect(
      membershipAllows(['mechanic', 'operator'], [], 'review_work'),
      isFalse,
    );
    expect(membershipAllows([], ['billing'], 'billing'), isFalse);
  });
  test(
    'organization context selects server-chosen membership, never first owner',
    () {
      final context = OrganizationContext.fromJson({
        'active_organization_id': 'company-b',
        'memberships': [
          {
            'organization_id': 'company-a',
            'name': 'A',
            'owner_profile_id': 'self',
            'roles': ['company_owner'],
            'permissions': [],
          },
          {
            'organization_id': 'company-b',
            'name': 'B',
            'owner_profile_id': 'other',
            'roles': ['operator'],
            'permissions': [],
          },
        ],
      });
      expect(context.active?.organizationId, 'company-b');
      expect(context.active?.can('billing'), isFalse);
    },
  );
  test('verification contact accepts email and international phone', () {
    expect(
      OtpContact.parse(VerificationChannel.email, ' NAME@EXAMPLE.COM ')?.value,
      'name@example.com',
    );
    expect(
      OtpContact.parse(VerificationChannel.phone, '+1 (555) 123-4567')?.value,
      '+15551234567',
    );
    expect(OtpContact.parse(VerificationChannel.phone, '5551234567'), isNull);
    expect(OtpContact.parse(VerificationChannel.email, 'name@'), isNull);
  });
  test('expired, used and revoked invitations cannot appear open', () {
    final now = DateTime.utc(2026, 9, 12);
    MembershipInvitation invitation({
      DateTime? redeemed,
      DateTime? revoked,
      DateTime? expiry,
    }) => MembershipInvitation(
      id: 'invite',
      roles: ['operator'],
      permissions: [],
      expiresAt: expiry ?? now.add(const Duration(days: 1)),
      redeemedAt: redeemed,
      revokedAt: revoked,
    );
    expect(invitation().activeAt(now), isTrue);
    expect(invitation(expiry: now).activeAt(now), isFalse);
    expect(invitation(redeemed: now).activeAt(now), isFalse);
    expect(invitation(revoked: now).activeAt(now), isFalse);
  });
}
