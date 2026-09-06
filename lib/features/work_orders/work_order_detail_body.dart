import 'package:flutter/material.dart';
import 'package:vortice_app/features/coordination/coordination_entry.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/fleet/work_order_fault_card.dart';
import 'package:vortice_app/features/checklists/checklist_provider.dart';
import 'package:vortice_app/features/work_orders/work_order_client_checklist_context_section.dart';
import 'package:vortice_app/features/work_orders/work_order_detail_actions_section.dart';
import 'package:vortice_app/features/work_orders/work_order_detail_info_row.dart';
import 'package:vortice_app/features/work_orders/work_order_detail_support.dart';
import 'package:vortice_app/features/work_orders/work_order_parts_section.dart';
import 'package:vortice_app/features/work_orders/work_order_pm_kit_section.dart';
import 'package:vortice_app/features/work_orders/work_order_provider.dart';
import 'package:vortice_app/features/work_orders/work_order_service_report_card.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/models/profile.dart';
import 'package:vortice_app/models/work_order.dart';

class WorkOrderDetailBody extends ConsumerWidget {
  final WorkOrder workOrder;
  final bool canManage;
  final Profile? profile;

  const WorkOrderDetailBody({
    super.key,
    required this.workOrder,
    required this.canManage,
    required this.profile,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final isOwner = profile?.role == UserRole.owner;
    final isOwnerOrEmployee = isOwner || profile?.role == UserRole.employee;
    final assignmentLabel =
        isOwnerOrEmployee ? 'Assigned Techs' : 'Assigned Team';

    final assetNameAsync = ref.watch(assetNameProvider(workOrder.assetId));
    final techNameAsync = workOrder.assignedTo != null
        ? ref.watch(profileNameProvider(workOrder.assignedTo!))
        : null;
    final assignmentNamesAsync =
        ref.watch(workOrderAssignmentNamesProvider(workOrder.id));

    final routePrefix = workOrderRoutePrefixForRole(profile?.role);

    final checklistDoneAsync =
        ref.watch(checklistHasResponsesProvider(workOrder.id));
    final checklistDone = checklistDoneAsync.valueOrNull ?? false;

    final dateFmt = DateFormat.yMMMd();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        WorkOrderFaultCard(workOrderId: workOrder.id, assetId: workOrder.assetId),
        CoordinationEntry(assetId: workOrder.assetId, kind: 'job', subjectId: workOrder.id),
        // ── Status banner ──────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: workOrderStatusColor(workOrder.status).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: workOrderStatusColor(workOrder.status).withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(workOrder.title,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: workOrderStatusColor(workOrder.status).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  workOrder.status.name,
                  style: TextStyle(
                      color: workOrderStatusColor(workOrder.status),
                      fontSize: 11,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── Description ────────────────────────────────────────────
        if (workOrder.description != null) ...[
          Text(l10n.description,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: AppColors.primary, letterSpacing: 1.2)),
          const SizedBox(height: 6),
          Text(workOrder.description!),
          const SizedBox(height: 16),
        ],

        // ── Details section ────────────────────────────────────────
        Text(
          l10n.woDetailsSection.toUpperCase(),
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: AppColors.primary, letterSpacing: 1.2),
        ),
        const SizedBox(height: 8),

        // Asset name
        assetNameAsync.when(
          loading: () => WorkOrderDetailInfoRow(
              icon: Icons.directions_boat,
              label: l10n.linkedAsset,
              value: '...'),
          error: (_, __) => WorkOrderDetailInfoRow(
              icon: Icons.directions_boat, label: l10n.linkedAsset, value: '—'),
          data: (name) => WorkOrderDetailInfoRow(
              icon: Icons.directions_boat,
              label: l10n.linkedAsset,
              value: name ?? '—'),
        ),

        // Job type
        WorkOrderDetailInfoRow(
          icon: Icons.build_outlined,
          label: l10n.jobType,
          value: workOrder.jobType.name,
        ),

        // Assigned tech(s)
        assignmentNamesAsync.when(
          loading: () => WorkOrderDetailInfoRow(
              icon: Icons.people_outline, label: assignmentLabel, value: '...'),
          error: (_, __) {
            if (techNameAsync == null) {
              return WorkOrderDetailInfoRow(
                icon: Icons.people_outline,
                label: assignmentLabel,
                value: '—',
              );
            }

            return techNameAsync.when(
              loading: () => WorkOrderDetailInfoRow(
                  icon: Icons.person_outline,
                  label: l10n.assignedTech,
                  value: '...'),
              error: (_, __) => WorkOrderDetailInfoRow(
                  icon: Icons.person_outline,
                  label: l10n.assignedTech,
                  value: '—'),
              data: (name) => WorkOrderDetailInfoRow(
                  icon: Icons.person_outline,
                  label: l10n.assignedTech,
                  value: name ?? '—'),
            );
          },
          data: (names) {
            if (names.isEmpty) {
              if (techNameAsync == null) {
                return const SizedBox.shrink();
              }

              return techNameAsync.when(
                loading: () => WorkOrderDetailInfoRow(
                    icon: Icons.person_outline,
                    label: l10n.assignedTech,
                    value: '...'),
                error: (_, __) => WorkOrderDetailInfoRow(
                    icon: Icons.person_outline,
                    label: l10n.assignedTech,
                    value: '—'),
                data: (name) => WorkOrderDetailInfoRow(
                    icon: Icons.person_outline,
                    label: l10n.assignedTech,
                    value: name ?? '—'),
              );
            }

            return WorkOrderDetailInfoRow(
              icon: Icons.people_outline,
              label: assignmentLabel,
              value: names.join(', '),
            );
          },
        ),

        // Scheduled date
        if (workOrder.scheduledDate != null)
          WorkOrderDetailInfoRow(
            icon: Icons.calendar_today,
            label: l10n.scheduledDate,
            value: dateFmt.format(workOrder.scheduledDate!),
          ),

        // Engine hours at start
        if (workOrder.hoursAtStart != null)
          WorkOrderDetailInfoRow(
            icon: Icons.speed,
            label: l10n.hoursAtStart,
            value: workOrder.hoursAtStart!.toStringAsFixed(1),
          ),

        // Engine hours at end
        if (workOrder.hoursAtEnd != null)
          WorkOrderDetailInfoRow(
            icon: Icons.speed,
            label: l10n.hoursAtEnd,
            value: workOrder.hoursAtEnd!.toStringAsFixed(1),
          ),

        // Labour hours
        if (workOrder.labourHours != null)
          WorkOrderDetailInfoRow(
            icon: Icons.access_time,
            label: l10n.labourHours,
            value: workOrder.labourHours!.toStringAsFixed(1),
          ),

        // Internal notes — owner/employee only
        if (isOwnerOrEmployee && workOrder.notesInternal != null) ...[
          const SizedBox(height: 12),
          Text(
            l10n.internalNotes.toUpperCase(),
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: AppColors.warning, letterSpacing: 1.2),
          ),
          const SizedBox(height: 4),
          Text(workOrder.notesInternal!, style: const TextStyle(fontSize: 13)),
        ],

