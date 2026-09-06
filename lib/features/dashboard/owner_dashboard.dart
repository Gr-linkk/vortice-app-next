import 'package:vortice_app/features/dashboard/dashboard_layout.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/features/assets/asset_provider.dart';
import 'package:vortice_app/features/work_orders/work_order_provider.dart';
import 'package:vortice_app/features/service_requests/service_request_provider.dart';
import 'package:vortice_app/features/telemetry/telemetry_provider.dart';
import 'package:vortice_app/models/telemetry_alert.dart';
import 'package:vortice_app/models/work_order.dart';

// ── Provider: clients organised by activity ──────────────────────────────────

final clientSummaryProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final orgRows = await supabase
      .from(AppConstants.tClientOrgs)
      .select('id, name, owner_profile_id, created_at')
      .order('created_at', ascending: false);

  final orgs = List<Map<String, dynamic>>.from(orgRows as List);
  final clients = orgs.isNotEmpty
      ? orgs
            .map((org) => {'id': org['owner_profile_id'], 'name': org['name']})
            .toList()
      : List<Map<String, dynamic>>.from(
          await supabase
                  .from(AppConstants.tProfiles)
                  .select('id, full_name')
                  .inFilter('role', ['client', 'client_admin'])
              as List,
        );

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
    final workOrdersAsync = ref.watch(workOrdersProvider);
    final clientsAsync = ref.watch(clientSummaryProvider);

    return Scaffold(
      appBar: const DashboardAppBar(),
      body: DashboardRefresh(
        onRefresh: () async {
          ref.invalidate(assetsProvider);
          ref.invalidate(clientSummaryProvider);
          ref.invalidate(activeAlertsProvider);
          ref.invalidate(workOrdersProvider);
          ref.invalidate(newServiceRequestCountProvider);
        },
        child: DashboardList(
          children: [
            DashboardSection(
              title: dashboardText(context, 'Alerts', 'Alertas'),
            ),
            const _OwnerAlertsSection(),

            DashboardSection(
              title: l10n.recentWorkOrders,
              onViewAll: () => context.go('/owner/work-orders'),
            ),
            workOrdersAsync.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (err, _) =>
                  _ErrorTile(message: friendlyError(context, err)),
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
            DashboardSection(
              title: l10n.clientsTitle,
              onViewAll: () => context.push('/owner/clients'),
            ),
            clientsAsync.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (err, _) =>
                  _ErrorTile(message: friendlyError(context, err)),
              data: (clients) {
                if (clients.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      'No clients yet.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
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
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
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
              const Icon(
                Icons.chevron_right,
                color: AppColors.textSecondary,
                size: 20,
              ),
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

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: const Icon(
          Icons.business_outlined,
          color: AppColors.primaryLight,
        ),
        title: Text(client['name'] as String? ?? '—'),
        subtitle: Text(
          dashboardText(
            context,
            '${client['vessel_count']} assets · ${client['open_wo_count']} open work orders\n$actStr',
            '${client['vessel_count']} equipos · ${client['open_wo_count']} órdenes abiertas\n$actStr',
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/owner/clients'),
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
        child: Text(
          friendlyError(context, err),
          style: const TextStyle(color: AppColors.error, fontSize: 13),
        ),
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
                border: Border.all(
                  color: AppColors.success.withValues(alpha: 0.3),
                ),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    color: AppColors.success,
                    size: 20,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'No active alerts',
                      style: TextStyle(color: AppColors.success, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Column(
          children: alerts
              .take(5)
              .map((a) => _OwnerAlertTile(alert: a))
              .toList(),
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
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
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
                      style: Theme.of(
                        context,
                      ).textTheme.titleSmall?.copyWith(color: color),
                    ),
                    if (alert.message != null)
                      Text(
                        alert.message!,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
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
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right,
                color: AppColors.textSecondary,
                size: 18,
              ),
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
