import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/assets/asset_provider.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/notifications/notification_provider.dart';
import 'package:vortice_app/features/operator/operator_runs_provider.dart';
import 'package:vortice_app/features/work_orders/work_order_provider.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/models/asset.dart';
import 'package:vortice_app/models/work_order.dart';

// ── Providers for client-visible operator data ─────────────────────────────

final clientPreTripRunsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final data = await supabase
      .from(AppConstants.tOperatorChecklistRuns)
      .select('id, asset_id, run_type, completed_at, assets(name)')
      .eq('run_type', 'pre_departure')
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
    final assetsAsync = ref.watch(assetsProvider);
    final workOrdersAsync = ref.watch(workOrdersProvider);
    final preTripAsync = ref.watch(clientPreTripRunsProvider);
    final flagsAsync = ref.watch(clientFlaggedIssuesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.clientDashboardTitle),
        actions: [
          _BellButton(route: '/client/notifications'),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(assetsProvider);
          ref.invalidate(workOrdersProvider);
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
            // KPI cards
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
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
                  const SizedBox(width: 12),
                  Expanded(
                    child: _KpiCard(
                      label: l10n.activeServices,
                      value: workOrdersAsync.when(
                        data: (list) => list
                            .where((w) =>
                                w.status == WorkOrderStatus.draft ||
                                w.status == WorkOrderStatus.assigned ||
                                w.status == WorkOrderStatus.inProgress)
                            .length
                            .toString(),
                        loading: () => '—',
                        error: (_, __) => '!',
                      ),
                      icon: Icons.build_outlined,
                      color: AppColors.warning,
                      onTap: () => context.go('/client/work-orders'),
                    ),
                  ),
                ],
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
            // Active work orders
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(l10n.activeServices,
                      style: Theme.of(context).textTheme.titleMedium),
                  TextButton(
                    onPressed: () => context.go('/client/work-orders'),
                    child: Text(l10n.viewAll),
                  ),
                ],
              ),
            ),
            workOrdersAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (orders) {
                if (orders.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(child: Text(l10n.noWorkOrders)),
                  );
                }
                return Column(
                  children: orders
                      .take(3)
                      .map((wo) => _WorkOrderCard(workOrder: wo))
                      .toList(),
                );
              },
            ),

            // ── Pre-Trip Checks ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
              child: Text(l10n.recentPreTripChecks,
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            preTripAsync.when(
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
                    final assetName =
                        (run['assets'] as Map<String, dynamic>?)?['name']
                            as String? ??
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
                            color: AppColors.success.withOpacity(0.15),
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
                    final assetName =
                        (flag['assets'] as Map<String, dynamic>?)?['name']
                            as String? ??
                        '—';
                    final isUrgent = flag['severity'] == 'urgent';
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: (isUrgent
                                  ? AppColors.error
                                  : AppColors.warning)
                              .withOpacity(0.15),
                          child: Icon(
                            isUrgent ? Icons.warning : Icons.flag,
                            color: isUrgent
                                ? AppColors.error
                                : AppColors.warning,
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
                                color: AppColors.textSecondary,
                                fontSize: 12)),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.warning.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'OPEN',
                            style: const TextStyle(
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
            const Icon(Icons.directions_boat, color: AppColors.primary, size: 28),
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

// ── Work order card ───────────────────────────────────────────────────────────

class _WorkOrderCard extends StatelessWidget {
  final WorkOrder workOrder;
  const _WorkOrderCard({required this.workOrder});

  Color _statusColor() => switch (workOrder.status) {
        WorkOrderStatus.draft => AppColors.textSecondary,
        WorkOrderStatus.assigned => AppColors.primary,
        WorkOrderStatus.inProgress => AppColors.warning,
        WorkOrderStatus.onHold => AppColors.error,
        WorkOrderStatus.pendingReview => AppColors.primary,
        WorkOrderStatus.invoiced => AppColors.success,
        WorkOrderStatus.closed => AppColors.success,
      };

  String _statusLabel() => switch (workOrder.status) {
        WorkOrderStatus.draft => 'Draft',
        WorkOrderStatus.assigned => 'Assigned',
        WorkOrderStatus.inProgress => 'In Progress',
        WorkOrderStatus.onHold => 'On Hold',
        WorkOrderStatus.pendingReview => 'Review',
        WorkOrderStatus.invoiced => 'Invoiced',
        WorkOrderStatus.closed => 'Closed',
      };

  @override
  Widget build(BuildContext context) {
    final color = _statusColor();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: () => context.push('/client/work-orders/${workOrder.id}'),
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
              Container(
                width: 4,
                height: 44,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            workOrder.title,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
                            _statusLabel(),
                            style: TextStyle(
                              color: color,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (workOrder.description != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        workOrder.description!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right,
                  color: AppColors.textSecondary, size: 20),
            ],
          ),
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
