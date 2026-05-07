import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/assets/asset_provider.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/invoices/invoice_provider.dart';
import 'package:vortice_app/features/org_codes/org_code_provider.dart';
import 'package:vortice_app/features/orgs/org_provider.dart';
import 'package:vortice_app/features/checklists/checklist_assignment_provider.dart';
import 'package:vortice_app/models/asset.dart';
import 'package:vortice_app/models/client_org.dart';
import 'package:vortice_app/models/invoice.dart';
import 'package:vortice_app/models/profile.dart';

class OrgAdminScreen extends ConsumerWidget {
  const OrgAdminScreen({super.key});

  void _showCreateOrgDialog(BuildContext context, WidgetRef ref) {
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
              await ref
                  .read(orgControllerProvider.notifier)
                  .createOrg(name, userId);
              ref.invalidate(currentUserOrgProvider);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orgAsync = ref.watch(currentUserOrgProvider);

    return orgAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (err, _) => Scaffold(
        appBar: AppBar(title: const Text('Organization')),
        body: Center(
          child: Text(err.toString(),
              style: const TextStyle(color: AppColors.error)),
        ),
      ),
      data: (org) {
        if (org == null) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Organization'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.logout),
                  onPressed: () =>
                      ref.read(authControllerProvider.notifier).signOut(),
                ),
              ],
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.business_outlined,
                        size: 56, color: AppColors.textSecondary),
                    const SizedBox(height: 16),
                    const Text('No organization found.',
                        style: TextStyle(color: AppColors.textSecondary)),
                    const SizedBox(height: 8),
                    const Text(
                      'Create a team workspace to invite operators/mechanics and assign vessel checklists.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: () => _showCreateOrgDialog(context, ref),
                      icon: const Icon(Icons.add_business_outlined),
                      label: const Text('Create Team Workspace'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return _OrgAdminBody(org: org);
      },
    );
  }
}

class _OrgAdminBody extends ConsumerWidget {
  final ClientOrg org;
  const _OrgAdminBody({required this.org});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 4, // Team | Fleet | Checklists | Invoices
      child: Scaffold(
        appBar: AppBar(
          title: Text(org.name),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () =>
                  ref.read(authControllerProvider.notifier).signOut(),
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(icon: Icon(Icons.people_outline), text: 'Team'),
              Tab(icon: Icon(Icons.directions_boat_outlined), text: 'Fleet'),
              Tab(icon: Icon(Icons.checklist_outlined), text: 'Checklists'),
              Tab(icon: Icon(Icons.receipt_long_outlined), text: 'Invoices'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _TeamTab(orgId: org.id),
            _FleetTab(ownerProfileId: org.ownerProfileId),
            _ChecklistsTab(orgId: org.id),
            const _InvoicesTab(),
          ],
        ),
      ),
    );
  }
}

// ── Team Tab ─────────────────────────────────────────────────────────────────

class _TeamTab extends ConsumerWidget {
  final String orgId;
  const _TeamTab({required this.orgId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(orgMembersProvider(orgId));

    return Scaffold(
      body: membersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Text(err.toString(),
              style: const TextStyle(color: AppColors.error)),
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
            itemBuilder: (_, i) => _MemberCard(
              profile: members[i],
              orgId: orgId,
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showInviteSheet(context, ref, orgId),
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('Invite Team Member'),
        backgroundColor: AppColors.primary,
      ),
    );
  }

  void _showInviteSheet(BuildContext context, WidgetRef ref, String orgId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _InviteSheet(orgId: orgId),
    );
  }
}

class _MemberCard extends ConsumerWidget {
  final Profile profile;
  final String orgId;
  const _MemberCard({required this.profile, required this.orgId});

  Color _roleColor() => switch (profile.role) {
        UserRole.clientMechanic => AppColors.primary,
        UserRole.clientOperator => AppColors.warning,
        UserRole.clientAdmin => AppColors.success,
        _ => AppColors.textSecondary,
      };

