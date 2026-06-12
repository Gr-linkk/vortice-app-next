import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/clients/client_capability_provider.dart';
import 'package:vortice_app/features/org_codes/org_code_provider.dart';
import 'package:vortice_app/features/orgs/org_admin_support.dart';
import 'package:vortice_app/models/client_capability.dart';

class OrgAdminInviteSheet extends ConsumerStatefulWidget {
  final String orgId;
  final String ownerProfileId;

  const OrgAdminInviteSheet({
    super.key,
    required this.orgId,
    required this.ownerProfileId,
  });

  @override
  ConsumerState<OrgAdminInviteSheet> createState() =>
      _OrgAdminInviteSheetState();
}

class _OrgAdminInviteSheetState extends ConsumerState<OrgAdminInviteSheet> {
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

  Future<void> _sendInvite(ClientCapabilitySwitchboard switchboard) async {
    if (_nameCtrl.text.trim().isEmpty) return;

    final requiredCapability = requiredCapabilityForInviteRole(_selectedRole);
    if (!switchboard.isEnabled(requiredCapability)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${requiredCapability.label} must be enabled before inviting this role.',
          ),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

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
      final error = ref.read(orgCodeControllerProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              error?.toString() ?? 'Failed to create invite code. Try again.'),
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
                border:
                    Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
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
    final capabilitiesAsync =
        ref.watch(clientCapabilitiesProvider(widget.ownerProfileId));

    return capabilitiesAsync.when(
      loading: () => Padding(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
        child: const Center(child: CircularProgressIndicator()),
      ),
      error: (err, _) => Padding(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
        child: Text(
          err.toString(),
          style: const TextStyle(color: AppColors.error),
        ),
      ),
      data: (switchboard) {
        final mechanicEnabled =
            switchboard.isEnabled(ClientCapability.pmChecklists);
        final operatorEnabled =
            switchboard.isEnabled(ClientCapability.operationalChecklists);
        final selectedCapability =
            requiredCapabilityForInviteRole(_selectedRole);
        final selectedEnabled = switchboard.isEnabled(selectedCapability);

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
              const Text('Role',
                  style:
                      TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OrgAdminRoleChip(
                      label: 'Mechanic',
                      selected: _selectedRole == 'client_mechanic',
                      enabled: mechanicEnabled,
                      onTap: mechanicEnabled
                          ? () =>
                              setState(() => _selectedRole = 'client_mechanic')
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OrgAdminRoleChip(
                      label: 'Operator',
                      selected: _selectedRole == 'client_operator',
                      enabled: operatorEnabled,
                      onTap: operatorEnabled
                          ? () =>
                              setState(() => _selectedRole = 'client_operator')
                          : null,
                    ),
                  ),
                ],
              ),
              if (!mechanicEnabled || !operatorEnabled) ...[
                const SizedBox(height: 8),
                Text(
                  [
                    if (!mechanicEnabled)
                      'Enable PM / Mechanic Checklists to invite mechanics.',
                    if (!operatorEnabled)
                      'Enable Operational Checklists to invite operators.',
                  ].join('\n'),
                  style: const TextStyle(
                    color: AppColors.warning,
                    fontSize: 12,
                  ),
                ),
              ],
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
                onPressed: _submitting || !selectedEnabled
                    ? null
                    : () => _sendInvite(switchboard),
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
      },
    );
  }
}

class OrgAdminRoleChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  const OrgAdminRoleChip({
    super.key,
    required this.label,
    required this.selected,
    this.enabled = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: !enabled
              ? AppColors.surfaceVariant.withValues(alpha: 0.55)
              : selected
                  ? AppColors.primary.withValues(alpha: 0.15)
                  : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: !enabled
                ? AppColors.cardBorder.withValues(alpha: 0.4)
                : selected
                    ? AppColors.primary
                    : AppColors.cardBorder,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: !enabled
                ? AppColors.textSecondary.withValues(alpha: 0.5)
                : selected
                    ? AppColors.primary
                    : AppColors.textSecondary,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
