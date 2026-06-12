import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/theme.dart';
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
    final membersAsync = ref.watch(orgMembersProvider(orgId));

    return Scaffold(
      body: membersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Text(
            err.toString(),
            style: const TextStyle(color: AppColors.error),
          ),
        ),
        data: (members) {
          if (members.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.people_outline,
                      size: 56, color: AppColors.textSecondary),
                  SizedBox(height: 12),
                  Text('No team members yet.',
                      style: TextStyle(color: AppColors.textSecondary)),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: members.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => OrgAdminMemberCard(
              profile: members[i],
              orgId: orgId,
              ownerProfileId: ownerProfileId,
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showInviteSheet(context, orgId, ownerProfileId),
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('Invite Team Member'),
        backgroundColor: AppColors.primary,
      ),
    );
  }

  void _showInviteSheet(
    BuildContext context,
    String orgId,
    String ownerProfileId,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => OrgAdminInviteSheet(
        orgId: orgId,
        ownerProfileId: ownerProfileId,
      ),
    );
  }
}
