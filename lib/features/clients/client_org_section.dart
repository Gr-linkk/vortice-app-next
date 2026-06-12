import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/clients/client_provider.dart';
import 'package:vortice_app/features/orgs/org_provider.dart';
import 'package:vortice_app/models/profile.dart';

class ClientOrgSection extends ConsumerWidget {
  final Profile client;

  const ClientOrgSection({super.key, required this.client});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orgId = client.orgId;

    if (orgId != null) {
      final orgAsync = ref.watch(orgByIdProvider(orgId));
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Organization',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 6),
          orgAsync.when(
            loading: () => const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            error: (_, __) => const Text('Could not load org',
                style: TextStyle(color: AppColors.error, fontSize: 13)),
            data: (org) => Row(
              children: [
                Expanded(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.business_outlined,
                            size: 16, color: AppColors.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            org?.name ?? 'Unknown',
                            style: const TextStyle(
                                color: AppColors.textPrimary, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined,
                      size: 18, color: AppColors.textSecondary),
                  tooltip: 'Rename',
                  onPressed: () => _showRenameOrgDialog(
                      context, ref, orgId, org?.name ?? ''),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Organization',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          onPressed: () => _showCreateOrgDialog(context, ref),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Create Organization'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.primary),
          ),
        ),
      ],
    );
  }

  void _showRenameOrgDialog(
      BuildContext context, WidgetRef ref, String orgId, String currentName) {
    final nameCtrl = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Organization'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(labelText: 'Organization name'),
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
              Navigator.pop(ctx);
              await ref
                  .read(orgControllerProvider.notifier)
                  .renameOrg(orgId, name);
              ref.invalidate(clientsProvider);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showCreateOrgDialog(BuildContext context, WidgetRef ref) {
    final nameCtrl = TextEditingController(text: client.fullName);
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
              Navigator.pop(ctx);
              final orgId = await ref
                  .read(orgControllerProvider.notifier)
                  .createOrg(name, client.id);
              if (orgId != null) {
                ref.invalidate(clientsProvider);
                ref.invalidate(currentUserOrgProvider);
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Organization "$name" created'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                }
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}
