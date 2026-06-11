import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/asset_icons.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/assets/asset_checklist_history_card.dart';
import 'package:vortice_app/features/assets/asset_client_assign_row.dart';
import 'package:vortice_app/features/assets/asset_detail_row.dart';
import 'package:vortice_app/features/assets/asset_detail_section_header.dart';
import 'package:vortice_app/features/assets/asset_engines_card.dart';
import 'package:vortice_app/features/assets/asset_maintenance_plan_card.dart';
import 'package:vortice_app/features/assets/asset_service_reports_card.dart';
import 'package:vortice_app/features/assets/asset_start_checklist_card.dart';
import 'package:vortice_app/features/assets/asset_telemetry_section.dart';
import 'package:vortice_app/features/assets/asset_workflow_policy.dart';
import 'package:vortice_app/features/assets/asset_workflow_summary_card.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/clients/client_capability_gate.dart';
import 'package:vortice_app/features/service_reports/service_report_workflow.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/models/asset.dart';
import 'package:vortice_app/models/client_capability.dart';

class AssetDetailBody extends ConsumerWidget {
  final Asset asset;

  const AssetDetailBody({super.key, required this.asset});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final role = ref.watch(profileProvider).valueOrNull?.role;
    final prefix = AssetWorkflowPolicy.routePrefixForRole(role);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: const Border.fromBorderSide(
                BorderSide(color: AppColors.cardBorder)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                    child: Icon(assetIconFor(asset.assetTypeId),
                        color: AppColors.primary, size: 30),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(asset.name,
                            style: Theme.of(context).textTheme.titleLarge),
                        if (asset.model != null || asset.make != null)
                          Text(
                            [asset.make, asset.model]
                                .whereType<String>()
                                .join(' · '),
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 13),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AssetDetailSectionHeader(title: l10n.assetDetails),
        AssetDetailRow(label: l10n.serialNumber, value: asset.serialNumber),
        AssetDetailRow(label: l10n.year, value: asset.year?.toString()),
        AssetDetailRow(label: l10n.location, value: asset.location),
        if (AssetWorkflowPolicy.canManageAsset(role))
          AssetClientAssignRow(asset: asset),
        const SizedBox(height: 16),
        AssetWorkflowSummaryCard(assetId: asset.id, role: role),
        if (AssetWorkflowPolicy.canStartClientChecklist(role)) ...[
          const SizedBox(height: 16),
          ClientCapabilityGate(
            clientId: asset.clientId,
            capability: ClientCapability.pmChecklists,
            loadingBuilder: (_) => const SizedBox.shrink(),
            errorBuilder: (_, __) => const SizedBox.shrink(),
            blockedBuilder: (_) => const SizedBox.shrink(),
            allowedBuilder: (_) => AssetStartChecklistCard(
              asset: asset,
              routePrefix: prefix,
            ),
          ),
        ],
        if (ServiceReportWorkflow.canViewReport(role)) ...[
          const SizedBox(height: 16),
          AssetServiceReportsCard(asset: asset, routePrefix: prefix),
        ],
        if (AssetWorkflowPolicy.canSeeChecklistHistory(role)) ...[
          const SizedBox(height: 16),
          AssetChecklistHistoryCard(asset: asset, routePrefix: prefix),
        ],
        if (AssetWorkflowPolicy.canSeeEngines(role)) ...[
          const SizedBox(height: 16),
          AssetEnginesCard(assetId: asset.id, routePrefix: prefix),
        ],
        if (AssetWorkflowPolicy.canSeeMaintenancePlan(role)) ...[
          const SizedBox(height: 16),
          ClientCapabilityGate(
            clientId: asset.clientId,
            capability: ClientCapability.maintenancePlanning,
            loadingBuilder: (_) => const SizedBox.shrink(),
            errorBuilder: (_, __) => const SizedBox.shrink(),
            blockedBuilder: (_) => const SizedBox.shrink(),
            allowedBuilder: (_) => AssetMaintenancePlanCard(
              assetId: asset.id,
              routePrefix: prefix,
              readOnly: !AssetWorkflowPolicy.canManageAsset(role),
            ),
          ),
        ],
        const SizedBox(height: 16),
        AssetTelemetrySection(asset: asset),
        if (asset.notes != null) ...[
          const SizedBox(height: 8),
          AssetDetailSectionHeader(title: l10n.notes),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Text(
              asset.notes!,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ],
      ],
    );
  }
}
