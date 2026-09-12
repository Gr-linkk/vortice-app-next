import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/auth/otp_auth_provider.dart';
import 'package:vortice_app/features/auth/otp_sign_in_screen.dart';
import 'package:vortice_app/features/membership/membership_models.dart';
import 'package:vortice_app/features/membership/membership_provider.dart';
import 'package:vortice_app/features/membership/organization_screen.dart';
import 'package:vortice_app/sync/online_action_gate.dart';

class FakeOtp extends OtpAuthRepository {
  final List<OtpContact> sent = [];
  final List<String> verified = [];
  @override
  Future<void> send(OtpContact contact, {required String language}) async {
    sent.add(contact);
  }

  @override
  Future<void> verify(OtpContact contact, String code) async {
    verified.add(code);
  }
}

class FakeMembership extends MembershipRepository {
  List<String>? capturedRoles;
  List<String>? capturedPermissions;
  @override
  Future<Map<String, dynamic>> invite(
    String organizationId,
    List<String> roles,
    List<String> permissions,
    String contact,
  ) async {
    capturedRoles = roles;
    capturedPermissions = permissions;
    return {
      'code': 'TEST-INVITATION-CODE',
      'expires_at': '2026-09-19T00:00:00Z',
    };
  }
}

void main() {
  testWidgets('deferred delivery explains password sign-in and sends nothing', (tester) async {
    final repository = FakeOtp();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        otpAuthRepositoryProvider.overrideWithValue(repository),
        otpDeliveryChannelsProvider.overrideWithValue({}),
      ],
      child: const MaterialApp(home: OtpSignInScreen()),
    ));
    expect(find.textContaining('Code sign-in is not available yet'), findsOneWidget);
    expect(find.text('Send code'), findsNothing);
    expect(repository.sent, isEmpty);
  });
  testWidgets('contact correction and code verification never send twice', (
    tester,
  ) async {
    final repository = FakeOtp();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          otpAuthRepositoryProvider.overrideWithValue(repository),
          otpDeliveryChannelsProvider.overrideWithValue({VerificationChannel.email, VerificationChannel.phone}),
        ],
        child: const MaterialApp(home: OtpSignInScreen()),
      ),
    );
    await tester.enterText(
      find.byType(TextFormField),
      'person@example.invalid',
    );
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();
    expect(repository.sent.length, 1);
    expect(find.text('Check your messages'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('verification-code')),
      '123456',
    );
    await tester.tap(find.text('Verify and continue'));
    await tester.pumpAndSettle();
    expect(repository.verified, ['123456']);
    expect(repository.sent.length, 1);
    await tester.tap(find.text('Change email or phone'));
    await tester.pumpAndSettle();
    expect(find.text('Send code'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'inviter chooses multiple roles and only gets a code, not a sent claim',
    (tester) async {
      final repository = FakeMembership();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            membershipRepositoryProvider.overrideWithValue(repository),
            onlineActionGateProvider.overrideWith((ref) => OnlineActionGate(
              account: 'fixture', currentAccount: () => 'fixture',
              probe: () async {},
            )),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: MembershipEditor(
                organization: OrganizationMembership(
                  organizationId: 'company',
                  name: 'Company',
                  ownerProfileId: 'owner',
                  roles: ['company_owner'],
                  permissions: [],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Mechanic / Technician'));
      await tester.pump();
      await tester.ensureVisible(find.text('Create invitation'));
      await tester.tap(find.text('Create invitation'));
      await tester.pumpAndSettle();
      expect(repository.capturedRoles, containsAll(['operator', 'mechanic']));
      expect(repository.capturedPermissions, isEmpty);
      expect(find.text('Invitation ready'), findsOneWidget);
      expect(find.text('TEST-INVITATION-CODE'), findsOneWidget);
      expect(find.textContaining('sent'), findsNothing);
    },
  );
  testWidgets('delegated team administrator cannot select owner or billing', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: MembershipEditor(
              organization: OrganizationMembership(
                organizationId: 'company',
                name: 'Company',
                ownerProfileId: 'owner',
                roles: ['supervisor'],
                permissions: ['team_admin'],
              ),
            ),
          ),
        ),
      ),
    );
    final owner = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, 'Company Owner'),
    );
    final billing = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, 'Billing'),
    );
    expect(owner.onChanged, isNull);
    expect(billing.onChanged, isNull);
  });
}
