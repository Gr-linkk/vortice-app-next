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
              loading: () => const _LoadingTile(),
              error: (err, _) =>
                  _ErrorTile(message: friendlyError(context, err)),
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
                      loading: () => const _LoadingTile(),
                      error: (err, _) =>
                          _ErrorTile(message: friendlyError(context, err)),
                      data: (options) {
                        if (options.isEmpty) {
                          return const _EmptyState(
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

class _AvailableChecklistCard extends StatelessWidget {
  final _MechanicChecklistOption option;
  const _AvailableChecklistCard({required this.option});

  @override
  Widget build(BuildContext context) {
    final asset = option.asset;
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
        leading: const Icon(Icons.checklist, color: AppColors.primaryLight),
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
      child: Text(
        message,
        style: const TextStyle(color: AppColors.error, fontSize: 13),
      ),
    );
  }
}

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
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: AppColors.textPrimary,
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
            BorderSide(color: AppColors.cardBorder),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.textSecondary, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: AppColors.textSecondary,
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
