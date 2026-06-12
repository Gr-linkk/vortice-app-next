import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/service_reports/service_report_provider.dart';
import 'package:vortice_app/features/service_reports/service_report_workflow.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/models/profile.dart';
import 'package:vortice_app/models/work_order.dart';

class WorkOrderServiceReportCard extends ConsumerWidget {
  final WorkOrder workOrder;
  final String routePrefix;
  final UserRole? role;

  const WorkOrderServiceReportCard({
    super.key,
    required this.workOrder,
    required this.routePrefix,
    required this.role,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final canView = ServiceReportWorkflow.canViewReport(role);
    final canAttach = ServiceReportWorkflow.canCreateOrUpdateReport(role) &&
        ServiceReportWorkflow.canAttachReportToWorkOrder(workOrder.status);
    if (!canView && !canAttach) return const SizedBox.shrink();

    final reportsAsync =
        ref.watch(serviceReportsByWorkOrderProvider(workOrder.id));

    return reportsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (reports) {
        if (reports.isEmpty && !canAttach) return const SizedBox.shrink();

        final hasReports = reports.isNotEmpty;
        final latest = hasReports ? reports.first : null;
        final latestDate = latest?.createdAt == null
            ? null
            : DateFormat('MMM d, yyyy').format(latest!.createdAt!.toLocal());
        final encodedWorkOrderId = Uri.encodeComponent(workOrder.id);
        final listRoute =
            '$routePrefix/service-reports?workOrderId=$encodedWorkOrderId';
        final newRoute =
            '$routePrefix/service-reports/new?workOrderId=$encodedWorkOrderId';
        final subtitle = hasReports
            ? '${reports.length} report${reports.length == 1 ? '' : 's'} attached${latestDate == null ? '' : ' • latest $latestDate'}'
            : workOrder.status == WorkOrderStatus.invoiced
                ? 'This work order is invoiced. Add an additional report anyway.'
                : workOrder.status == WorkOrderStatus.closed
                    ? 'This work order is closed. Add a report without reopening it.'
                    : 'Attach a client-visible report to this work order.';

        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: hasReports
              ? (canView ? () => context.push(listRoute) : null)
              : (canAttach ? () => context.push(newRoute) : null),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: const Border.fromBorderSide(
                BorderSide(color: AppColors.cardBorder),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  hasReports
                      ? Icons.description_outlined
                      : Icons.note_add_outlined,
                  color: hasReports ? AppColors.success : AppColors.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasReports
                            ? 'View ${l10n.serviceReportListTitle}'
                            : 'Add ${l10n.serviceReport}',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if ((hasReports && canView) || (!hasReports && canAttach))
                  const Icon(
                    Icons.chevron_right,
                    color: AppColors.textSecondary,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
