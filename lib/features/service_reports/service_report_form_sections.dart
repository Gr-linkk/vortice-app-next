import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/service_reports/service_report_workflow.dart';
import 'package:vortice_app/features/work_orders/work_order_provider.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/models/work_order.dart';

class ServiceReportSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;

  const ServiceReportSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: AppColors.primary, letterSpacing: 0.8),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style:
                  const TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}

class ServiceReportTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final bool requiredField;
  final int minLines;
  final int maxLines;

  const ServiceReportTextField({
    super.key,
    required this.controller,
    required this.hintText,
    this.requiredField = false,
    this.minLines = 2,
    this.maxLines = 3,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TextFormField(
      controller: controller,
      minLines: minLines,
      maxLines: maxLines,
      scrollPadding: const EdgeInsets.fromLTRB(16, 16, 16, 160),
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        hintText: hintText,
        alignLabelWithHint: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      validator: requiredField
          ? (v) => (v == null || v.trim().isEmpty) ? l10n.fieldRequired : null
          : null,
    );
  }
}

class ServiceReportPermissionBanner extends StatelessWidget {
  const ServiceReportPermissionBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.warning.withValues(alpha: 0.35),
        ),
      ),
      child: const Text(
        'Only owner and employee accounts can submit service reports.',
        style: TextStyle(color: AppColors.warning),
      ),
    );
  }
}

class ServiceReportLinkedWorkOrderBanner extends StatelessWidget {
  const ServiceReportLinkedWorkOrderBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Text(
        'Linked to this work order. Fill the 5C fields below.',
        style: TextStyle(color: AppColors.textSecondary),
      ),
    );
  }
}

class ServiceReportWorkOrderSection extends ConsumerWidget {
  final String? selectedWorkOrderId;
  final ValueChanged<String?> onWorkOrderChanged;

  const ServiceReportWorkOrderSection({
    super.key,
    required this.selectedWorkOrderId,
    required this.onWorkOrderChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final workOrdersAsync = ref.watch(workOrdersProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ServiceReportSectionHeader(title: l10n.linkedWorkOrder),
        workOrdersAsync.when(
          loading: () => const LinearProgressIndicator(),
          error: (error, __) => Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'Could not load work orders: $error',
              style: const TextStyle(color: AppColors.error),
            ),
          ),
          data: (orders) {
            final active = orders
                .where((w) =>
                    ServiceReportWorkflow.canAttachReportToWorkOrder(w.status))
                .toList();
            final hasSelectedWorkOrder =
                active.any((w) => w.id == selectedWorkOrderId);
            if (active.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'No cached work orders are available. Reopen from a work order or reconnect and try again.',
                  style: TextStyle(color: AppColors.warning),
                ),
              );
            }
            Widget workOrderLabel(WorkOrder w) => Text(
                  w.status == WorkOrderStatus.closed
                      ? '${w.title} • closed'
                      : w.title,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                );

            final resolvedWorkOrderId =
                hasSelectedWorkOrder ? selectedWorkOrderId : null;

            return DropdownButtonFormField<String>(
              key: ValueKey(
                'service-report-work-order-$resolvedWorkOrderId-${active.length}',
              ),
              initialValue: resolvedWorkOrderId,
              isExpanded: true,
              selectedItemBuilder: (context) => active
                  .map(
                    (w) => Align(
                      alignment: Alignment.centerLeft,
                      child: workOrderLabel(w),
                    ),
                  )
                  .toList(),
              decoration: InputDecoration(
                labelText: l10n.linkedWorkOrder,
                prefixIcon: const Icon(Icons.build_outlined),
              ),
              dropdownColor: AppColors.surfaceVariant,
              items: active
                  .map(
                    (w) => DropdownMenuItem(
                      value: w.id,
                      child: workOrderLabel(w),
                    ),
                  )
                  .toList(),
              onChanged: onWorkOrderChanged,
            );
          },
        ),
      ],
    );
  }
}

class ServiceReportFiveCFieldsSection extends StatelessWidget {
  final TextEditingController complaintController;
  final TextEditingController causeController;
  final TextEditingController correctionController;
  final TextEditingController collateralController;
  final TextEditingController commentsController;

  const ServiceReportFiveCFieldsSection({
    super.key,
    required this.complaintController,
    required this.causeController,
    required this.correctionController,
    required this.collateralController,
    required this.commentsController,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ServiceReportSectionHeader(
          title: l10n.srComplaint,
          subtitle: l10n.srComplaintSub,
        ),
        ServiceReportTextField(
          controller: complaintController,
          hintText: l10n.srComplaintHint,
          requiredField: true,
        ),
        ServiceReportSectionHeader(
          title: l10n.srCause,
          subtitle: l10n.srCauseSub,
        ),
        ServiceReportTextField(
          controller: causeController,
          hintText: l10n.srCauseHint,
          requiredField: true,
        ),
        ServiceReportSectionHeader(
          title: l10n.srCorrection,
          subtitle: l10n.srCorrectionSub,
        ),
        ServiceReportTextField(
          controller: correctionController,
          hintText: l10n.srCorrectionHint,
          requiredField: true,
          maxLines: 4,
        ),
        ServiceReportSectionHeader(
          title: l10n.srSecondaryDamage,
          subtitle: l10n.srSecondaryDamageSub,
        ),
        ServiceReportTextField(
          controller: collateralController,
          hintText: l10n.srSecondaryDamageHint,
        ),
        ServiceReportSectionHeader(
          title: l10n.srComments,
          subtitle: l10n.srCommentsSub,
        ),
        ServiceReportTextField(
          controller: commentsController,
          hintText: l10n.srCommentsHint,
        ),
      ],
    );
  }
}
