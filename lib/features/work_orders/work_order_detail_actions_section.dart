import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/clients/client_capability_gate.dart';
import 'package:vortice_app/features/invoices/invoice_provider.dart';
import 'package:vortice_app/features/service_reports/service_report_provider.dart';
import 'package:vortice_app/features/work_orders/work_order_completion_policy.dart';
import 'package:vortice_app/features/work_orders/work_order_detail_actions_policy.dart';
import 'package:vortice_app/features/work_orders/work_order_detail_support.dart';
import 'package:vortice_app/features/work_orders/work_order_log_hours_sheet.dart';
import 'package:vortice_app/features/work_orders/work_order_provider.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/models/client_capability.dart';
import 'package:vortice_app/models/profile.dart';
import 'package:vortice_app/models/work_order.dart';

class WorkOrderDetailActionsSection extends ConsumerWidget {
  final WorkOrder workOrder;
  final Profile? profile;
  final bool isOwnerOrEmployee;
  final bool isOwner;
  final String routePrefix;
  final bool checklistDone;

  const WorkOrderDetailActionsSection({
    super.key,
    required this.workOrder,
    required this.profile,
    required this.isOwnerOrEmployee,
    required this.isOwner,
    required this.routePrefix,
    required this.checklistDone,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final isLoading = ref.watch(workOrderControllerProvider).isLoading;
    final invoiceState = ref.watch(invoiceControllerProvider);
    final assignedAsync =
        ref.watch(currentUserAssignedToWorkOrderProvider(workOrder.id));
    final pmChecklistsAllowedAsync = ref.watch(clientCapabilityGateProvider((
      clientId: null,
      capability: ClientCapability.pmChecklists,
    )));
    final isAssignedContributor = assignedAsync.valueOrNull ?? false;
    final pmChecklistsAllowed =
        isOwnerOrEmployee || (pmChecklistsAllowedAsync.valueOrNull ?? false);
    final canUseChecklist = WorkOrderDetailActionsPolicy.canUseChecklist(
      isOwnerOrEmployee: isOwnerOrEmployee,
      isAssignedContributor: isAssignedContributor,
      pmChecklistsAllowed: pmChecklistsAllowed,
    );
    final canManageStatus = isOwnerOrEmployee;
    final reportsAsync =
        ref.watch(serviceReportsByWorkOrderProvider(workOrder.id));
    final hasSubmittedServiceReport =
        WorkOrderCompletionPolicy.workOrderHasSubmittedServiceReport(
      reportsAsync.valueOrNull ?? const [],
    );
    final canOpenChecklist = WorkOrderDetailActionsPolicy.canOpenChecklist(
      canUseChecklist: canUseChecklist,
      checklistTemplateId: workOrder.checklistTemplateId,
      status: workOrder.status,
    );

    if (!WorkOrderDetailActionsPolicy.showsActionsSection(
      canManageStatus: canManageStatus,
      canOpenChecklist: canOpenChecklist,
    )) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.actions.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.primary,
                letterSpacing: 1.2,
              ),
        ),
        const SizedBox(height: 12),
        if (WorkOrderDetailActionsPolicy.canStartWorkOrder(
          canManageStatus: canManageStatus,
          status: workOrder.status,
        ))
          ElevatedButton.icon(
            onPressed: isLoading
                ? null
                : () async {
                    final success = await ref
                        .read(workOrderControllerProvider.notifier)
                        .updateStatus(
                          workOrder.id,
                          WorkOrderStatus.inProgress,
                        );
                    if (!success && context.mounted) {
                      showWorkOrderActionFailedSnackBar(context);
                    }
                  },
            icon: const Icon(Icons.play_arrow),
            label: Text(l10n.startWorkOrder),
          ),
        if (canOpenChecklist) ...[
          if (WorkOrderDetailActionsPolicy.canStartWorkOrder(
            canManageStatus: canManageStatus,
            status: workOrder.status,
          ))
            const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () =>
                context.push('$routePrefix/checklists/${workOrder.id}'),
            icon: Icon(
              checklistDone ? Icons.check_circle : Icons.checklist,
              color: checklistDone ? AppColors.success : null,
            ),
            label: Text(
              checklistDone
                  ? '${l10n.viewChecklist} • ${l10n.statusCompleted}'
                  : 'Continue checklist',
            ),
            style: checklistDone
                ? OutlinedButton.styleFrom(
                    foregroundColor: AppColors.success,
                    side: const BorderSide(color: AppColors.success),
                  )
                : null,
          ),
        ],
        if (WorkOrderDetailActionsPolicy.canCompleteWorkOrder(
          canManageStatus: canManageStatus,
          status: workOrder.status,
        )) ...[
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: isLoading
                ? null
                : () async {
                    if (WorkOrderCompletionPolicy.shouldExplainMissingServiceReport(
                      status: workOrder.status,
                      hasSubmittedServiceReport: hasSubmittedServiceReport,
                    )) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Submit a service report before marking this work order completed.',
                            ),
                            backgroundColor: AppColors.warning,
                          ),
                        );
                      context.push(
                        '$routePrefix/service-reports/new?workOrderId=${Uri.encodeComponent(workOrder.id)}',
                      );
                      return;
                    }
                    if (!WorkOrderCompletionPolicy.canMarkCompleted(
                      status: workOrder.status,
                      hasSubmittedServiceReport: hasSubmittedServiceReport,
                    )) {
                      return;
                    }
                    final success = await ref
                        .read(workOrderControllerProvider.notifier)
                        .updateStatus(
                          workOrder.id,
                          WorkOrderStatus.closed,
                        );
                    if (!context.mounted) return;
                    if (success) {
                      context.pop();
                    } else {
                      showWorkOrderActionFailedSnackBar(context);
                    }
                  },
            icon: const Icon(Icons.check),
            label: Text(l10n.completeWorkOrder),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
            ),
          ),
          if (profile?.role == UserRole.employee) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: AppColors.surface,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                builder: (_) => LogHoursSheet(workOrderId: workOrder.id),
              ),
              icon: const Icon(Icons.access_time),
              label: Text(l10n.logHours),
            ),
          ],
        ],
        if (WorkOrderDetailActionsPolicy.canReopenWorkOrder(
          canManageStatus: canManageStatus,
          status: workOrder.status,
        )) ...[
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: isLoading
                ? null
                : () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text(l10n.reopenWorkOrder),
                        content: const Text(
                          'Reopen this work order and continue working?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: Text(l10n.reopenWorkOrder),
                          ),
                        ],
                      ),
                    );
                    if (confirm != true) return;
                    final success = await ref
                        .read(workOrderControllerProvider.notifier)
                        .reopenStatus(workOrder.id);
                    if (!context.mounted) return;
                    if (success) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Work order reopened'),
                          backgroundColor: AppColors.primary,
                        ),
                      );
                    } else {
                      showWorkOrderActionFailedSnackBar(context);
                    }
                  },
            icon: const Icon(Icons.refresh),
            label: Text(l10n.reopenWorkOrder),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.warning,
              side: const BorderSide(color: AppColors.warning),
            ),
          ),
        ],
        if (WorkOrderDetailActionsPolicy.canGenerateInvoice(
          isOwner: isOwner,
          status: workOrder.status,
        )) ...[
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: isLoading || invoiceState.isLoading
                ? null
                : () async {
                    final newId = await ref
                        .read(invoiceControllerProvider.notifier)
                        .generateFromWorkOrder(workOrder.id);
                    if (!context.mounted) return;
                    if (newId != null) {
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          SnackBar(
                            content: Text(l10n.invoiceGenerated),
                            backgroundColor: AppColors.success,
                          ),
                        );
                      context.push('$routePrefix/invoices/$newId');
                    } else {
                      final error = ref.read(invoiceControllerProvider).error;
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          SnackBar(
                            content: Text(
                              error == null
                                  ? 'Invoice generation failed.'
                                  : 'Invoice generation failed: $error',
                            ),
                            backgroundColor: AppColors.error,
                          ),
                        );
                    }
                  },
            icon: invoiceState.isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.receipt_long),
            label: Text(l10n.generateInvoice),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E40AF),
            ),
          ),
        ],
      ],
    );
  }
}
