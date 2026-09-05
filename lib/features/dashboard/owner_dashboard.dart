import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/fleet/fleet_entry_card.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/features/assets/asset_provider.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/notifications/notification_provider.dart';
import 'package:vortice_app/features/work_orders/work_order_provider.dart';
import 'package:vortice_app/features/reminders/reminder_provider.dart';
import 'package:vortice_app/features/service_requests/service_request_provider.dart';
import 'package:vortice_app/features/telemetry/telemetry_provider.dart';
import 'package:vortice_app/models/telemetry_alert.dart';
import 'package:vortice_app/models/work_order.dart';

// ── Provider: clients organised by activity ──────────────────────────────────

final clientSummaryProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final orgRows = await supabase
      .from(AppConstants.tClientOrgs)
      .select('id, name, owner_profile_id, created_at')
      .order('created_at', ascending: false);

  final orgs = List<Map<String, dynamic>>.from(orgRows as List);
  final clients = orgs.isNotEmpty
      ? orgs
          .map((org) => {
                'id': org['owner_profile_id'],
                'name': org['name'],
              })
          .toList()
      : List<Map<String, dynamic>>.from(await supabase
          .from(AppConstants.tProfiles)
          .select('id, full_name')
          .inFilter('role', ['client', 'client_admin']) as List);

  // For each client org/owner, get vessel count and open WO count.
  final result = <Map<String, dynamic>>[];
  for (final client in clients) {
    final clientId = client['id'] as String?;
    if (clientId == null) continue;

    final assets = await supabase
        .from(AppConstants.tAssets)
        .select('id')
        .eq('client_id', clientId);
    final assetCount = (assets as List).length;

    final openWOs = await supabase
        .from(AppConstants.tWorkOrders)
        .select('id, updated_at')
        .eq('client_id', clientId)
        .inFilter('status', ['draft', 'assigned', 'in_progress']);
    final openWOList = List<Map<String, dynamic>>.from(openWOs as List);

    // Latest activity = most recent updated_at from any WO
    DateTime? latestActivity;
    for (final wo in openWOList) {
      final ts = wo['updated_at'] != null
          ? DateTime.tryParse(wo['updated_at'] as String)
          : null;
      if (ts != null &&
          (latestActivity == null || ts.isAfter(latestActivity))) {
        latestActivity = ts;
      }
    }

    result.add({
      'id': clientId,
      'name':
          client['name'] as String? ?? client['full_name'] as String? ?? '—',
      'vessel_count': assetCount,
      'open_wo_count': openWOList.length,
      'latest_activity': latestActivity,
    });
  }

  // Sort by most recent activity
  result.sort((a, b) {
    final aDate = a['latest_activity'] as DateTime?;
    final bDate = b['latest_activity'] as DateTime?;
    if (aDate == null && bDate == null) return 0;
    if (aDate == null) return 1;
    if (bDate == null) return -1;
    return bDate.compareTo(aDate);
  });

  return result;
});

class OwnerDashboard extends ConsumerWidget {
  const OwnerDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final profile = ref.watch(profileProvider).valueOrNull;
    final assetsAsync = ref.watch(assetsProvider);
    final workOrdersAsync = ref.watch(workOrdersProvider);
    final urgentCount = ref.watch(reminderUrgentCountProvider);
    final newServiceRequestCount = ref.watch(newServiceRequestCountProvider);
    final clientsAsync = ref.watch(clientSummaryProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.ownerDashboardTitle),
        actions: [
          const _BellButton(route: '/owner/notifications'),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () =>
                ref.read(authControllerProvider.notifier).signOut(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(assetsProvider);
          ref.invalidate(workOrdersProvider);
          ref.invalidate(newServiceRequestCountProvider);
        },
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            const FleetEntryCard(),
            // Greeting + date
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
              child: Text(
                l10n.greeting(profile?.fullName.split(' ').first ?? ''),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                DateFormat('EEEE, MMMM d').format(DateTime.now()),
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
            // KPI cards
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                      onTap: () => context.go('/owner/assets'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _KpiCard(
                      label: l10n.openWorkOrders,
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
                      icon: Icons.build,
                      color: AppColors.warning,
                      onTap: () => context.go('/owner/work-orders'),
                    ),
                  ),
                ],
              ),
            ),
            // Quick access cards
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: _QuickAccessCard(
                      icon: Icons.people,
                      label: l10n.clientsTitle,
                      color: const Color(0xFF9C27B0),
                      badge: clientsAsync.valueOrNull?.length,
                      onTap: () => context.push('/owner/clients'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _QuickAccessCard(
                      icon: Icons.vpn_key,
                      label: l10n.orgCodesTitle,
                      color: AppColors.warning,
                      onTap: () => context.push('/owner/org-codes'),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _QuickAccessCard(
                icon: Icons.schedule,
                label: l10n.upcomingServices,
                color: AppColors.error,
                badge: urgentCount.valueOrNull,
                onTap: () => context.push('/owner/reminders'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _QuickAccessCard(
                icon: Icons.settings_outlined,
                label: l10n.partsTitle,
                color: AppColors.primary,
                onTap: () => context.push('/owner/parts'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _QuickAccessCard(
                icon: Icons.support_agent_outlined,
                label: 'Service Requests',
                color: AppColors.warning,
                badge: newServiceRequestCount.valueOrNull,
                onTap: () => context.push('/owner/service-requests'),
              ),
            ),
            // ── Clients section ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(l10n.clientsTitle,
                      style: Theme.of(context).textTheme.titleMedium),
                  TextButton(
                    onPressed: () => context.push('/owner/clients'),
                    child: Text(l10n.viewAll),
                  ),
                ],
              ),
            ),
            clientsAsync.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (err, _) => _ErrorTile(message: err.toString()),
              data: (clients) {
                if (clients.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      'No clients yet.',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 13),
                    ),
                  );
                }
                return Column(
                  children: clients
                      .take(5)
                      .map((c) => _ClientSummaryCard(client: c))
                      .toList(),
                );
              },
            ),

            // ── Alerts section (live telemetry) ────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Text('Alerts',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            const _OwnerAlertsSection(),

            // Open work orders section
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(l10n.recentWorkOrders,
                      style: Theme.of(context).textTheme.titleMedium),
                  TextButton(
                    onPressed: () => context.go('/owner/work-orders'),
                    child: Text(l10n.viewAll),
                  ),
                ],
              ),
            ),
            workOrdersAsync.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (err, _) => _ErrorTile(message: err.toString()),
              data: (orders) {
                final recent = orders.take(5).toList();
                if (recent.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(child: Text(l10n.noWorkOrders)),
                  );
                }
                return Column(
                  children: recent
                      .map((wo) => _WorkOrderTile(workOrder: wo))
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/owner/work-orders/create'),
        icon: const Icon(Icons.add),
        label: Text(l10n.createWorkOrder),
        backgroundColor: AppColors.primary,
      ),
    );
  }
}

