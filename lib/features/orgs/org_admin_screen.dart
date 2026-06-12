import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/orgs/org_admin_body.dart';
import 'package:vortice_app/features/orgs/org_admin_support.dart';
import 'package:vortice_app/features/orgs/org_provider.dart';

class OrgAdminScreen extends ConsumerWidget {
  const OrgAdminScreen({super.key});

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
          child: Text(
            err.toString(),
            style: const TextStyle(color: AppColors.error),
          ),
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
                      onPressed: () => showCreateOrgDialog(context, ref),
                      icon: const Icon(Icons.add_business_outlined),
                      label: const Text('Create Team Workspace'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return OrgAdminBody(org: org);
      },
    );
  }
}
