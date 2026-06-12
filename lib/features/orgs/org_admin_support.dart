import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/orgs/org_provider.dart';
import 'package:vortice_app/models/client_capability.dart';
import 'package:vortice_app/models/invoice.dart';
import 'package:vortice_app/models/profile.dart';

Color orgAdminMemberRoleColor(UserRole role) => switch (role) {
      UserRole.clientMechanic => AppColors.primary,
      UserRole.clientOperator => AppColors.warning,
      UserRole.clientAdmin => AppColors.success,
      _ => AppColors.textSecondary,
    };

String orgAdminMemberRoleLabel(UserRole role) => switch (role) {
      UserRole.clientMechanic => 'Mechanic',
      UserRole.clientOperator => 'Operator',
      UserRole.clientAdmin => 'Admin',
      _ => role.name,
    };

ClientCapability? orgAdminCapabilityForRole(UserRole role) => switch (role) {
      UserRole.clientMechanic => ClientCapability.pmChecklists,
      UserRole.clientOperator ||
      UserRole.operator =>
        ClientCapability.operationalChecklists,
      _ => null,
    };

bool isOrgMemberWorkflowDisabled({
  required UserRole role,
  required ClientCapabilitySwitchboard capabilities,
}) {
  final roleCapability = orgAdminCapabilityForRole(role);
  return roleCapability != null && !capabilities.isEnabled(roleCapability);
}

ClientCapability requiredCapabilityForInviteRole(String role) =>
    role == 'client_mechanic'
        ? ClientCapability.pmChecklists
        : ClientCapability.operationalChecklists;

Color orgAdminInvoiceStatusColor(InvoiceStatus status) => switch (status) {
      InvoiceStatus.paid => AppColors.success,
      InvoiceStatus.sent => AppColors.warning,
      InvoiceStatus.draft => AppColors.textSecondary,
      InvoiceStatus.voided => AppColors.error,
    };

Color orgAdminChecklistAssignmentStatusColor(String status) => switch (status) {
      'completed' => AppColors.success,
      'in_progress' => AppColors.warning,
      'cancelled' => AppColors.textSecondary,
      _ => AppColors.primary,
    };

bool isMemberEligibleForChecklistType(Profile member, String checklistType) =>
    checklistType == 'pm'
        ? member.role == UserRole.clientMechanic
        : member.role == UserRole.clientOperator ||
            member.role == UserRole.operator;

List<Profile> filterMembersForChecklistType(
  List<Profile> members,
  String checklistType,
) =>
    members
        .where((m) => isMemberEligibleForChecklistType(m, checklistType))
        .toList();

void showCreateOrgDialog(BuildContext context, WidgetRef ref) {
  final nameCtrl = TextEditingController();
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Create Organization'),
      content: TextField(
        controller: nameCtrl,
        decoration: const InputDecoration(
          labelText: 'Organization name',
          hintText: 'e.g. Pacific Marine Services',
        ),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () async {
            final name = nameCtrl.text.trim();
            if (name.isEmpty) return;
            final userId = supabase.auth.currentUser?.id;
            if (userId == null) return;
            Navigator.pop(ctx);
            await ref.read(orgControllerProvider.notifier).createOrg(name, userId);
            ref.invalidate(currentUserOrgProvider);
          },
          child: const Text('Create'),
        ),
      ],
    ),
  );
}

