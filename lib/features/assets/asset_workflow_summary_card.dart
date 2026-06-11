import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/assets/asset_detail_support.dart';
import 'package:vortice_app/features/assets/asset_workflow_summary.dart';
import 'package:vortice_app/models/profile.dart';

class AssetWorkflowSummaryCard extends ConsumerWidget {
  final String assetId;
  final UserRole? role;

  const AssetWorkflowSummaryCard({
    super.key,
    required this.assetId,
    required this.role,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(
      assetWorkflowSummaryProvider((assetId: assetId, role: role)),
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: const Border.fromBorderSide(
            BorderSide(color: AppColors.cardBorder)),
      ),
      child: summaryAsync.when(
        loading: () => const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AssetWorkflowSummaryHeader(),
            SizedBox(height: 12),
            LinearProgressIndicator(),
          ],
        ),
        error: (_, __) => const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AssetWorkflowSummaryHeader(),
            SizedBox(height: 8),
            Text(
              'Workflow summary unavailable.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
        ),
        data: (summary) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AssetWorkflowSummaryHeader(),
            const SizedBox(height: 12),
            if (summary.canSeeMaintenanceChecklist)
              AssetWorkflowSummaryLine(
                icon: Icons.build_circle_outlined,
                label: 'Latest maintenance',
                value: formatAssetChecklistSummaryValue(
                  summary.latestMaintenanceChecklist,
                ),
              ),
            if (summary.canSeeOperationsChecklist)
              AssetWorkflowSummaryLine(
                icon: Icons.fact_check_outlined,
                label: 'Latest operations',
                value: formatAssetChecklistSummaryValue(
                  summary.latestOperationsChecklist,
                ),
              ),
            if (summary.pmDueSummary.visible)
              AssetWorkflowSummaryLine(
                icon: Icons.event_busy_outlined,
                label: 'Due/overdue PM',
                value: formatAssetPmDueSummaryValue(summary.pmDueSummary),
                highlight: summary.pmDueSummary.dueOrOverdueCount > 0,
              ),
            if (summary.openServiceRequestCount != null)
              AssetWorkflowSummaryLine(
                icon: Icons.support_agent_outlined,
                label: 'New service requests',
                value: '${summary.openServiceRequestCount}',
                highlight: summary.openServiceRequestCount! > 0,
              ),
          ],
        ),
      ),
    );
  }
}

class AssetWorkflowSummaryHeader extends StatelessWidget {
  const AssetWorkflowSummaryHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(
          Icons.dashboard_customize_outlined,
          color: AppColors.primary,
          size: 18,
        ),
        const SizedBox(width: 8),
        Text('Summary', style: Theme.of(context).textTheme.titleSmall),
      ],
    );
  }
}

class AssetWorkflowSummaryLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool highlight;

  const AssetWorkflowSummaryLine({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 16,
            color: highlight ? AppColors.warning : AppColors.textSecondary,
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 132,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: highlight ? AppColors.warning : AppColors.textPrimary,
                fontSize: 12,
                fontWeight: highlight ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
