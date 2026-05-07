import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/work_orders/work_order_provider.dart';
import 'package:vortice_app/features/service_reports/service_report_provider.dart';
import 'package:vortice_app/models/work_order.dart';

class EmployeeDashboard extends ConsumerWidget {
  const EmployeeDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final profile = ref.watch(profileProvider).valueOrNull;
    final workOrdersAsync = ref.watch(workOrdersProvider);
    final reportsAsync = ref.watch(serviceReportsProvider);

    final today = DateFormat('EEEE, MMMM d').format(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.employeeDashboardTitle),
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
          ref.invalidate(workOrdersProvider);
          ref.invalidate(serviceReportsProvider);
        },
        child: workOrdersAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(
            child: Text(err.toString(),
                style: const TextStyle(color: AppColors.error)),
          ),
          data: (allOrders) {
            final myId = profile?.id;

            final activeOrders = allOrders
                .where((w) =>
                    w.status != WorkOrderStatus.closed &&
                    w.status != WorkOrderStatus.invoiced)
                .toList()
              ..sort((a, b) =>
                  _priorityRank(a.status).compareTo(_priorityRank(b.status)));

            final myActive =
                activeOrders.where((w) => w.assignedTo == myId).toList();

            final shopQueue =
                activeOrders.where((w) => w.assignedTo != myId).toList();

            final activeInProgress = activeOrders
                .where((w) => w.status == WorkOrderStatus.inProgress)
                .length;
            final assignedToMe = myActive.length;
            final openWorkOrders = activeOrders.length;
            final myDraft =
                myActive.where((w) => w.status == WorkOrderStatus.draft).length;

            final reportCount = reportsAsync.valueOrNull?.length ?? 0;

            return ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                // ── Greeting + date ────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                  child: Text(
                    l10n.greeting(profile?.fullName.split(' ').first ?? ''),
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  child: Text(
                    today,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 13),
                  ),
                ),

                // ── KPI row ────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  child: Row(
                    children: [
                      _KpiCard(
                        label: 'In Progress',
                        value: '$activeInProgress',
                        color: AppColors.primary,
                        icon: Icons.play_circle_outline,
                        onTap: () => context.push('/employee/work-orders'),
                      ),
                      const SizedBox(width: 10),
                      _KpiCard(
                        label: 'Assigned Me',
                        value: '$assignedToMe',
                        color: AppColors.warning,
                        icon: Icons.assignment_outlined,
                        onTap: () => context.push('/employee/work-orders'),
                      ),
                      const SizedBox(width: 10),
                      _KpiCard(
                        label: 'Open WOs',
                        value: '$openWorkOrders',
                        color: AppColors.success,
                        icon: Icons.list_alt_outlined,
                        onTap: () => context.push('/employee/work-orders'),
                      ),
                      const SizedBox(width: 10),
                      _KpiCard(
                        label: 'Reports',
                        value: '$reportCount',
                        color: AppColors.success,
                        icon: Icons.description_outlined,
                        onTap: () => context.push('/employee/service-reports'),
                      ),
                    ],
                  ),
                ),

                // ── Quick actions ──────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: _SectionHeader(title: 'QUICK ACTIONS'),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      _QuickAction(
                        icon: Icons.description_outlined,
                        label: 'New Report',
                        onTap: () =>
                            context.push('/employee/service-reports/new'),
                      ),
                      const SizedBox(width: 10),
                      _QuickAction(
                        icon: Icons.settings_outlined,
                        label: 'Parts Log',
                        onTap: () => context.push('/employee/parts'),
                      ),
                      const SizedBox(width: 10),
                      _QuickAction(
                        icon: Icons.list_alt_outlined,
                        label: 'All WOs',
                        onTap: () => context.push('/employee/work-orders'),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ── My work queue ──────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _SectionHeader(title: l10n.assignedToMe),
                      if (myActive.isNotEmpty)
                        TextButton(
                          onPressed: () =>
                              context.push('/employee/work-orders'),
                          child: Text(l10n.viewAll,
                              style: const TextStyle(
                                  color: AppColors.primary, fontSize: 12)),
                        ),
                    ],
                  ),
                ),

                if (myActive.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 24),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(Icons.check_circle_outline,
                              size: 48,
                              color: AppColors.success.withOpacity(0.7)),
                          const SizedBox(height: 10),
                          Text(
                            l10n.noAssignedWorkOrders,
                            style:
                                const TextStyle(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ...myActive.take(5).map((wo) => _WorkOrderCard(
                        workOrder: wo,
                        onTap: () =>
                            context.push('/employee/work-orders/${wo.id}'),
                      )),

                if (myActive.length > 5) ...[
                  const SizedBox(height: 4),
                  Center(
                    child: TextButton(
                      onPressed: () => context.push('/employee/work-orders'),
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
                      const _SectionHeader(title: 'OPEN WORK ORDERS'),
                      if (shopQueue.isNotEmpty)
                        TextButton(
                          onPressed: () =>
                              context.push('/employee/work-orders'),
                          child: Text(l10n.viewAll,
                              style: const TextStyle(
                                  color: AppColors.primary, fontSize: 12)),
                        ),
                    ],
                  ),
                ),

                if (shopQueue.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    child: Text(
                      'No other active work orders.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                else
                  ...shopQueue.take(5).map((wo) => _WorkOrderCard(
                        workOrder: wo,
                        onTap: () =>
                            context.push('/employee/work-orders/${wo.id}'),
                      )),

                if (shopQueue.length > 5) ...[
                  const SizedBox(height: 4),
                  Center(
                    child: TextButton(
                      onPressed: () => context.push('/employee/work-orders'),
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
                        color: AppColors.warning.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: AppColors.warning.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline,
                              color: AppColors.warning, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '$myDraft draft work order${myDraft > 1 ? 's' : ''} waiting to be started.',
                              style: const TextStyle(
                                  color: AppColors.warning, fontSize: 13),
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

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  const _KpiCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 8),
              Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Quick action button ───────────────────────────────────────────────────────

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Column(
            children: [
              Icon(icon, color: AppColors.primary, size: 22),
              const SizedBox(height: 6),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppColors.primary,
            letterSpacing: 1.2,
          ),
    );
  }
}

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
                    if (workOrder.scheduledDate != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.calendar_today_outlined,
                              size: 11, color: AppColors.textSecondary),
                          const SizedBox(width: 4),
                          Text(
                            DateFormat('MMM d')
                                .format(workOrder.scheduledDate!),
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
              const Icon(Icons.chevron_right,
                  color: AppColors.textSecondary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
