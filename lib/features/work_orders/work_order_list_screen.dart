import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/work_orders/work_order_provider.dart';
import 'package:vortice_app/models/profile.dart';
import 'package:vortice_app/models/work_order.dart';

class WorkOrderListScreen extends ConsumerStatefulWidget {
  const WorkOrderListScreen({super.key});

  @override
  ConsumerState<WorkOrderListScreen> createState() =>
      _WorkOrderListScreenState();
}

class _WorkOrderListScreenState extends ConsumerState<WorkOrderListScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final profile = ref.watch(profileProvider).valueOrNull;
    final workOrdersAsync = ref.watch(workOrdersProvider);
    final canCreate =
        profile?.role == UserRole.owner || profile?.role == UserRole.employee;

    final prefix = switch (profile?.role) {
      UserRole.owner => '/owner',
      UserRole.employee => '/employee',
      UserRole.client ||
      UserRole.clientAdmin ||
      UserRole.clientMechanic ||
      UserRole.clientOperator ||
      UserRole.operator =>
        '/client',
      _ => '/owner',
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.workOrdersTitle),
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: [
            Tab(text: l10n.statusOpen),
            Tab(text: l10n.statusInProgress),
            Tab(text: l10n.statusCompleted),
          ],
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
        ),
      ),
      body: workOrdersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(err.toString(),
                  style: const TextStyle(color: AppColors.error)),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => ref.invalidate(workOrdersProvider),
                child: Text(l10n.retry),
              ),
            ],
          ),
        ),
        data: (all) {
          final open = all
              .where((w) =>
                  w.status == WorkOrderStatus.draft ||
                  w.status == WorkOrderStatus.assigned)
              .toList();
          final inProgress = all
              .where((w) =>
                  w.status == WorkOrderStatus.inProgress ||
                  w.status == WorkOrderStatus.onHold ||
                  w.status == WorkOrderStatus.pendingReview)
              .toList();
          final completed = all
              .where((w) =>
                  w.status == WorkOrderStatus.invoiced ||
                  w.status == WorkOrderStatus.closed)
              .toList();

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(workOrdersProvider),
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _WorkOrderTab(
                    orders: open,
                    prefix: prefix,
                    emptyLabel: l10n.noWorkOrders),
                _WorkOrderTab(
                    orders: inProgress,
                    prefix: prefix,
                    emptyLabel: l10n.noWorkOrders),
                _WorkOrderTab(
                    orders: completed,
                    prefix: prefix,
                    emptyLabel: l10n.noWorkOrders),
              ],
            ),
          );
        },
      ),
      floatingActionButton: canCreate
          ? FloatingActionButton(
              onPressed: () => context.push('$prefix/work-orders/create'),
              backgroundColor: AppColors.primary,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}

class _WorkOrderTab extends StatelessWidget {
  final List<WorkOrder> orders;
  final String prefix;
  final String emptyLabel;

  const _WorkOrderTab({
    required this.orders,
    required this.prefix,
    required this.emptyLabel,
  });

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return Center(
        child: Text(emptyLabel,
            style: const TextStyle(color: AppColors.textSecondary)),
      );
    }
    return ListView.builder(
      itemCount: orders.length,
      itemBuilder: (_, i) => _WorkOrderTile(
        order: orders[i],
        onTap: () => context.push('$prefix/work-orders/${orders[i].id}'),
      ),
    );
  }
}

class _WorkOrderTile extends StatelessWidget {
  final WorkOrder order;
  final VoidCallback onTap;

  const _WorkOrderTile({required this.order, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Container(
          width: 4,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        title: Text(order.title, style: Theme.of(context).textTheme.titleSmall),
        subtitle: Text(
          order.status.name,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
        ),
        trailing:
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
        onTap: onTap,
      ),
    );
  }
}
