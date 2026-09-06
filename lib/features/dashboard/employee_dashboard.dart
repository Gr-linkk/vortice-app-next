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
                    // ── My work queue ──────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: DashboardSection(
                              inset: false,
                              title: l10n.assignedToMe,
                            ),
                          ),
                          if (myActive.isNotEmpty)
                            TextButton(
                              onPressed: () =>
                                  context.push('/employee/work-orders'),
                              child: Text(
                                l10n.viewAll,
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                    if (myActive.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 24,
                        ),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(
                                Icons.check_circle_outline,
                                size: 48,
                                color: AppColors.success.withValues(alpha: 0.7),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                l10n.noAssignedWorkOrders,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      ...myActive
                          .take(5)
                          .map(
                            (wo) => _WorkOrderCard(
                              workOrder: wo,
                              onTap: () => context.push(
                                '/employee/work-orders/${wo.id}',
                              ),
                            ),
                          ),

                    if (myActive.length > 5) ...[
                      const SizedBox(height: 4),
                      Center(
                        child: TextButton(
                          onPressed: () =>
                              context.push('/employee/work-orders'),
                          child: Text(
                            '+${myActive.length - 5} more',
                            style: const TextStyle(color: AppColors.primary),
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),

                    // ── Shop work queue ────────────────────────────────
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
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                    if (shopQueue.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        child: Text(
                          'No other active work orders.',
                          style: TextStyle(color: AppColors.textSecondary),
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
                            style: const TextStyle(color: AppColors.primary),
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
                            color: AppColors.warning.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: AppColors.warning.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.info_outline,
                                color: AppColors.warning,
                                size: 18,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  '$myDraft draft work order${myDraft > 1 ? 's' : ''} waiting to be started.',
                                  style: const TextStyle(
                                    color: AppColors.warning,
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

  Color _statusColor() => switch (workOrder.status) {
    WorkOrderStatus.inProgress => AppColors.primary,
    WorkOrderStatus.assigned => AppColors.warning,
    WorkOrderStatus.draft => AppColors.textSecondary,
    WorkOrderStatus.onHold => AppColors.error,
    _ => AppColors.textSecondary,
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
    final color = _statusColor();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: onTap,
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
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    if (workOrder.scheduledDate != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.calendar_today_outlined,
                            size: 11,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            DateFormat(
                              'MMM d',
                            ).format(workOrder.scheduledDate!),
                            style: const TextStyle(
                              color: AppColors.textSecondary,
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
