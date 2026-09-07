import 'package:vortice_app/features/dashboard/dashboard_layout.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/work_orders/work_order_provider.dart';
import 'package:vortice_app/features/service_reports/service_report_provider.dart';
import 'package:vortice_app/features/service_requests/service_request_provider.dart';
import 'package:vortice_app/models/work_order.dart';

class EmployeeDashboard extends ConsumerWidget {
  const EmployeeDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final profile = ref.watch(profileProvider).valueOrNull;
    final workOrdersAsync = ref.watch(workOrdersProvider);

    return Scaffold(
      appBar: const DashboardAppBar(),
      body: DashboardRefresh(
        onRefresh: () async {
          ref.invalidate(workOrdersProvider);
          ref.invalidate(serviceReportsProvider);
          ref.invalidate(newServiceRequestCountProvider);
        },
        child: DashboardList(
          children: [
            workOrdersAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (err, _) => AppErrorState(
                error: err,
                onRetry: () => ref.invalidate(workOrdersProvider),
              ),
              data: (allOrders) {
                final myId = profile?.id;

                final activeOrders =
                    allOrders
                        .where(
                          (w) =>
                              w.status != WorkOrderStatus.closed &&
                              w.status != WorkOrderStatus.invoiced,
                        )
                        .toList()
                      ..sort(
                        (a, b) => _priorityRank(
                          a.status,
                        ).compareTo(_priorityRank(b.status)),
                      );

                final myActive = activeOrders
                    .where((w) => w.assignedTo == myId)
                    .toList();

                final shopQueue = activeOrders
                    .where((w) => w.assignedTo != myId)
                    .toList();

                final myDraft = myActive
                    .where((w) => w.status == WorkOrderStatus.draft)
                    .length;

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: DashboardSection(
                              inset: false,
                              title: dashboardText(
                                context,
                                'Other work orders',
                                'Otras órdenes de trabajo',
                              ),
                            ),
                          ),
                          if (shopQueue.isNotEmpty)
                            TextButton(
                              onPressed: () =>
                                  context.push('/employee/work-orders'),
                              child: Text(
                                l10n.viewAll,
                                style: TextStyle(
                                  color: context.appColors.primary,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                    if (shopQueue.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        child: Text(
                          'No other active work orders.',
                          style: TextStyle(
                            color: context.appColors.textSecondary,
                          ),
                        ),
                      )
                    else
                      ...shopQueue
                          .take(5)
                          .map(
                            (wo) => _WorkOrderCard(
                              workOrder: wo,
                              onTap: () => context.push(
                                '/employee/work-orders/${wo.id}',
                              ),
                            ),
                          ),

                    if (shopQueue.length > 5) ...[
                      const SizedBox(height: 4),
                      Center(
                        child: TextButton(
                          onPressed: () =>
                              context.push('/employee/work-orders'),
                          child: Text(
                            '+${shopQueue.length - 5} more',
                            style: TextStyle(color: context.appColors.primary),
                          ),
                        ),
                      ),
                    ],

                    // ── Draft WOs reminder ─────────────────────────────
                    if (myDraft > 0) ...[
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: context.appColors.warning.withValues(
                              alpha: 0.08,
                            ),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: context.appColors.warning.withValues(
                                alpha: 0.3,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                color: context.appColors.warning,
                                size: 18,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  '$myDraft draft work order${myDraft > 1 ? 's' : ''} waiting to be started.',
                                  style: TextStyle(
                                    color: context.appColors.warning,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // In-progress first, then assigned, then draft
  int _priorityRank(WorkOrderStatus status) => switch (status) {
    WorkOrderStatus.inProgress => 0,
    WorkOrderStatus.assigned => 1,
    WorkOrderStatus.draft => 2,
    _ => 3,
  };
}

// ── KPI card ─────────────────────────────────────────────────────────────────

// ── Quick action button ───────────────────────────────────────────────────────

// ── Section header ────────────────────────────────────────────────────────────

// ── Work order card ───────────────────────────────────────────────────────────

class _WorkOrderCard extends StatelessWidget {
  final WorkOrder workOrder;
  final VoidCallback onTap;

  const _WorkOrderCard({required this.workOrder, required this.onTap});

  Color _statusColor(BuildContext context) => switch (workOrder.status) {
    WorkOrderStatus.inProgress => context.appColors.primary,
    WorkOrderStatus.assigned => context.appColors.warning,
    WorkOrderStatus.draft => context.appColors.textSecondary,
    WorkOrderStatus.onHold => context.appColors.error,
    _ => context.appColors.textSecondary,
  };

  String _statusLabel() => switch (workOrder.status) {
    WorkOrderStatus.inProgress => 'In Progress',
    WorkOrderStatus.assigned => 'Assigned',
    WorkOrderStatus.draft => 'Draft',
    WorkOrderStatus.onHold => 'On Hold',
    WorkOrderStatus.closed => 'Closed',
    _ => workOrder.status.name,
  };

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.appColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.appColors.cardBorder),
          ),
          child: Row(
            children: [
              // Status indicator strip
              Container(
                width: 4,
                height: 44,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              // Content
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
                        style: TextStyle(
                          color: context.appColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    if (workOrder.scheduledDate != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.calendar_today_outlined,
                            size: 11,
                            color: context.appColors.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            DateFormat(
                              'MMM d',
                            ).format(workOrder.scheduledDate!),
                            style: TextStyle(
                              color: context.appColors.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                color: context.appColors.textSecondary,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
