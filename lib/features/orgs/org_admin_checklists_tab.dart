import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/checklists/checklist_assignment_provider.dart';
import 'package:vortice_app/features/orgs/org_admin_assign_checklist_sheet.dart';
import 'package:vortice_app/features/orgs/org_admin_support.dart';

class OrgAdminChecklistsTab extends ConsumerWidget {
  final String orgId;

  const OrgAdminChecklistsTab({super.key, required this.orgId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assignmentsAsync = ref.watch(orgChecklistAssignmentsProvider);
    final profile = ref.watch(profileProvider).valueOrNull;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAssignSheet(context, orgId, profile?.id ?? ''),
        icon: const Icon(Icons.add),
        label: const Text('Assign Checklist'),
      ),
      body: assignmentsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Text(
            err.toString(),
            style: const TextStyle(color: AppColors.error),
          ),
        ),
        data: (assignments) {
          if (assignments.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.checklist_outlined,
                      size: 56, color: AppColors.textSecondary),
                  SizedBox(height: 12),
                  Text('No checklists assigned yet.',
                      style: TextStyle(color: AppColors.textSecondary)),
                  SizedBox(height: 4),
                  Text('Tap + to assign a PM or pre-op checklist to your team.',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: assignments.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final a = assignments[i];
              final template =
                  a['checklist_templates'] as Map<String, dynamic>?;
              final asset = a['assets'] as Map<String, dynamic>?;
              final assignee = a['assignee'] as Map<String, dynamic>?;
              final status = a['status'] as String? ?? 'pending';
              final isPM = template?['checklist_type'] == 'pm';
              final statusColor =
                  orgAdminChecklistAssignmentStatusColor(status);
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        (isPM ? AppColors.primary : AppColors.warning)
                            .withValues(alpha: 0.15),
                    child: Icon(
                      isPM ? Icons.build_outlined : Icons.checklist_outlined,
                      color: isPM ? AppColors.primary : AppColors.warning,
                      size: 18,
                    ),
                  ),
                  title: Text(
                    template?['name'] as String? ?? 'Checklist',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    [
                      if (assignee?['full_name'] != null)
                        assignee!['full_name'] as String,
                      if (asset?['name'] != null) asset!['name'] as String,
                    ].join(' • '),
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                  ),
                  trailing: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      status.replaceAll('_', ' ').toUpperCase(),
                      style: TextStyle(
                          color: statusColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showAssignSheet(
    BuildContext context,
    String orgId,
    String assignedBy,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => OrgAdminAssignChecklistSheet(
        orgId: orgId,
        assignedBy: assignedBy,
      ),
    );
  }
}
