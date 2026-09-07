import 'package:vortice_app/features/assets/asset_type_provider.dart';
import 'package:vortice_app/core/equipment_illustration.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/features/dashboard/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/assets/client_team_asset_access.dart';
import 'package:vortice_app/features/checklists/asset_checklist_template_filter.dart';
import 'package:vortice_app/features/checklists/checklist_provider.dart';
import 'package:vortice_app/features/clients/client_capability_gate.dart';
import 'package:vortice_app/models/asset.dart';
import 'package:vortice_app/models/checklist_template.dart';
import 'package:vortice_app/models/client_capability.dart';

// ── Provider: mechanic checklist autonomy for visible fleet ─────────────────

class _MechanicChecklistOption {
  final Asset asset;
  final ChecklistTemplate template;

  const _MechanicChecklistOption({required this.asset, required this.template});
}

final mechanicAvailableChecklistsProvider =
    FutureProvider<List<_MechanicChecklistOption>>((ref) async {
      final assets = await ref.watch(currentClientFleetAssetsProvider.future);
      final templates = await ref.watch(checklistTemplatesProvider.future);
      final pmTemplates = templates
          .where((template) => template.checklistType == 'pm')
          .toList(growable: false);

      final options = <_MechanicChecklistOption>[];
      for (final asset in assets) {
        final assetTemplates = templatesForAssetChecklist(
          templates: pmTemplates,
          assetTypeId: asset.assetTypeId,
          assetId: asset.id,
          clientId: asset.clientId,
        );
        for (final template in assetTemplates) {
          options.add(
            _MechanicChecklistOption(asset: asset, template: template),
          );
        }
      }
      return options;
    });

// ── Client Mechanic Dashboard ─────────────────────────────────────────────────

class ClientMechanicDashboard extends ConsumerWidget {
  const ClientMechanicDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pmChecklistsAllowedAsync = ref.watch(
      clientCapabilityGateProvider((
        clientId: null,
        capability: ClientCapability.pmChecklists,
      )),
    );
    final availableChecklistsAsync = ref.watch(
      mechanicAvailableChecklistsProvider,
    );
    return Scaffold(
      appBar: const DashboardAppBar(),
      body: DashboardRefresh(
        onRefresh: () async {
          ref.invalidate(mechanicAvailableChecklistsProvider);
          ref.invalidate(
            clientCapabilityGateProvider((
              clientId: null,
              capability: ClientCapability.pmChecklists,
            )),
          );
        },
        child: DashboardList(
          children: [
            const DashboardSection(title: 'Fleet Checklists'),
            pmChecklistsAllowedAsync.when(
              loading: () => const DashboardLoadingTile(),
              error: (err, _) =>
                  DashboardErrorTile(message: friendlyError(context, err)),
              data: (allowed) {
                if (!allowed) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: ClientCapabilityDisabledPanel(
                      capability: ClientCapability.pmChecklists,
                      message:
                          'PM / mechanic checklists are not enabled for this client.',
                    ),
                  );
                }

                return Column(
                  children: [
                    const _HelperTile(
                      icon: Icons.info_outline,
                      message:
                          'Choose a checklist to start. Completed checks are saved in the asset’s history.',
                    ),
                    availableChecklistsAsync.when(
                      loading: () => const DashboardLoadingTile(),
                      error: (err, _) =>
                          DashboardErrorTile(message: friendlyError(context, err)),
                      data: (options) {
                        if (options.isEmpty) {
                          return const DashboardEmptyState(
                            icon: Icons.checklist_outlined,
                            message:
                                'No mechanic checklists are configured for this fleet yet.',
                          );
                        }
                        return Column(
                          children: options
                              .map(
                                (option) =>
                                    _AvailableChecklistCard(option: option),
                              )
                              .toList(),
                        );
                      },
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ── Available Checklist Card ─────────────────────────────────────────────────

class _AvailableChecklistCard extends ConsumerWidget {
  final _MechanicChecklistOption option;
  const _AvailableChecklistCard({required this.option});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asset = option.asset;
    final typeName = ref
        .watch(assetTypesProvider)
        .valueOrNull
        ?.where((type) => type.id == asset.assetTypeId)
        .firstOrNull
        ?.name;

    final template = option.template;
    final query = Uri(
      path: '/client/assets/${asset.id}/checklists/new',
      queryParameters: {
        'clientId': asset.clientId,
        'name': asset.name,
        'assetTypeId': asset.assetTypeId,
        'templateId': template.id,
      },
    ).toString();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: EquipmentIllustration(
          assetTypeId: asset.assetTypeId,
          typeName: typeName,
          size: 48,
        ),
        title: Text(template.name),
        subtitle: Text(
          '${asset.name} · ${dashboardText(context, 'Start checklist', 'Iniciar revisión')}',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push(query),
      ),
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────



class _HelperTile extends StatelessWidget {
  final IconData icon;
  final String message;
  const _HelperTile({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.appColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: context.appColors.primary.withValues(alpha: 0.18),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: context.appColors.primary, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: context.appColors.textPrimary,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