        // On-hold reason — only when on_hold
        if (workOrder.status == WorkOrderStatus.onHold &&
            workOrder.onHoldReason != null) ...[
          const SizedBox(height: 12),
          WorkOrderDetailInfoRow(
            icon: Icons.pause_circle_outline,
            label: l10n.onHoldReason,
            value: workOrder.onHoldReason!,
            color: AppColors.warning,
          ),
        ],

        // Completed at
        if (workOrder.completedAt != null)
          WorkOrderDetailInfoRow(
            icon: Icons.check_circle,
            label: l10n.completedAt,
            value: dateFmt.format(workOrder.completedAt!.toLocal()),
            color: AppColors.success,
          ),

        // ── Client checklist context ───────────────────────────────────
        if (canManage) ...[
          const SizedBox(height: 16),
          WorkOrderClientChecklistContextSection(workOrder: workOrder),
        ],

        // ── PM Parts Kit (read-only for tech) ──────────────────────────
        if (workOrder.checklistTemplateId != null)
          WorkOrderPmKitSection(templateId: workOrder.checklistTemplateId!),

        if (isOwnerOrEmployee) ...[
          const SizedBox(height: 16),
          WorkOrderPartsSection(
            workOrderId: workOrder.id,
            isOwnerOrEmployee: isOwnerOrEmployee,
          ),
        ],

        const SizedBox(height: 24),
        WorkOrderServiceReportCard(
          workOrder: workOrder,
          routePrefix: routePrefix,
          role: profile?.role,
        ),
        const SizedBox(height: 24),
        WorkOrderDetailActionsSection(
          workOrder: workOrder,
          profile: profile,
          isOwnerOrEmployee: isOwnerOrEmployee,
          isOwner: isOwner,
          routePrefix: routePrefix,
          checklistDone: checklistDone,
        ),

      ],
    );
  }
}
