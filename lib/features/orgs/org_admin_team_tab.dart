import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/features/orgs/org_admin_invite_sheet.dart';
import 'package:vortice_app/features/orgs/org_admin_member_card.dart';
import 'package:vortice_app/features/orgs/org_provider.dart';

class OrgAdminTeamTab extends ConsumerWidget {
  final String orgId;
  final String ownerProfileId;

  const OrgAdminTeamTab({
    super.key,
    required this.orgId,
    required this.ownerProfileId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final es = isSpanish(context);
    final membersAsync = ref.watch(orgMembersProvider(orgId));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                backgroundColor: context.appColors.surface,
                builder: (_) => OrgAdminInviteSheet(
                  orgId: orgId,
                  ownerProfileId: ownerProfileId,
                ),
              ),
              icon: const Icon(Icons.person_add_outlined),
              label: Text(
                es ? 'Invitar a un miembro' : 'Invite team member',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
        Expanded(
          child: membersAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => AppErrorState(
              error: error,
              onRetry: () => ref.invalidate(orgMembersProvider(orgId)),
            ),
            data: (members) {
              if (members.isEmpty) {
                return Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.people_outline,
                          size: 56,
                          color: context.appColors.textSecondary,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          es
                              ? 'Aún no hay miembros en el equipo.'
                              : 'No team members yet.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          es
                              ? 'Crea y comparte un código para invitar al primer miembro.'
                              : 'Create and share an invite code to add your first team member.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                );
              }
              return RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(orgMembersProvider(orgId));
                  await ref.read(orgMembersProvider(orgId).future);
                },
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: members.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => OrgAdminMemberCard(
                    profile: members[i],
                    orgId: orgId,
                    ownerProfileId: ownerProfileId,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
