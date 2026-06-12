import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/clients/client_capability_provider.dart';
import 'package:vortice_app/features/orgs/org_admin_support.dart';
import 'package:vortice_app/features/orgs/org_provider.dart';
import 'package:vortice_app/models/profile.dart';

class OrgAdminMemberCard extends ConsumerWidget {
  final Profile profile;
  final String orgId;
  final String ownerProfileId;

  const OrgAdminMemberCard({
    super.key,
    required this.profile,
    required this.orgId,
    required this.ownerProfileId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLoading = ref.watch(orgControllerProvider).isLoading;
    final capabilities =
        ref.watch(clientCapabilitiesProvider(ownerProfileId)).valueOrNull;
    final roleCapability = orgAdminCapabilityForRole(profile.role);
    final workflowDisabled = capabilities != null &&
        isOrgMemberWorkflowDisabled(
          role: profile.role,
          capabilities: capabilities,
        );
    final color = orgAdminMemberRoleColor(profile.role);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.15),
            child: Icon(Icons.person_outline, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.fullName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  profile.email,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                if (workflowDisabled && roleCapability != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${roleCapability.label} disabled for this client',
                    style: const TextStyle(
                      color: AppColors.warning,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              orgAdminMemberRoleLabel(profile.role),
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: isLoading
                ? null
                : () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Remove Member'),
                        content:
                            Text('Remove ${profile.fullName} from this org?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.error),
                            child: const Text('Remove'),
                          ),
                        ],
                      ),
                    );
                    if (confirm != true) return;
                    await ref
                        .read(orgControllerProvider.notifier)
                        .removeMember(profile.id, orgId: orgId);
                  },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}
