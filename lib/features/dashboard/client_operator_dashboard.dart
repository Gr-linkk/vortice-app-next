import 'package:vortice_app/features/assets/asset_type_provider.dart';
import 'package:vortice_app/core/equipment_illustration.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/core/localized_text.dart';
import 'package:vortice_app/features/dashboard/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/assets/client_team_asset_access.dart';
import 'package:vortice_app/features/checklists/checklist_assignment_provider.dart';
import 'package:vortice_app/features/clients/client_capability_gate.dart';
import 'package:vortice_app/models/asset.dart';
import 'package:vortice_app/models/client_capability.dart';

// ── Provider: recent pre-departure checklist runs for this operator ──────────

final clientOperatorRecentRunsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return [];

      final data = await supabase
          .from(AppConstants.tOperatorChecklistRuns)
          .select('id, run_type, completed_at, assets(name)')
          .eq('operator_id', userId)
          .order('created_at', ascending: false)
          .limit(10);

      return List<Map<String, dynamic>>.from(data as List);
    });

// ── Client Operator Dashboard ─────────────────────────────────────────────────

class ClientOperatorDashboard extends ConsumerWidget {
  const ClientOperatorDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assetsAsync = ref.watch(currentClientFleetAssetsProvider);
    final runsAsync = ref.watch(clientOperatorRecentRunsProvider);
    final operationalChecklistsAllowedAsync = ref.watch(
      clientCapabilityGateProvider((
        clientId: null,
        capability: ClientCapability.operationalChecklists,
      )),
    );
    final showOperationalChecklists =
        operationalChecklistsAllowedAsync.valueOrNull ?? false;
    final assignedChecklistsAsync = showOperationalChecklists
        ? ref.watch(myChecklistAssignmentsProvider)
        : null;

    return Scaffold(
      appBar: const DashboardAppBar(),
      body: DashboardRefresh(
        onRefresh: () async {
          ref.invalidate(currentClientFleetAssetsProvider);
          ref.invalidate(clientOperatorRecentRunsProvider);
          ref.invalidate(myChecklistAssignmentsProvider);
          ref.invalidate(
            clientCapabilityGateProvider((
              clientId: null,
              capability: ClientCapability.operationalChecklists,
            )),
          );
        },
        child: DashboardList(
          children: [
            if (!showOperationalChecklists)
              const Padding(
                padding: EdgeInsets.all(16),
                child: ClientCapabilityDisabledPanel(
                  capability: ClientCapability.operationalChecklists,
                  message:
                      'Operational checklists are not enabled for this client.',
                ),
              ),

            // ── 0. Assigned Pre-Op Checklists (from client admin) ──────────
            if (showOperationalChecklists)
              assignedChecklistsAsync!.when(
                loading: () => const DashboardLoadingTile(),
                error: (error, _) => AppErrorState(
                  error: error,
                  onRetry: () => ref.invalidate(myChecklistAssignmentsProvider),
                ),
                data: (assignments) {
                  if (assignments.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Text(
                        dashboardText(
                          context,
                          'No checklists assigned to you.',
                          'No tienes revisiones asignadas.',
                          'Aucune inspection ne vous est attribuée.',
                        ),
                      ),
                    );
                  }
                  final ordered = [...assignments]
                    ..sort((a, b) {
                      const ranks = {
                        'in_progress': 0,
                        'pending': 1,
                        'completed': 2,
                      };
                      return (ranks[a['status']] ?? 1).compareTo(
                        ranks[b['status']] ?? 1,
                      );
                    });
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DashboardSection(
                        title: 'Assigned Checklists (${assignments.length})',
                      ),
                      ...ordered.map((a) {
                        final template =
                            a['checklist_templates'] as Map<String, dynamic>?;
                        final asset = a['assets'] as Map<String, dynamic>?;
                        final status = a['status'] as String? ?? 'pending';
                        final statusColor = switch (status) {
                          'completed' => context.appColors.success,
                          'in_progress' => context.appColors.warning,
                          _ => context.appColors.primary,
                        };
                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: context.appColors.warning
                                  .withValues(alpha: 0.1),
                              child: Icon(
                                Icons.checklist_outlined,
                                size: 18,
                                color: context.appColors.warning,
                              ),
                            ),
                            title: Text(
                              template?['name'] as String? ?? 'Checklist',
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: asset?['name'] != null
                                ? Text(
                                    asset!['name'] as String,
                                    style: TextStyle(
                                      color: context.appColors.textSecondary,
                                      fontSize: 12,
                                    ),
                                  )
                                : null,
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                status.replaceAll('_', ' ').toUpperCase(),
                                style: TextStyle(
                                  color: statusColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            onTap: () async {
                              if (status == 'completed') {
                                if (asset?['id'] != null) {
                                  context.push(
                                    '/operator/assets/${asset!['id']}/checklist-history',
                                  );
                                }
                                return;
                              }
                              if (status == 'pending') {
                                await ChecklistAssignmentController.markInProgress(
                                  a['id'] as String,
                                );
                                ref.invalidate(myChecklistAssignmentsProvider);
                                ref.invalidate(
                                  clientCapabilityGateProvider((
                                    clientId: null,
                                    capability:
                                        ClientCapability.operationalChecklists,
                                  )),
                                );
                              }
                              final query = <String, String>{
                                'assignmentId': a['id'] as String,
                                if (asset?['id'] != null)
                                  'assetId': asset!['id'] as String,
                                if (template?['id'] != null)
                                  'templateId': template!['id'] as String,
                              };
                              if (context.mounted) {
                                context.push(
                                  Uri(
                                    path: '/operator/checklist',
                                    queryParameters: query.isEmpty
                                        ? null
                                        : query,
                                  ).toString(),
                                );
                              }
                            },
                          ),
                        );
                      }),
                      const SizedBox(height: 8),
                    ],
                  );
                },
              ),

