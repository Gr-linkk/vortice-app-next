import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/checklists/checklist_assignment_provider.dart';
import 'package:vortice_app/features/work_orders/work_order_provider.dart';
import 'package:vortice_app/models/work_order.dart';

// ── Provider: WOs assigned to the current mechanic ──────────────────────────

final mechanicAssignedWorkOrdersProvider =
    FutureProvider<List<WorkOrder>>((ref) async {
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return [];

  // Fetch work orders where this user is the assigned tech
  final data = await supabase
      .from(AppConstants.tWorkOrders)
      .select()
      .eq('assigned_to', userId)
      .order('created_at', ascending: false);

  return (data as List)
      .map((e) => WorkOrder.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ── Provider: active checklists for assigned WOs ─────────────────────────────

final mechanicActiveChecklistsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return [];

  // Get WO IDs that have templates and are in progress
  final data = await supabase
      .from(AppConstants.tWorkOrders)
      .select('id, title, checklist_template_id')
      .eq('assigned_to', userId)
      .eq('status', 'in_progress')
      .not('checklist_template_id', 'is', null);

  return List<Map<String, dynamic>>.from(data as List);
});

// ── Provider: parts for mechanic's org assets ────────────────────────────────

final mechanicPartsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return [];

  // Fetch parts from the catalog scoped to assets the mechanic is assigned to
  final assignments = await supabase
      .from(AppConstants.tWorkOrders)
      .select('asset_id')
      .eq('assigned_to', userId);

  final assetIds = (assignments as List)
      .map((e) => e['asset_id'] as String)
      .toSet()
      .toList();

  if (assetIds.isEmpty) return [];

  final parts = await supabase
      .from(AppConstants.tPartsCatalog)
      .select('part_number, description, assets(name)')
      .inFilter('asset_id', assetIds)
      .limit(10);

  return List<Map<String, dynamic>>.from(parts as List);
});

// ── Client Mechanic Dashboard ─────────────────────────────────────────────────

class ClientMechanicDashboard extends ConsumerWidget {
  const ClientMechanicDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).valueOrNull;
    final assignedAsync = ref.watch(mechanicAssignedWorkOrdersProvider);
    final checklistsAsync = ref.watch(mechanicActiveChecklistsProvider);
    final partsAsync = ref.watch(mechanicPartsProvider);

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
          ref.invalidate(mechanicAssignedWorkOrdersProvider);
          ref.invalidate(mechanicActiveChecklistsProvider);
          ref.invalidate(mechanicPartsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            // ── 1. Assigned Work ──────────────────────────────────────
            _SectionHeader(
              title: 'My Assigned Work',
              icon: Icons.build_outlined,
            ),
            assignedAsync.when(
              loading: () => const _LoadingTile(),
              error: (err, _) =>
                  _ErrorTile(message: err.toString()),
              data: (orders) {
                if (orders.isEmpty) {
                  return const _EmptyState(
                    icon: Icons.check_circle_outline,
                    message: 'No work assigned yet.',
                  );
                }
                return Column(
                  children: orders
                      .map((wo) => _AssignedWorkCard(workOrder: wo))
                      .toList(),
                );
              },
            ),

            // ── 2. Assigned PM Checklists (from client admin) ──────────────────
            _SectionHeader(
              title: 'Assigned Checklists',
              icon: Icons.checklist_outlined,
            ),
            checklistsAsync.when(
              loading: () => const _LoadingTile(),
              error: (err, _) => _ErrorTile(message: err.toString()),
              data: (assignments) {
                if (assignments.isEmpty) {
                  return const _EmptyState(
                    icon: Icons.checklist_outlined,
                    message: 'No checklists assigned yet.',
                  );
                }
                return Column(
                  children: assignments.map((a) {
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
                              AppColors.primary.withOpacity(0.1),
                          child: const Icon(Icons.build_outlined,
                              size: 18, color: AppColors.primary),
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
                            color: statusColor.withOpacity(0.15),
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
                          }
                        },
                      ),
                    );
                  }).toList(),
                );
              },
            ),

            // ── 3. Parts Lists ────────────────────────────────────────
            _SectionHeader(
              title: 'Parts Lists',
              icon: Icons.settings_outlined,
            ),
            partsAsync.when(
              loading: () => const _LoadingTile(),
              error: (err, _) =>
                  _ErrorTile(message: err.toString()),
              data: (parts) {
                if (parts.isEmpty) {
                  return const _EmptyState(
                    icon: Icons.inventory_2_outlined,
                    message: 'No parts catalog entries.',
                  );
                }
                return Column(
                  children: parts
                      .map((p) => _PartsTile(part: p))
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

// ── Assigned Work Card ────────────────────────────────────────────────────────

class _AssignedWorkCard extends ConsumerWidget {
  final WorkOrder workOrder;
  const _AssignedWorkCard({required this.workOrder});

  Color _statusColor() => switch (workOrder.status) {
        WorkOrderStatus.draft => AppColors.textSecondary,
        WorkOrderStatus.assigned => AppColors.primary,
        WorkOrderStatus.inProgress => AppColors.warning,
        WorkOrderStatus.onHold => AppColors.error,
        WorkOrderStatus.pendingReview => AppColors.primary,
        WorkOrderStatus.invoiced => AppColors.success,
        WorkOrderStatus.closed => AppColors.success,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = _statusColor();
    final assetNameAsync =
        ref.watch(assetNameProvider(workOrder.assetId));
    final scheduledStr = workOrder.scheduledDate != null
        ? DateFormat('MMM d').format(workOrder.scheduledDate!)
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: () =>
            context.push('/employee/work-orders/${workOrder.id}'),
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
                height: 50,
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
                    Text(
                      workOrder.title,
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
                            size: 12,
                            color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        assetNameAsync.when(
                          loading: () => const Text('...',
                              style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12)),
                          error: (_, __) => const Text('—',
                              style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12)),
                          data: (name) => Text(
                            name ?? '—',
                            style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12),
                          ),
                        ),
                        if (scheduledStr != null) ...[
                          const SizedBox(width: 10),
                          const Icon(Icons.calendar_today,
                              size: 12,
                              color: AppColors.textSecondary),
                          const SizedBox(width: 4),
                          Text(
                            scheduledStr,
                            style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ],
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
                  workOrder.status.name,
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right,
                  color: AppColors.textSecondary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Checklist Card ────────────────────────────────────────────────────────────

class _ChecklistCard extends StatelessWidget {
  final Map<String, dynamic> item;
  const _ChecklistCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: () => context
            .push('/employee/checklists/${item['id']}'),
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
              const Icon(Icons.checklist_outlined,
                  color: AppColors.primary, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item['title'] as String? ?? 'Checklist',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
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

// ── Parts Tile ────────────────────────────────────────────────────────────────

class _PartsTile extends StatelessWidget {
  final Map<String, dynamic> part;
  const _PartsTile({required this.part});

  @override
  Widget build(BuildContext context) {
    final assetName =
        (part['assets'] as Map<String, dynamic>?)?['name'] as String? ??
            '—';
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
            const Icon(Icons.settings_outlined,
                color: AppColors.primary, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    part['part_number'] as String? ?? '—',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  if (part['description'] != null)
                    Text(
                      part['description'] as String,
                      style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            Text(
              assetName,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 11),
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
          Text(title,
              style: Theme.of(context).textTheme.titleMedium),
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
