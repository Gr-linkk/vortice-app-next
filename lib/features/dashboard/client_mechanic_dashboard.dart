import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/assets/client_team_asset_access.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/checklists/asset_checklist_template_filter.dart';
import 'package:vortice_app/features/checklists/checklist_provider.dart';
import 'package:vortice_app/features/clients/client_capability_gate.dart';
import 'package:vortice_app/features/work_orders/work_order_provider.dart';
import 'package:vortice_app/models/asset.dart';
import 'package:vortice_app/models/checklist_template.dart';
import 'package:vortice_app/models/client_capability.dart';
import 'package:vortice_app/models/work_order.dart';

// ── Provider: checklist-backed assignments for the current mechanic ─────────

final mechanicAssignedChecklistWorkProvider =
    FutureProvider<List<WorkOrder>>((ref) async {
  final assignedWorkOrders = await ref.watch(workOrdersProvider.future);
  return assignedWorkOrders
      .where((workOrder) => workOrder.checklistTemplateId != null)
      .toList(growable: false);
});

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
  final assignedWork =
      await ref.watch(mechanicAssignedChecklistWorkProvider.future);
  final assetIds =
      assignedWork.map((workOrder) => workOrder.assetId).toSet().toList();

  if (assetIds.isEmpty) return [];

  final parts = await supabase
      .from(AppConstants.tPartsCatalog)
      .select('part_number, description, assets(name)')
      .inFilter('asset_id', assetIds)
      .limit(10);

  return List<Map<String, dynamic>>.from(parts as List);
});

// ── Client Mechanic Dashboard ─────────────────────────────────────────────────

class ClientMechanicDashboard extends ConsumerWidget {
  const ClientMechanicDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).valueOrNull;
    final assignedAsync = ref.watch(mechanicAssignedChecklistWorkProvider);
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
          ref.invalidate(mechanicAssignedChecklistWorkProvider);
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
            // ── 1. Assigned Checklists ─────────────────────────────────
            const _SectionHeader(
              title: 'My Assigned Checklists',
              icon: Icons.build_outlined,
            ),
            assignedAsync.when(
              loading: () => const _LoadingTile(),
              error: (err, _) => _ErrorTile(message: err.toString()),
              data: (orders) {
                if (orders.isEmpty) {
                  return const _EmptyState(
                    icon: Icons.check_circle_outline,
                    message: 'No checklists assigned yet.',
                  );
                }
                return Column(
                  children: orders
                      .map((wo) => _AssignedChecklistCard(workOrder: wo))
                      .toList(),
                );
              },
            ),

            // ── 2. Fleet Checklist Autonomy ───────────────────────────
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
                          'Assignments show priority work. You can also start any mechanic checklist for the fleet and it will save to asset history for Vórtice review.',
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

            // ── 3. Parts Lists ────────────────────────────────────────
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

// ── Assigned Checklist Card ──────────────────────────────────────────────────

class _AssignedChecklistCard extends ConsumerWidget {
  final WorkOrder workOrder;
  const _AssignedChecklistCard({required this.workOrder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const color = AppColors.primary;
    final assetNameAsync = ref.watch(assetNameProvider(workOrder.assetId));
    final scheduledStr = workOrder.scheduledDate != null
        ? DateFormat('MMM d').format(workOrder.scheduledDate!)
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: () => context.push('/client/checklists/${workOrder.id}'),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 50,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      workOrder.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.directions_boat,
                            size: 12, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        assetNameAsync.when(
                          loading: () => const Text('...',
                              style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12)),
                          error: (_, __) => const Text('—',
                              style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12)),
                          data: (name) => Text(
                            name ?? '—',
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 12),
                          ),
                        ),
                        if (scheduledStr != null) ...[
                          const SizedBox(width: 10),
                          const Icon(Icons.calendar_today,
                              size: 12, color: AppColors.textSecondary),
                          const SizedBox(width: 4),
                          Text(
                            scheduledStr,
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Open checklist',
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right,
                  color: AppColors.textSecondary, size: 20),
            ],
          ),
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