class _QuickAccessCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final int? badge;
  final VoidCallback onTap;

  const _QuickAccessCard({
    required this.icon,
    required this.label,
    required this.color,
    this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: const Border.fromBorderSide(
            BorderSide(color: AppColors.cardBorder),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label, style: Theme.of(context).textTheme.titleSmall),
            ),
            if (badge != null && badge! > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  badge.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            const Icon(Icons.chevron_right,
                color: AppColors.textSecondary, size: 20),
          ],
        ),
      ),
    );
  }
}

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
            BorderSide(color: AppColors.cardBorder),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 12),
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

class _WorkOrderTile extends StatelessWidget {
  final WorkOrder workOrder;

  const _WorkOrderTile({required this.workOrder});

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
        onTap: () => context.push('/owner/work-orders/${workOrder.id}'),
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
                            color: color.withValues(alpha: 0.12),
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

// ── Client summary card ───────────────────────────────────────────

class _ClientSummaryCard extends StatelessWidget {
  final Map<String, dynamic> client;
  const _ClientSummaryCard({required this.client});

  @override
  Widget build(BuildContext context) {
    final activity = client['latest_activity'] as DateTime?;
    final actStr = activity != null
        ? DateFormat('MMM d').format(activity.toLocal())
        : 'No activity';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: () => context.push('/owner/clients'),
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
              CircleAvatar(
                backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                child: const Icon(Icons.person_outline,
                    color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      client['name'] as String? ?? '—',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.directions_boat,
                            size: 11, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          '${client['vessel_count']} vessels',
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 11),
                        ),
                        const SizedBox(width: 12),
                        const Icon(Icons.build_outlined,
                            size: 11, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          '${client['open_wo_count']} open WOs',
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 11),
                        ),
                        const SizedBox(width: 12),
                        const Icon(Icons.access_time,
                            size: 11, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          actStr,
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  color: AppColors.textSecondary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorTile extends StatelessWidget {
  final String message;
  const _ErrorTile({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(message, style: const TextStyle(color: AppColors.error)),
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

// ── Owner alerts section ───────────────────────────────────────────────────────────────

class _OwnerAlertsSection extends ConsumerWidget {
  const _OwnerAlertsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alertsAsync = ref.watch(activeAlertsProvider);

    return alertsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: LinearProgressIndicator(),
      ),
      error: (err, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Text(err.toString(),
            style: const TextStyle(color: AppColors.error, fontSize: 13)),
      ),
      data: (alerts) {
        if (alerts.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: AppColors.success.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle_outline,
                      color: AppColors.success, size: 20),
                  SizedBox(width: 12),
                  Text(
                    'No active alerts',
                    style: TextStyle(color: AppColors.success, fontSize: 13),
                  ),
                ],
              ),
            ),
          );
        }

        return Column(
          children:
              alerts.take(5).map((a) => _OwnerAlertTile(alert: a)).toList(),
        );
      },
    );
  }
}

class _OwnerAlertTile extends StatelessWidget {
  final TelemetryAlert alert;

  const _OwnerAlertTile({required this.alert});

  Color get _severityColor => switch (alert.severity) {
        AlertSeverity.critical => AppColors.error,
        AlertSeverity.warning => AppColors.warning,
        _ => AppColors.primary,
      };

  @override
  Widget build(BuildContext context) {
    final color = _severityColor;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: () {
          if (alert.assetId.isNotEmpty) {
            context.push('/telemetry/vessel/${alert.assetId}');
          } else if (alert.engineId != null) {
            context.push('/owner/engines/${alert.engineId}/telemetry');
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      alert.spn != null
                          ? 'SPN ${alert.spn}'
                          : alert.alertType.name.toUpperCase(),
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(color: color),
                    ),
                    if (alert.message != null)
                      Text(
                        alert.message!,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    Text(
                      _severityLabel(),
                      style: TextStyle(
                        color: color,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              if (alert.createdAt != null)
                Text(
                  DateFormat('MMM d HH:mm').format(alert.createdAt!),
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 11),
                ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right,
                  color: AppColors.textSecondary, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  String _severityLabel() => switch (alert.severity) {
        AlertSeverity.critical => 'CRITICAL',
        AlertSeverity.warning => 'WARNING',
        _ => 'INFO',
      };
}
