import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/fleet/fleet_entry_card.dart';
import 'package:vortice_app/features/assets/client_team_asset_access.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
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
      options.add(_MechanicChecklistOption(asset: asset, template: template));
    }
  }
  return options;
});

// ── Provider: parts for mechanic's org assets ────────────────────────────────

final mechanicPartsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  await ref.watch(currentClientFleetAssetsProvider.future);
  return const [];
});

// ── Client Mechanic Dashboard ─────────────────────────────────────────────────

class ClientMechanicDashboard extends ConsumerWidget {
  const ClientMechanicDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).valueOrNull;
    final pmChecklistsAllowedAsync = ref.watch(clientCapabilityGateProvider((
      clientId: null,
      capability: ClientCapability.pmChecklists,
    )));
    final pmPartsListsAllowedAsync = ref.watch(clientCapabilityGateProvider((
      clientId: null,
      capability: ClientCapability.pmPartsLists,
    )));
    final showPmPartsLists = pmPartsListsAllowedAsync.valueOrNull ?? false;
    final availableChecklistsAsync =
        ref.watch(mechanicAvailableChecklistsProvider);
    final partsAsync =
        showPmPartsLists ? ref.watch(mechanicPartsProvider) : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          profile?.fullName.split(' ').first != null
              ? 'Hi, ${profile!.fullName.split(' ').first}'
              : 'My Dashboard',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () =>
                ref.read(authControllerProvider.notifier).signOut(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(mechanicAvailableChecklistsProvider);
          ref.invalidate(mechanicPartsProvider);
          ref.invalidate(clientCapabilityGateProvider((
            clientId: null,
            capability: ClientCapability.pmChecklists,
          )));
          ref.invalidate(clientCapabilityGateProvider((
            clientId: null,
            capability: ClientCapability.pmPartsLists,
          )));
        },
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            const FleetEntryCard(),
            const _SectionHeader(
              title: 'Fleet Checklists',
              icon: Icons.checklist_outlined,
            ),
            pmChecklistsAllowedAsync.when(
              loading: () => const _LoadingTile(),
              error: (err, _) => _ErrorTile(message: err.toString()),
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
                          'Start enabled mechanic checklists for your fleet. Submitted runs save to asset history for your Vórtice team to review.',
                    ),
                    availableChecklistsAsync.when(
                      loading: () => const _LoadingTile(),
                      error: (err, _) => _ErrorTile(message: err.toString()),
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
                              .map((option) =>
                                  _AvailableChecklistCard(option: option))
                              .toList(),
                        );
                      },
                    ),
                  ],
                );
              },
            ),
            if (showPmPartsLists) ...[
              const _SectionHeader(
                title: 'Parts Lists',
                icon: Icons.settings_outlined,
              ),
              partsAsync!.when(
                loading: () => const _LoadingTile(),
                error: (err, _) => _ErrorTile(message: err.toString()),
                data: (parts) {
                  if (parts.isEmpty) {
                    return const _EmptyState(
                      icon: Icons.inventory_2_outlined,
                      message: 'No parts catalog entries.',
                    );
                  }
                  return Column(
                    children: parts.map((p) => _PartsTile(part: p)).toList(),
                  );
                },
              ),
            ],
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Row(
          children: [
            const Icon(Icons.fact_check_outlined,
                color: AppColors.primary, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    template.name,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    [
                      asset.name,
                      if (template.intervalHours != null)
                        '${template.intervalHours} hr',
                    ].join(' • '),
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: () => context.push(query),
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                textStyle:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              child: const Text('Start'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Parts Tile ────────────────────────────────────────────────────────────────

class _PartsTile extends StatelessWidget {
  final Map<String, dynamic> part;
  const _PartsTile({required this.part});

  @override
  Widget build(BuildContext context) {
    final assetName =
        (part['assets'] as Map<String, dynamic>?)?['name'] as String? ?? '—';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Row(
          children: [
            const Icon(Icons.settings_outlined,
                color: AppColors.primary, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    part['part_number'] as String? ?? '—',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  if (part['description'] != null)
                    Text(
                      part['description'] as String,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            Text(
              assetName,
              style:
                  const TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 18),
          const SizedBox(width: 8),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}

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
      child: Text(message,
          style: const TextStyle(color: AppColors.error, fontSize: 13)),
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
              BorderSide(color: AppColors.cardBorder)),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.textSecondary, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
