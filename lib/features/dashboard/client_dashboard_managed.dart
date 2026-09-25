import 'package:vortice_app/features/assets/asset_type_provider.dart';
import 'package:vortice_app/core/equipment_illustration.dart';
import 'package:vortice_app/features/dashboard/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/core/localized_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/assets/asset_provider.dart';
import 'package:vortice_app/features/assets/asset_workflow_policy.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/operator/operator_runs_provider.dart';
import 'package:vortice_app/features/invoices/invoice_provider.dart';
import 'package:vortice_app/features/service_reports/service_report_provider.dart';
import 'package:vortice_app/models/asset.dart';
import 'package:vortice_app/models/invoice.dart';

/// Company dashboard with equipment, service history and permitted invoices.
class ClientDashboardManaged extends ConsumerWidget {
  const ClientDashboardManaged({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assetsAsync = ref.watch(visibleAssetsProvider);
    final invoicesAsync = ref.watch(invoicesProvider);
    final reportsAsync = ref.watch(clientServiceReportsProvider);
    final flagsAsync = ref.watch(clientFlaggedIssuesProvider);
    final canAddAsset = AssetWorkflowPolicy.canManageProfile(
      ref.watch(profileProvider).valueOrNull,
    );

    return Scaffold(
      appBar: const DashboardAppBar(),
      body: DashboardRefresh(
        onRefresh: () async {
          ref.invalidate(visibleAssetsProvider);
          ref.invalidate(invoicesProvider);
          ref.invalidate(clientServiceReportsProvider);
          ref.invalidate(clientFlaggedIssuesProvider);
        },
        child: DashboardList(
          children: [
            // ── Flagged Issues ───────────────────────────────────────────
            flagsAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (flags) {
                if (flags.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DashboardSection(
                      title:
                          '${localizedText(context, 'Open faults', 'Fallos abiertos', 'Défaillances en cours')} (${flags.length})',
                      color: context.appColors.warning,
                    ),
                    ...flags.map((flag) {
                      final assetName =
                          (flag['assets'] as Map<String, dynamic>?)?['name']
                              as String? ??
                          localizedText(
                            context,
                            'Unknown asset',
                            'Equipo desconocido',
                            'Équipement inconnu',
                          );
                      final isUrgent = flag['severity'] == 'urgent';
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        child: ListTile(
                          onTap: () =>
                              context.push('/fleet/faults/${flag['id']}'),
                          leading: CircleAvatar(
                            backgroundColor:
                                (isUrgent
                                        ? context.appColors.error
                                        : context.appColors.warning)
                                    .withValues(alpha: 0.15),
                            child: Icon(
                              isUrgent ? Icons.warning : Icons.flag,
                              color: isUrgent
                                  ? context.appColors.error
                                  : context.appColors.warning,
                              size: 18,
                            ),
                          ),
                          title: Text(
                            flag['description'] as String? ?? '—',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          subtitle: Text(
                            assetName,
                            style: TextStyle(
                              color: context.appColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          trailing: isUrgent
                              ? Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: context.appColors.error.withValues(
                                      alpha: 0.15,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    localizedText(
                                      context,
                                      'URGENT',
                                      'URGENTE',
                                      'URGENT',
                                    ),
                                    style: TextStyle(
                                      color: context.appColors.error,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                )
                              : null,
                        ),
                      );
                    }),
                    const SizedBox(height: 8),
                  ],
                );
              },
            ),

            // ── Recent Service ───────────────────────────────────────────
            DashboardSection(
              title: localizedText(
                context,
                'Recent service',
                'Servicio reciente',
                'Interventions récentes',
              ),
            ),
            reportsAsync.when(
              loading: () => const _MLoadingTile(),
              error: (_, __) => const SizedBox.shrink(),
              data: (reports) {
                final thirtyDaysAgo = DateTime.now().subtract(
                  const Duration(days: 30),
                );
                final recent = reports.where((r) {
                  final createdAt = r['created_at'] != null
                      ? DateTime.tryParse(r['created_at'] as String)
                      : null;
                  return createdAt != null && createdAt.isAfter(thirtyDaysAgo);
                }).toList();
                if (recent.isEmpty) {
                  return _MEmptyStateTile(
                    icon: Icons.history_outlined,
                    message: localizedText(
                      context,
                      'No service in the last 30 days.',
                      'No hubo servicios en los últimos 30 días.',
                      'Aucune intervention au cours des 30 derniers jours.',
                    ),
                  );
                }
                return Column(
                  children: recent.take(5).map((r) {
                    final assetName =
                        ((r['work_orders'] as Map<String, dynamic>?)?['assets']
                                as Map<String, dynamic>?)?['name']
                            as String?;
                    final createdAt = r['created_at'] != null
                        ? DateTime.tryParse(r['created_at'] as String)
                        : null;
                    return ListTile(
                      onTap: () => context.push(
                        r['maintenance_job_id'] != null
                            ? '/maintenance/jobs/${r['maintenance_job_id']}'
                            : '/client/service-reports/${r['id']}',
                      ),
                      leading: CircleAvatar(
                        backgroundColor: context.appColors.surfaceVariant,
                        child: Icon(
                          Icons.build_outlined,
                          size: 18,
                          color: context.appColors.textSecondary,
                        ),
                      ),
                      title: Text(
                        r['correction'] as String? ??
                            r['comments'] as String? ??
                            localizedText(
                              context,
                              'Service completed',
                              'Servicio completado',
                              'Intervention terminée',
                            ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        [
                          if (assetName != null) assetName,
                          if (createdAt != null)
                            DateFormat.yMMMd(
                              appLocaleCode(context),
                            ).format(createdAt),
                        ].join(' • '),
                        style: TextStyle(
                          color: context.appColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),

            // ── My Assets ────────────────────────────────────────────────
            DashboardSection(
              title: localizedText(
                context,
                'My assets',
                'Mis equipos',
                'Mes équipements',
              ),
            ),
            assetsAsync.when(
              loading: () => const _MLoadingTile(),
              error: (err, _) =>
                  _MErrorTile(message: friendlyError(context, err)),
              data: (assets) {
                if (assets.isEmpty) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _MEmptyStateTile(
                        icon: Icons.inventory_2_outlined,
                        message: canAddAsset
                            ? localizedText(
                                context,
                                'Add your company’s first asset to plan its maintenance.',
                                'Añade el primer equipo de tu empresa para planificar su mantenimiento.',
                                'Ajoutez le premier équipement de votre entreprise pour planifier son entretien.',
                              )
                            : localizedText(
                                context,
                                'No assets available yet. Ask your company owner or manager for access.',
                                'Todavía no hay equipos disponibles. Pide acceso al responsable de tu empresa.',
                                'Aucun équipement n’est disponible pour le moment. Demandez l’accès à la personne responsable de votre entreprise.',
                              ),
                      ),
                      if (canAddAsset)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: FilledButton.icon(
                            onPressed: () => context.push('/assets/new'),
                            icon: const Icon(Icons.add),
                            label: Text(
                              localizedText(
                                context,
                                'Add asset',
                                'Añadir equipo',
                                'Ajouter un équipement',
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                }
                return Column(
                  children: assets.map((a) => _MAssetTile(asset: a)).toList(),
                );
              },
            ),

            // ── Invoices ─────────────────────────────────────────────────
            const DashboardSection(title: 'Invoices'),
            invoicesAsync.when(
              loading: () => const _MLoadingTile(),
              error: (err, _) =>
                  _MErrorTile(message: friendlyError(context, err)),
              data: (invoices) {
                if (invoices.isEmpty) {
                  return const _MEmptyStateTile(
                    icon: Icons.receipt_long_outlined,
                    message: 'No invoices yet.',
                  );
                }
                return Column(
                  children: invoices
                      .take(5)
                      .map((inv) => _MInvoiceTile(invoice: inv))
                      .toList(),
                );
              },
            ),

            // ── Service Reports ───────────────────────────────────────────
            DashboardSection(
              title: localizedText(
                context,
                'Service reports',
                'Informes de servicio',
                'Rapports d’intervention',
              ),
            ),
            reportsAsync.when(
              loading: () => const _MLoadingTile(),
              error: (_, __) => const SizedBox.shrink(),
              data: (reports) {
                if (reports.isEmpty) {
                  return _MEmptyStateTile(
                    icon: Icons.assignment_outlined,
                    message: localizedText(
                      context,
                      'No service reports yet.',
                      'Todavía no hay informes de servicio.',
                      'Aucun rapport d’intervention pour le moment.',
                    ),
                  );
                }
                return Column(
                  children: reports.take(5).map((r) {
                    final assetName =
                        ((r['work_orders'] as Map<String, dynamic>?)?['assets']
                                as Map<String, dynamic>?)?['name']
                            as String?;
                    final createdAt = r['created_at'] != null
                        ? DateTime.tryParse(r['created_at'] as String)
                        : null;
                    return ListTile(
                      onTap: () =>
                          context.push('/client/service-reports/${r['id']}'),
                      leading: CircleAvatar(
                        backgroundColor: context.appColors.surfaceVariant,
                        child: Icon(
                          Icons.assignment_outlined,
                          size: 18,
                          color: context.appColors.textSecondary,
                        ),
                      ),
                      title: Text(
                        r['correction'] as String? ??
                            r['comments'] as String? ??
                            localizedText(
                              context,
                              'Service report',
                              'Informe de servicio',
                              'Rapport d’intervention',
                            ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        [
                          if (assetName != null) assetName,
                          if (createdAt != null)
                            DateFormat.yMMMd(
                              appLocaleCode(context),
                            ).format(createdAt),
                        ].join(' • '),
                        style: TextStyle(
                          color: context.appColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ── Section header ─────────────────────────────────────────────────────────────

// ── Loading / error / empty ────────────────────────────────────────────────────

class _MLoadingTile extends StatelessWidget {
  const _MLoadingTile();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(16),
    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
  );
}

class _MErrorTile extends StatelessWidget {
  final String message;
  const _MErrorTile({required this.message});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Text(
      message,
      style: TextStyle(color: context.appColors.error, fontSize: 13),
    ),
  );
}

class _MEmptyStateTile extends StatelessWidget {
  final IconData icon;
  final String message;
  const _MEmptyStateTile({required this.icon, required this.message});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Row(
      children: [
        Icon(icon, size: 18, color: context.appColors.textSecondary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: TextStyle(
              color: context.appColors.textSecondary,
              fontSize: 13,
            ),
          ),
        ),
      ],
    ),
  );
}

// ── Bell button ────────────────────────────────────────────────────────────────

// ── Asset tile ─────────────────────────────────────────────────────────────────

class _MAssetTile extends ConsumerWidget {
  final Asset asset;
  const _MAssetTile({required this.asset});

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
        subtitle: asset.make != null || asset.model != null
            ? Text(
                [asset.make, asset.model].whereType<String>().join(' '),
                style: TextStyle(
                  color: context.appColors.textSecondary,
                  fontSize: 12,
                ),
              )
            : null,
        trailing: Icon(
          Icons.chevron_right,
          color: context.appColors.textSecondary,
          size: 18,
        ),
        onTap: () => context.push('/client/assets/${asset.id}'),
      ),
    );
  }
}

// ── Invoice tile ───────────────────────────────────────────────────────────────

class _MInvoiceTile extends StatelessWidget {
  final Invoice invoice;
  const _MInvoiceTile({required this.invoice});

  @override
  Widget build(BuildContext context) {
    final isPaid = invoice.status == InvoiceStatus.paid;
    final color = isPaid
        ? context.appColors.success
        : context.appColors.warning;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(
            isPaid ? Icons.check_circle_outline : Icons.receipt_long_outlined,
            color: color,
            size: 18,
          ),
        ),
        title: Text(invoice.invoiceNumber),
        subtitle: Text(
          '\$${(invoice.totalUsd ?? 0).toStringAsFixed(2)} USD',
          style: TextStyle(
            color: context.appColors.textSecondary,
            fontSize: 12,
          ),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            isPaid ? 'PAID' : invoice.status.name.toUpperCase(),
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        onTap: () => context.push('/client/invoices/${invoice.id}'),
      ),
    );
  }
}

// ── Service report tile ────────────────────────────────────────────────────────
