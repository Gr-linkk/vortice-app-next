import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/account_storage.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/membership/membership_models.dart';

class MembershipRepository {
  Future<OrganizationContext> context() async {
    final account = supabase.auth.currentUser?.id;
    if (account == null) return const OrganizationContext();
    final data =
        await AccountJsonCache(
          account,
          () => supabase.auth.currentUser?.id,
        ).readThrough(
          'organization_context',
          () => supabase
              .rpc('organization_context')
              .timeout(const Duration(seconds: 6)),
        );
    return OrganizationContext.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<OrganizationTeam> team(String organizationId) async =>
      OrganizationTeam.fromJson(
        Map<String, dynamic>.from(
          await supabase.rpc(
                'organization_team',
                params: {'p_organization_id': organizationId},
              )
              as Map,
        ),
      );
  Future<void> selectOrganization(String organizationId) async {
    await supabase.rpc(
      'set_active_organization',
      params: {'p_organization_id': organizationId},
    );
  }

  Future<String> createCompany(String name, String fullName) async =>
      await supabase.rpc(
            'create_company_workspace',
            params: {'p_name': name.trim(), 'p_full_name': fullName.trim()},
          )
          as String;
  Future<String> redeem(String code, String fullName) async =>
      await supabase.rpc(
            'redeem_membership_invite',
            params: {
              'p_code': code.trim().toUpperCase(),
              'p_full_name': fullName.trim(),
            },
          )
          as String;
  Future<Map<String, dynamic>> invite(
    String organizationId,
    List<String> roles,
    List<String> permissions,
    String contact,
  ) async => Map<String, dynamic>.from(
    await supabase.rpc(
          'create_membership_invite',
          params: {
            'p_organization_id': organizationId,
            'p_roles': roles,
            'p_permissions': permissions,
            'p_contact': contact.trim(),
          },
        )
        as Map,
  );
  Future<void> revokeInvite(String id) async {
    await supabase.rpc(
      'revoke_membership_invite',
      params: {'p_invitation_id': id},
    );
  }

  Future<void> updateMember(
    String organizationId,
    String profileId,
    List<String> roles,
    List<String> permissions,
    String status,
  ) async {
    await supabase.rpc(
      'update_organization_membership',
      params: {
        'p_organization_id': organizationId,
        'p_profile_id': profileId,
        'p_roles': roles,
        'p_permissions': permissions,
        'p_status': status,
      },
    );
  }
}

final membershipRepositoryProvider = Provider<MembershipRepository>(
  (ref) => MembershipRepository(),
);
final organizationContextProvider = FutureProvider<OrganizationContext>((
  ref,
) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return const OrganizationContext();
  return ref.watch(membershipRepositoryProvider).context();
});
final organizationTeamProvider =
    FutureProvider.family<OrganizationTeam, String>((ref, organizationId) {
      ref.watch(sessionProvider);
      return ref.watch(membershipRepositoryProvider).team(organizationId);
    });

/// Re-fetch the profile after a company switch. Account read caches are also
/// cleared because historic cache keys predate multi-organization membership.
Future<void> refreshMembership(WidgetRef ref) async {
  final account = supabase.auth.currentUser?.id;
  if (account != null) await invalidateAccountReadCaches(account);
  ref.invalidate(profileProvider);
  ref.invalidate(organizationContextProvider);
  ref.invalidate(organizationTeamProvider);
}
