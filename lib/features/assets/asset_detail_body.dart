import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/localized_text.dart';
import 'package:vortice_app/features/agent_access/maintenance_documents_screen.dart';
import 'package:vortice_app/models/profile.dart';
import 'asset_context_sections.dart';
import 'asset_meter_card.dart';
import 'package:vortice_app/features/maintenance/maintenance_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/equipment_illustration.dart';
import 'package:vortice_app/features/assets/asset_type_provider.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/fleet/fleet_entry_card.dart';
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
    final profile = ref.watch(profileProvider).valueOrNull;
    final role = profile?.role;
    final prefix = AssetWorkflowPolicy.routePrefixForRole(role);
    final types =
        ref.watch(assetTypesProvider).valueOrNull ?? const <AssetType>[];
    final typeName = types
        .where((type) => type.id == asset.assetTypeId)
        .firstOrNull
        ?.name;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: context.appColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.fromBorderSide(
              BorderSide(color: context.appColors.cardBorder),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  EquipmentIllustration(
                    assetTypeId: asset.assetTypeId,
                    typeName: typeName,
                    size: 92,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          asset.name,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (asset.model != null || asset.make != null)
                          Text(
                            [
                              asset.make,
                              asset.model,
                            ].whereType<String>().join(' · '),
                            style: TextStyle(
                              color: context.appColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        if (asset.serialNumber?.isNotEmpty == true)
                          Text('${l10n.serialNumber}: ${asset.serialNumber}'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AssetReadinessCard(assetId: asset.id),
        const SizedBox(height: 12),
        AssetCustodySection(assetId: asset.id),
        AssetMeterCard(asset: asset),
        AssetCurrentWorkSection(assetId: asset.id),
        AssetInspectionsSection(assetId: asset.id),
        if (AssetWorkflowPolicy.canStartClientChecklist(role)) ...[
          const SizedBox(height: 16),
          ClientCapabilityGate(
            clientId: asset.clientId,
            capability: ClientCapability.pmChecklists,
            loadingBuilder: (_) => const SizedBox.shrink(),
            errorBuilder: (_, __) => const SizedBox.shrink(),
            blockedBuilder: (_) => const SizedBox.shrink(),
            allowedBuilder: (_) =>
                AssetStartChecklistCard(asset: asset, routePrefix: prefix),
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
        if (AssetWorkflowPolicy.canManageProfile(profile)) ...[
          const SizedBox(height: 16),
          AssetEnginesCard(assetId: asset.id, routePrefix: ''),
        ],
        if (canUseMaintenance(role)) ...[
          const SizedBox(height: 16),
          AssetMaintenancePlanCard(assetId: asset.id),
        ],
        const SizedBox(height: 16),
        AssetTelemetrySection(asset: asset),
        if ([
          UserRole.owner,
          UserRole.client,
          UserRole.clientAdmin,
        ].contains(role))
          Card(
            child: ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: Text(
                localizedText(
                  context,
                  'Company manuals & procedures',
                  'Manuales y procedimientos de la empresa',
                  'Manuels et procédures de l’entreprise',
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => MaintenanceDocumentsScreen(
                    fleet: asset.clientId,
                    fleetName: asset.name,
                  ),
                ),
              ),
            ),
          ),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.forum_outlined),
                title: Text(
                  localizedText(
                    context,
                    'Asset discussion',
                    'Conversación del equipo',
                    'Discussion sur l’équipement',
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/discussion/asset/${asset.id}'),
              ),
              ListTile(
                leading: const Icon(Icons.history),
                title: Text(
                  localizedText(
                    context,
                    'Full asset history',
                    'Historial completo',
                    'Historique complet de l’équipement',
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/history/assets/${asset.id}'),
              ),
            ],
          ),
        ),
        Card(
          child: ExpansionTile(
            title: Text(l10n.assetDetails),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            children: [
              AssetDetailRow(
                label: l10n.serialNumber,
                value: asset.serialNumber,
              ),
              AssetDetailRow(label: l10n.year, value: asset.year?.toString()),
              if (AssetWorkflowPolicy.canManageAsset(role))
                AssetClientAssignRow(asset: asset),
            ],
          ),
        ),
        if (asset.notes != null) ...[
          const SizedBox(height: 8),
          AssetDetailSectionHeader(title: l10n.notes),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Text(
              asset.notes!,
              style: TextStyle(color: context.appColors.textSecondary),
            ),
          ),
        ],
      ],
    );
  }
}