            // ── 1. Pre-Departure Checklists ───────────────────────────
            if (showOperationalChecklists) ...[
              DashboardSection(
                title: localizedText(
                  context,
                  'Pre-operation checks',
                  'Revisiones antes de operar',
                  'Inspections avant utilisation',
                ),
              ),
              assetsAsync.when(
                loading: () => const DashboardLoadingTile(),
                error: (err, _) =>
                    DashboardErrorTile(message: friendlyError(context, err)),
                data: (assets) {
                  if (assets.isEmpty) {
                    return DashboardEmptyState(
                      icon: Icons.directions_boat_outlined,
                      message: localizedText(
                        context,
                        'No assets assigned.',
                        'No hay equipos asignados.',
                        'Aucun équipement ne vous est attribué.',
                      ),
                    );
                  }
                  return Column(
                    children: assets
                        .map((asset) => _AssetChecklistCard(asset: asset))
                        .toList(),
                  );
                },
              ),
            ],

            if (showOperationalChecklists) ...[
              // ── 3. Recent Checks ──────────────────────────────────────
              DashboardSection(
                title: localizedText(
                  context,
                  'Recent checks',
                  'Revisiones recientes',
                  'Inspections récentes',
                ),
              ),
              runsAsync.when(
                loading: () => const DashboardLoadingTile(),
                error: (err, _) =>
                    DashboardErrorTile(message: friendlyError(context, err)),
                data: (runs) {
                  if (runs.isEmpty) {
                    return DashboardEmptyState(
                      icon: Icons.history_outlined,
                      message: localizedText(
                        context,
                        'No completed checks yet.',
                        'Todavía no hay revisiones completadas.',
                        'Aucune inspection terminée pour le moment.',
                      ),
                    );
                  }
                  return Column(
                    children: runs
                        .map((run) => _RecentRunTile(run: run))
                        .toList(),
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

// ── Asset Checklist Card ──────────────────────────────────────────────────────

class _AssetChecklistCard extends ConsumerWidget {
  final Asset asset;
  const _AssetChecklistCard({required this.asset});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final typeName = ref
        .watch(assetTypesProvider)
        .valueOrNull
        ?.where((type) => type.id == asset.assetTypeId)
        .firstOrNull
        ?.name;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: EquipmentIllustration(
          assetTypeId: asset.assetTypeId,
          typeName: typeName,
          size: 48,
        ),
        title: Text(asset.name),
        subtitle: Text(
          dashboardText(
            context,
            'Start checklist',
            'Iniciar revisión',
            'Commencer une inspection',
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/operator/checklist?assetId=${asset.id}'),
      ),
    );
  }
}

// ── Recent Run Tile ───────────────────────────────────────────────────────────

class _RecentRunTile extends StatelessWidget {
  final Map<String, dynamic> run;
  const _RecentRunTile({required this.run});

  @override
  Widget build(BuildContext context) {
    final assetName =
        (run['assets'] as Map<String, dynamic>?)?['name'] as String? ?? '—';
    final completedAt = run['completed_at'] != null
        ? DateTime.tryParse(run['completed_at'] as String)
        : null;
    final dateStr = completedAt != null
        ? DateFormat('MMM d, yyyy').format(completedAt.toLocal())
        : 'In progress';
    final runType = run['run_type'] as String? ?? 'pre_departure';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.appColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.appColors.cardBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: context.appColors.success.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_circle_outline,
                color: context.appColors.success,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    assetName,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: context.appColors.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    dateStr,
                    style: TextStyle(
                      color: context.appColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: context.appColors.success.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                runType.replaceAll('_', ' ').toUpperCase(),
                style: TextStyle(
                  color: context.appColors.success,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