  String _roleLabel() => switch (profile.role) {
        UserRole.clientMechanic => 'Mechanic',
        UserRole.clientOperator => 'Operator',
        UserRole.clientAdmin => 'Admin',
        _ => profile.role.name,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLoading = ref.watch(orgControllerProvider).isLoading;
    final color = _roleColor();

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
            backgroundColor: color.withOpacity(0.15),
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
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _roleLabel(),
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

// ── Invite Sheet ──────────────────────────────────────────────────────────────

class _InviteSheet extends ConsumerStatefulWidget {
  final String orgId;
  const _InviteSheet({required this.orgId});

  @override
  ConsumerState<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends ConsumerState<_InviteSheet> {
  String _selectedRole = 'client_mechanic';
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendInvite() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() => _submitting = true);

    final code = OrgCodeController.generateCode();
    final success =
        await ref.read(orgCodeControllerProvider.notifier).createCode(
              code: code,
              intendedRole: _selectedRole,
              maxUses: 1,
              singleUse: true,
              orgId: widget.orgId,
              notes:
                  'Invite for ${_nameCtrl.text.trim()} (${_emailCtrl.text.trim()})',
              expiresAt: DateTime.now().add(const Duration(days: 7)),
            );

    setState(() => _submitting = false);

    if (!mounted) return;
    if (success) {
      Navigator.pop(context);
      _showCodeDialog(code);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to create invite code. Try again.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _showCodeDialog(String code) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Invite Code Created'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Share this code with your team member to register:',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primary.withOpacity(0.5)),
              ),
              child: Text(
                code,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Expires in 7 days. Single-use.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Invite Team Member',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary),
          ),
          const SizedBox(height: 16),
          // Role picker
          const Text('Role',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _RoleChip(
                  label: 'Mechanic',
                  selected: _selectedRole == 'client_mechanic',
                  onTap: () =>
                      setState(() => _selectedRole = 'client_mechanic'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _RoleChip(
                  label: 'Operator',
                  selected: _selectedRole == 'client_operator',
                  onTap: () =>
                      setState(() => _selectedRole = 'client_operator'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Name',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email (for reference)',
              prefixIcon: Icon(Icons.email_outlined),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _submitting ? null : _sendInvite,
            icon: _submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.send),
            label: const Text('Send Invite'),
          ),
        ],
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _RoleChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withOpacity(0.15)
              : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.cardBorder,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected ? AppColors.primary : AppColors.textSecondary,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

// ── Fleet Tab ─────────────────────────────────────────────────────────────────

class _FleetTab extends ConsumerWidget {
  final String ownerProfileId;
  const _FleetTab({required this.ownerProfileId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assetsAsync = ref.watch(assetsProvider);

    return assetsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(
        child: Text(err.toString(),
            style: const TextStyle(color: AppColors.error)),
      ),
      data: (assets) {
        // Filter assets belonging to the org's owner
        final orgAssets =
            assets.where((a) => a.clientId == ownerProfileId).toList();

        if (orgAssets.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.directions_boat_outlined,
                    size: 56, color: AppColors.textSecondary),
                SizedBox(height: 12),
                Text('No fleet assets.',
                    style: TextStyle(color: AppColors.textSecondary)),
              ],
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: orgAssets.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) => _AssetCard(asset: orgAssets[i]),
        );
      },
    );
  }
}

class _AssetCard extends StatelessWidget {
  final Asset asset;
  const _AssetCard({required this.asset});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.directions_boat, color: AppColors.primary, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  asset.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                    fontSize: 14,
                  ),
                ),
                if (asset.model != null)
                  Text(
                    asset.model!,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                  ),
              ],
            ),
          ),
          const Icon(Icons.lock_outline,
              color: AppColors.textSecondary, size: 16),
        ],
      ),
    );
  }
}

// ── Work Orders Tab ───────────────────────────────────────────────────────────

// ── Checklists Tab ──────────────────────────────────────────────────

class _ChecklistsTab extends ConsumerWidget {
  final String orgId;
  const _ChecklistsTab({required this.orgId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assignmentsAsync = ref.watch(orgChecklistAssignmentsProvider);
    final profile = ref.watch(profileProvider).valueOrNull;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAssignSheet(context, ref, orgId, profile),
        icon: const Icon(Icons.add),
        label: const Text('Assign Checklist'),
      ),
      body: assignmentsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
            child: Text(err.toString(),
                style: const TextStyle(color: AppColors.error))),
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
              final statusColor = switch (status) {
                'completed' => AppColors.success,
                'in_progress' => AppColors.warning,
                'cancelled' => AppColors.textSecondary,
                _ => AppColors.primary,
              };
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        (isPM ? AppColors.primary : AppColors.warning)
                            .withOpacity(0.15),
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
                      color: statusColor.withOpacity(0.15),
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
      BuildContext context, WidgetRef ref, String orgId, profile) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) =>
          _AssignChecklistSheet(orgId: orgId, assignedBy: profile?.id ?? ''),
    );
  }
}

class _AssignChecklistSheet extends ConsumerStatefulWidget {
  final String orgId;
  final String assignedBy;
  const _AssignChecklistSheet({required this.orgId, required this.assignedBy});

  @override
  ConsumerState<_AssignChecklistSheet> createState() =>
      _AssignChecklistSheetState();
}

class _AssignChecklistSheetState extends ConsumerState<_AssignChecklistSheet> {
  String? _selectedTemplateId;
  String? _selectedMemberId;
  String? _selectedAssetId;
  bool _submitting = false;
  String _checklistType = 'pm'; // pm or operator_daily

