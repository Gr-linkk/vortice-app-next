import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/checklists/checklist_provider.dart';
import 'package:vortice_app/features/parts/pm_kits_screen.dart';
import 'package:vortice_app/features/parts/pm_parts_provider.dart';
import 'package:vortice_app/features/service_intervals/maintenance_work_order_draft.dart';
import 'package:vortice_app/features/service_intervals/service_interval_metric_chip.dart';
import 'package:vortice_app/features/service_intervals/service_interval_provider.dart';
import 'package:vortice_app/models/asset.dart';

class ServiceIntervalCard extends ConsumerWidget {
  final ServiceIntervalSummary summary;
  final String assetId;
  final Asset? asset;
  final bool readOnly;
  final void Function(ServiceIntervalSummary summary)? onEdit;

  const ServiceIntervalCard({
    super.key,
    required this.summary,
    required this.assetId,
    required this.asset,
    required this.readOnly,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final interval = summary.interval;
    final card = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: interval.enabled
              ? AppColors.cardBorder
              : AppColors.cardBorder.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '${interval.intervalHours.toInt()}h',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        interval.label ??
                            '${interval.intervalHours.toInt()}h Service',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: interval.enabled
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    if (!readOnly)
                      IconButton(
                        onPressed: () => onEdit?.call(summary),
                        icon: const Icon(Icons.tune_outlined, size: 18),
                        tooltip: 'Edit schedule',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                ServiceIntervalTemplateLabel(
                    templateId: interval.checklistTemplateId),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (summary.currentHours != null)
                      ServiceIntervalMetricChip(
                        icon: Icons.speed_outlined,
                        label:
                            'Last known ${summary.currentHours!.toStringAsFixed(0)}h',
                      ),
                    if (summary.nextDueHours != null)
                      ServiceIntervalMetricChip(
                        icon: Icons.schedule_outlined,
                        label:
                            'Due ${summary.nextDueHours!.toStringAsFixed(0)}h',
                      ),
                    if (summary.hoursRemaining != null)
                      ServiceIntervalMetricChip(
                        icon: Icons.timelapse_outlined,
                        label:
                            '${summary.hoursRemaining!.toStringAsFixed(0)}h remaining',
                      ),
                  ],
                ),
                if (interval.checklistTemplateId != null) ...[
                  const SizedBox(height: 8),
                  ServiceIntervalPartsSummary(
                    templateId: interval.checklistTemplateId!,
                    fallbackName: interval.label ??
                        '${interval.intervalHours.toInt()}h Service',
                    canEdit: !readOnly,
                  ),
                ],
                if (!readOnly) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _generateWorkOrder(context, ref),
                    icon: const Icon(Icons.add_task_outlined, size: 18),
                    label: const Text('Generate work order'),
                  ),
                ] else if (interval.checklistTemplateId != null &&
                    asset != null) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _startClientChecklist(context),
                    icon:
                        const Icon(Icons.playlist_add_check_outlined, size: 18),
                    label: const Text('Start checklist'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    if (readOnly) return card;

    return Dismissible(
      key: Key(interval.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete Interval'),
            content: Text(
                'Delete the ${interval.intervalHours.toInt()}h service interval?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style:
                    ElevatedButton.styleFrom(backgroundColor: AppColors.error),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (confirmed != true) return false;

        final success = await ref
            .read(serviceIntervalControllerProvider.notifier)
            .deleteInterval(interval.id, assetId);
        if (!success && context.mounted) {
          final error =
              ref.read(serviceIntervalControllerProvider.notifier).lastError;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(error ?? 'Failed to delete interval. Try again.'),
              backgroundColor: AppColors.error,
            ),
          );
        }
        return success;
      },
      child: card,
    );
  }

  void _generateWorkOrder(BuildContext context, WidgetRef ref) {
    final interval = summary.interval;
    final templates = ref.read(checklistTemplatesProvider).valueOrNull;
    final templateName = interval.checklistTemplateId == null
        ? null
        : templates
            ?.where((t) => t.id == interval.checklistTemplateId)
            .firstOrNull
            ?.name;
    final draft = MaintenanceWorkOrderDraft.preventativeMaintenance(
      assetId: assetId,
      intervalHours: interval.intervalHours,
      currentHours: summary.currentHours,
      nextDueHours: summary.nextDueHours,
      intervalLabel: interval.label,
      checklistTemplateId: interval.checklistTemplateId,
      checklistTemplateName: templateName,
    );
    context.push(Uri(
      path: '/owner/work-orders/create',
      queryParameters: draft.toQueryParameters(),
    ).toString());
  }

  void _startClientChecklist(BuildContext context) {
    final targetAsset = asset;
    final templateId = summary.interval.checklistTemplateId;
    if (targetAsset == null || templateId == null) return;

    context.push(Uri(
      path: '/client/assets/$assetId/checklists/new',
      queryParameters: {
        'clientId': targetAsset.clientId,
        'name': targetAsset.name,
        'assetTypeId': targetAsset.assetTypeId,
        'templateId': templateId,
      },
    ).toString());
  }
}

class ServiceIntervalTemplateLabel extends ConsumerWidget {
  final String? templateId;

  const ServiceIntervalTemplateLabel({super.key, required this.templateId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (templateId == null) {
      return const Text(
        'No checklist template',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
      );
    }
    final templatesAsync = ref.watch(checklistTemplatesProvider);
    return templatesAsync.when(
      loading: () => const Text('...',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      error: (_, __) => const Text('—',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      data: (templates) {
        final template = templates.where((t) => t.id == templateId).firstOrNull;
        return Text(
          template?.name ?? 'Unknown template',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        );
      },
    );
  }
}

class ServiceIntervalPartsSummary extends ConsumerWidget {
  final String templateId;
  final String fallbackName;
  final bool canEdit;

  const ServiceIntervalPartsSummary({
    super.key,
    required this.templateId,
    required this.fallbackName,
    required this.canEdit,
  });

  void _showPartsSheet(
      BuildContext context, String templateId, String templateName) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PmPartsListSheet(
        templateId: templateId,
        templateName: templateName,
        canEdit: canEdit,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partsAsync = ref.watch(pmPartsRequirementsProvider(templateId));
    final templatesAsync = ref.watch(checklistTemplatesProvider);

    return partsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (parts) {
        final templateName = templatesAsync.valueOrNull
                ?.where((t) => t.id == templateId)
                .firstOrNull
                ?.name ??
            fallbackName;
        return Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Chip(
              visualDensity: VisualDensity.compact,
              backgroundColor: AppColors.surfaceVariant,
              avatar: const Icon(Icons.inventory_2_outlined, size: 16),
              label:
                  Text('${parts.length} part${parts.length == 1 ? '' : 's'}'),
            ),
            TextButton.icon(
              onPressed: () =>
                  _showPartsSheet(context, templateId, templateName),
              icon: const Icon(Icons.visibility_outlined, size: 16),
              label: Text(canEdit ? 'Review parts' : 'View parts'),
            ),
          ],
        );
      },
    );
  }
}
