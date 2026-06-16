import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/assets/asset_provider.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/clients/client_capability_gate.dart';
import 'package:vortice_app/features/notifications/notification_provider.dart';
import 'package:vortice_app/features/operator/operator_runs_provider.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/models/asset.dart';
import 'package:vortice_app/models/client_capability.dart';

// ── Providers for client-visible operator data ─────────────────────────────

final clientPreTripRunsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final assets = await ref.watch(visibleAssetsProvider.future);
  final assetIds = assets.map((asset) => asset.id).toList();
  if (assetIds.isEmpty) return [];

  final data = await supabase
      .from(AppConstants.tOperatorChecklistRuns)
      .select('id, asset_id, run_type, completed_at, assets(name)')
      .eq('run_type', 'pre_departure')
      .inFilter('asset_id', assetIds)
      .order('completed_at', ascending: false)
      .limit(5);
  return List<Map<String, dynamic>>.from(data as List);
});

// clientFlaggedIssuesProvider is defined in operator_runs_provider.dart
// so it can be invalidated from the maintenance flag screen.

class ClientDashboard extends ConsumerWidget {
  const ClientDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final profile = ref.watch(profileProvider).valueOrNull;
    final assetsAsync = ref.watch(visibleAssetsProvider);
    final operationalChecklistsAllowedAsync =
        ref.watch(clientCapabilityGateProvider((
      clientId: null,
      capability: ClientCapability.operationalChecklists,
    )));
    final showOperationalChecklists =
        operationalChecklistsAllowedAsync.valueOrNull ?? false;
    final preTripAsync =
        showOperationalChecklists ? ref.watch(clientPreTripRunsProvider) : null;
    final flagsAsync = ref.watch(clientFlaggedIssuesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.clientDashboardTitle),
        actions: [
          const _BellButton(route: '/client/notifications'),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () =>
                ref.read(authControllerProvider.notifier).signOut(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(visibleAssetsProvider);
          ref.invalidate(clientPreTripRunsProvider);
          ref.invalidate(clientFlaggedIssuesProvider);
        },
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
              child: Text(
                l10n.greeting(profile?.fullName.split(' ').first ?? ''),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(
                DateFormat('EEEE, MMMM d').format(DateTime.now()),
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: _KpiCard(
                label: l10n.totalAssets,
                value: assetsAsync.when(
                  data: (list) => list.length.toString(),
                  loading: () => '—',
                  error: (_, __) => '!',
                ),
                icon: Icons.directions_boat,
                color: AppColors.primary,
                onTap: () => context.go('/client/assets'),
              ),
            ),
            // My fleet
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(l10n.myFleet,
                      style: Theme.of(context).textTheme.titleMedium),
                  TextButton(
                    onPressed: () => context.go('/client/assets'),
                    child: Text(l10n.viewAll),
                  ),
                ],
              ),
            ),
            assetsAsync.when(
              loading: () => const Center(
                  child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              )),
              error: (err, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text(err.toString(),
                    style: const TextStyle(color: AppColors.error)),
              ),
              data: (assets) {
                final active = assets.take(4).toList();

                if (active.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(child: Text(l10n.noAssets)),
                  );
                }
                return SizedBox(
                  height: 110,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: active.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (_, i) => _AssetChip(asset: active[i]),
                  ),
                );
              },
            ),
            if (showOperationalChecklists) ...[
              // ── Pre-Trip Checks ──────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                child: Text(l10n.recentPreTripChecks,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              preTripAsync!.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (runs) {
                  if (runs.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text(l10n.noRecentChecks,
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 13)),
                    );
                  }
                  return Column(
                    children: runs.map((run) {
                      final assetName = (run['assets']
                              as Map<String, dynamic>?)?['name'] as String? ??
                          '—';
                      final completedAt = run['completed_at'] != null
                          ? DateTime.tryParse(run['completed_at'] as String)
                          : null;
                      return Card(
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: AppColors.surfaceVariant,
                            child: Icon(Icons.checklist_rtl,
                                color: AppColors.success, size: 18),
                          ),
                          title: Text(assetName,
                              style: Theme.of(context).textTheme.titleSmall),
                          subtitle: Text(
                            completedAt != null
                                ? '${completedAt.toLocal()}'.split('.').first
                                : '—',
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 11),
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.success.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              l10n.preDeparture.toUpperCase(),
                              style: const TextStyle(
                                  color: AppColors.success,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ],

            // ── Flagged Issues ───────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(l10n.flaggedIssues,
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            flagsAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (flags) {
                if (flags.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(l10n.noFlaggedIssues,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 13)),
                  );
                }
                return Column(
                  children: flags.map((flag) {
                    final assetName = (flag['assets']
                            as Map<String, dynamic>?)?['name'] as String? ??
                        '—';
                    final isUrgent = flag['severity'] == 'urgent';
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              (isUrgent ? AppColors.error : AppColors.warning)
                                  .withValues(alpha: 0.15),
                          child: Icon(
                            isUrgent ? Icons.warning : Icons.flag,
                            color:
                                isUrgent ? AppColors.error : AppColors.warning,
                            size: 18,
                          ),
                        ),
                        title: Text(
                          flag['description'] as String? ?? '—',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        subtitle: Text(assetName,
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 12)),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.warning.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'OPEN',
                            style: TextStyle(
                                color: AppColors.warning,
                                fontSize: 10,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AssetChip extends StatelessWidget {
  final Asset asset;
  const _AssetChip({required this.asset});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push('/client/assets/${asset.id}'),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 140,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: const Border.fromBorderSide(
              BorderSide(color: AppColors.cardBorder)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.directions_boat,
                color: AppColors.primary, size: 28),
            const SizedBox(height: 8),
            Text(
              asset.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (asset.model != null)
              Text(
                asset.model!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.textSecondary),
              ),
          ],
        ),
      ),
    );
  }
}

// ── KPI card ─────────────────────────────────────────────────────────────────

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: const Border.fromBorderSide(
              BorderSide(color: AppColors.cardBorder)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 10),
            Text(
              value,
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(color: color, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(label,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

// ── Bell icon with unread badge ──────────────────────────────────────────────

class _BellButton extends ConsumerWidget {
  final String route;
  const _BellButton({required this.route});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadCountProvider);
    return Stack(
      children: [
        IconButton(
          icon: const Icon(Icons.notifications_outlined),
          onPressed: () => context.push(route),
          tooltip: AppLocalizations.of(context).notificationsTitle,
        ),
        if (unread > 0)
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              width: 17,
              height: 17,
              decoration: const BoxDecoration(
                color: AppColors.error,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  unread > 9 ? '9+' : '$unread',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