  @override
  Widget build(BuildContext context) {
    final pmAsync = ref.watch(pmChecklistTemplatesProvider);
    final preOpAsync = ref.watch(preOpChecklistTemplatesProvider);
    final membersAsync = ref.watch(orgMembersProvider(widget.orgId));
    final assetsAsync = ref.watch(operatorScopedAssetsProvider);

    final templates = _checklistType == 'pm' ? pmAsync : preOpAsync;

    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Assign Checklist',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),

          // Type toggle
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'pm', label: Text('PM Checklist')),
              ButtonSegment(value: 'operator_daily', label: Text('Pre-Op')),
            ],
            selected: {_checklistType},
            onSelectionChanged: (v) => setState(() {
              _checklistType = v.first;
              _selectedTemplateId = null;
              _selectedMemberId = null;
            }),
          ),
          const SizedBox(height: 16),

          // Template picker
          templates.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, __) => const SizedBox.shrink(),
            data: (list) => DropdownButtonFormField<String>(
              value: _selectedTemplateId,
              decoration:
                  const InputDecoration(labelText: 'Checklist template'),
              dropdownColor: AppColors.surfaceVariant,
              items: list
                  .map((t) => DropdownMenuItem(
                        value: t['id'] as String,
                        child: Text(
                          t['name'] as String? ?? '',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _selectedTemplateId = v),
            ),
          ),
          const SizedBox(height: 12),

          // Member picker (filtered by role)
          membersAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, __) => const SizedBox.shrink(),
            data: (members) {
              final filtered = members
                  .where((m) => _checklistType == 'pm'
                      ? m.role == UserRole.clientMechanic
                      : m.role == UserRole.clientOperator ||
                          m.role == UserRole.operator)
                  .toList();
              return DropdownButtonFormField<String>(
                value: _selectedMemberId,
                decoration: InputDecoration(
                    labelText: _checklistType == 'pm'
                        ? 'Assign to mechanic'
                        : 'Assign to operator'),
                dropdownColor: AppColors.surfaceVariant,
                items: filtered
                    .map((m) => DropdownMenuItem(
                          value: m.id,
                          child: Text(m.fullName),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _selectedMemberId = v),
              );
            },
          ),
          const SizedBox(height: 12),

          // Asset picker
          assetsAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, __) => const SizedBox.shrink(),
            data: (assets) => DropdownButtonFormField<String>(
              value: _selectedAssetId,
              decoration: const InputDecoration(labelText: 'Vessel (optional)'),
              dropdownColor: AppColors.surfaceVariant,
              items: [
                const DropdownMenuItem(value: null, child: Text('No vessel')),
                ...assets.map((a) => DropdownMenuItem(
                      value: a.id,
                      child: Text(a.name),
                    )),
              ],
              onChanged: (v) => setState(() => _selectedAssetId = v),
            ),
          ),
          const SizedBox(height: 24),

          ElevatedButton(
            onPressed: _submitting ||
                    _selectedTemplateId == null ||
                    _selectedMemberId == null
                ? null
                : _submit,
            child: _submitting
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Assign'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      await ChecklistAssignmentController.assign(
        templateId: _selectedTemplateId!,
        assignedTo: _selectedMemberId!,
        assignedBy: widget.assignedBy,
        orgId: widget.orgId,
        assetId: _selectedAssetId,
      );
      ref.invalidate(orgChecklistAssignmentsProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e.toString()), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

// ── Invoices Tab ──────────────────────────────────────────────────────────────

class _InvoicesTab extends ConsumerWidget {
  const _InvoicesTab();

  Color _statusColor(InvoiceStatus s) => switch (s) {
        InvoiceStatus.paid => AppColors.success,
        InvoiceStatus.sent => AppColors.warning,
        InvoiceStatus.draft => AppColors.textSecondary,
        InvoiceStatus.voided => AppColors.error,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoicesAsync = ref.watch(invoicesProvider);

    return invoicesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(
        child: Text(err.toString(),
            style: const TextStyle(color: AppColors.error)),
      ),
      data: (invoices) {
        if (invoices.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.receipt_long_outlined,
                    size: 56, color: AppColors.textSecondary),
                SizedBox(height: 12),
                Text('No invoices yet.',
                    style: TextStyle(color: AppColors.textSecondary)),
              ],
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: invoices.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final inv = invoices[i];
            final color = _statusColor(inv.status);
            return InkWell(
              onTap: () => context.push('/client/invoices/${inv.id}'),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.receipt_long_outlined,
                        color: AppColors.primary, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            inv.invoiceNumber,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                              fontSize: 13,
                            ),
                          ),
                          if (inv.totalUsd != null)
                            Text(
                              '\$${inv.totalUsd!.toStringAsFixed(2)} USD',
                              style: const TextStyle(
                                  color: AppColors.textSecondary, fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        inv.status.name.toUpperCase(),
                        style: TextStyle(
                          color: color,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right,
                        color: AppColors.textSecondary, size: 20),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
