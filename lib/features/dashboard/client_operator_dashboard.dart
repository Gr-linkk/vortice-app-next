import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/assets/client_team_asset_access.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/checklists/checklist_assignment_provider.dart';
import 'package:vortice_app/features/clients/client_capability_gate.dart';
import 'package:vortice_app/models/client_capability.dart';

// ── Provider: assets assigned to this client_operator's org ─────────────────

final clientOperatorAssignedAssetsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final assets = await ref.watch(currentClientFleetAssetsProvider.future);
  return assets.map(clientTeamAssetRow).toList();
});

// ── Provider: recent pre-departure checklist runs for this operator ──────────

final clientOperatorRecentRunsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return [];

  final data = await supabase
      .from(AppConstants.tOperatorChecklistRuns)
      .select('id, run_type, completed_at, assets(name)')
      .eq('operator_id', userId)
      .order('created_at', ascending: false)
      .limit(10);

  return List<Map<String, dynamic>>.from(data as List);
});

// ── Client Operator Dashboard ─────────────────────────────────────────────────

class ClientOperatorDashboard extends ConsumerWidget {
  const ClientOperatorDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).valueOrNull;
    final assetsAsync = ref.watch(clientOperatorAssignedAssetsProvider);
    final runsAsync = ref.watch(clientOperatorRecentRunsProvider);
    final operationalChecklistsAllowedAsync =
        ref.watch(clientCapabilityGateProvider((
      clientId: null,
      capability: ClientCapability.operationalChecklists,
    )));
    final showOperationalChecklists =
        operationalChecklistsAllowedAsync.valueOrNull ?? false;
    final assignedChecklistsAsync = showOperationalChecklists
        ? ref.watch(myChecklistAssignmentsProvider)
        : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          profile?.fullName.split(' ').first != null
              ? 'Hi, ${profile!.fullName.split(' ').first}'
              : 'My Dashboard',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () =>
                ref.read(authControllerProvider.notifier).signOut(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(clientOperatorAssignedAssetsProvider);
          ref.invalidate(clientOperatorRecentRunsProvider);
          ref.invalidate(myChecklistAssignmentsProvider);
          ref.invalidate(clientCapabilityGateProvider((
            clientId: null,
            capability: ClientCapability.operationalChecklists,
          )));
        },
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            // ── 0. Assigned Pre-Op Checklists (from client admin) ──────────
            if (showOperationalChecklists)
              assignedChecklistsAsync!.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (assignments) {
                  if (assignments.isEmpty) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SectionHeader(
                        title: 'Assigned Checklists (${assignments.length})',
                        icon: Icons.assignment_outlined,
                      ),
                      ...assignments.map((a) {
                        final template =
                            a['checklist_templates'] as Map<String, dynamic>?;
                        final asset = a['assets'] as Map<String, dynamic>?;
                        final status = a['status'] as String? ?? 'pending';
                        final statusColor = switch (status) {
                          'completed' => AppColors.success,
                          'in_progress' => AppColors.warning,
                          _ => AppColors.primary,
                        };
                        return Card(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor:
                                  AppColors.warning.withValues(alpha: 0.1),
                              child: const Icon(Icons.checklist_outlined,
                                  size: 18, color: AppColors.warning),
                            ),
                            title: Text(
                              template?['name'] as String? ?? 'Checklist',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: asset?['name'] != null
                                ? Text(asset!['name'] as String,
                                    style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 12))
                                : null,
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
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
                            onTap: () async {
                              if (status == 'pending') {
                                await ChecklistAssignmentController
                                    .markInProgress(a['id'] as String);
                                ref.invalidate(myChecklistAssignmentsProvider);
                                ref.invalidate(clientCapabilityGateProvider((
                                  clientId: null,
                                  capability:
                                      ClientCapability.operationalChecklists,
                                )));
                              }
                              final query = <String, String>{
                                if (asset?['id'] != null)
                                  'assetId': asset!['id'] as String,
                                if (template?['id'] != null)
                                  'templateId': template!['id'] as String,
                              };
                              if (context.mounted) {
                                context.push(
                                  Uri(
                                    path: '/operator/checklist',
                                    queryParameters:
                                        query.isEmpty ? null : query,
                                  ).toString(),
                                );
                              }
                            },
                          ),
                        );
                      }),
                      const SizedBox(height: 8),
                    ],
                  );
                },
              ),

            // ── 1. Pre-Departure Checklists ───────────────────────────
            if (showOperationalChecklists) ...[
              const _SectionHeader(
                title: 'Pre-Departure Checklists',
                icon: Icons.checklist_outlined,
              ),
              assetsAsync.when(
                loading: () => const _LoadingTile(),
                error: (err, _) => _ErrorTile(message: err.toString()),
                data: (assets) {
                  if (assets.isEmpty) {
                    return const _EmptyState(
                      icon: Icons.directions_boat_outlined,
                      message: 'No assets assigned.',
                    );
                  }
                  return Column(
                    children: assets
                        .map((asset) => _AssetChecklistCard(asset: asset))
                        .toList(),
                  );
                },
              ),
            ],

            // ── 2. Flag an Issue ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
              child: ElevatedButton.icon(
                onPressed: () => context.push('/operator/flags'),
                icon: const Icon(Icons.flag_outlined),
                label: const Text('Flag an Issue'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: AppColors.warning,
                  foregroundColor: Colors.white,
                ),
              ),
            ),

            // ── 3. Recent Checks ──────────────────────────────────────
            const _SectionHeader(
              title: 'Recent Checks',
              icon: Icons.history_outlined,
            ),
            runsAsync.when(
              loading: () => const _LoadingTile(),
              error: (err, _) => _ErrorTile(message: err.toString()),
              data: (runs) {
                if (runs.isEmpty) {
                  return const _EmptyState(
                    icon: Icons.history_outlined,
                    message: 'No completed checks yet.',
                  );
                }
                return Column(
                  children:
                      runs.map((run) => _RecentRunTile(run: run)).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ── Asset Checklist Card ──────────────────────────────────────────────────────

class _AssetChecklistCard extends StatelessWidget {
  final Map<String, dynamic> asset;
  const _AssetChecklistCard({required this.asset});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Row(
          children: [
            const Icon(Icons.directions_boat,
                color: AppColors.primary, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    asset['name'] as String? ?? '—',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                      fontSize: 14,
                    ),
                  ),
                  if (asset['model'] != null)
                    Text(
                      asset['model'] as String,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: () =>
                  context.push('/operator/checklist?assetId=${asset['id']}'),
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                textStyle:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              child: const Text('Start Checklist'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Recent Run Tile ───────────────────────────────────────────────────────────

class _RecentRunTile extends StatelessWidget {
  final Map<String, dynamic> run;
  const _RecentRunTile({required this.run});

  @override
  Widget build(BuildContext context) {
    final assetName =
        (run['assets'] as Map<String, dynamic>?)?['name'] as String? ?? '—';
    final completedAt = run['completed_at'] != null
        ? DateTime.tryParse(run['completed_at'] as String)
        : null;
    final dateStr = completedAt != null
        ? DateFormat('MMM d, yyyy').format(completedAt.toLocal())
        : 'In progress';
    final runType = run['run_type'] as String? ?? 'pre_departure';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_outline,
                  color: AppColors.success, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    assetName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    dateStr,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                runType.replaceAll('_', ' ').toUpperCase(),
                style: const TextStyle(
                  color: AppColors.success,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 18),
          const SizedBox(width: 8),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _LoadingTile extends StatelessWidget {
  const _LoadingTile();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _ErrorTile extends StatelessWidget {
  final String message;
  const _ErrorTile({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(message,
          style: const TextStyle(color: AppColors.error, fontSize: 13)),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: const Border.fromBorderSide(
              BorderSide(color: AppColors.cardBorder)),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.textSecondary, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
