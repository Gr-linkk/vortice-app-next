import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/service_reports/service_report_provider.dart';
import 'package:vortice_app/features/service_reports/service_report_workflow.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/models/profile.dart';
import 'package:vortice_app/models/service_report.dart';
import 'package:vortice_app/sync/sync_status.dart';

class ServiceReportListScreen extends ConsumerWidget {
  final String? initialWorkOrderId;
  final String? initialAssetId;

  const ServiceReportListScreen({
    super.key,
    this.initialWorkOrderId,
    this.initialAssetId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final profile = ref.watch(profileProvider).valueOrNull;
    final role = profile?.role;
    final canView = ServiceReportWorkflow.canViewReport(role);
    final canCreate = ServiceReportWorkflow.canCreateOrUpdateReport(role);

    if (!canView) {
      return const Scaffold(
        body: Center(
          child: Text(
            'Service reports are not available for this role.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }
    final prefix = switch (role) {
      UserRole.owner => '/owner',
      UserRole.employee => '/employee',
      UserRole.client ||
      UserRole.clientAdmin ||
      UserRole.clientMechanic =>
        '/client',
      _ => '/owner',
    };

    final reportsAsync = initialWorkOrderId != null
        ? ref.watch(serviceReportsByWorkOrderProvider(initialWorkOrderId!))
        : initialAssetId != null
            ? ref.watch(serviceReportsForAssetProvider(initialAssetId!))
            : ref.watch(serviceReportsProvider);

    final title = initialWorkOrderId != null
        ? 'Work Order Service Reports'
        : initialAssetId != null
            ? 'Asset Service Reports'
            : l10n.serviceReportListTitle;
    final authoringRoute = serviceReportAuthoringRoute(
      prefix: prefix,
      workOrderId: initialWorkOrderId,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      floatingActionButton: canCreate && authoringRoute != null
          ? FloatingActionButton.extended(
              onPressed: () {
                context.push(authoringRoute);
              },
              icon: const Icon(Icons.add),
              label: Text(l10n.newReport),
            )
          : null,
      body: reportsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Text(err.toString(),
              style: const TextStyle(color: AppColors.error)),
        ),
        data: (reports) {
          if (reports.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.description_outlined,
                      size: 56,
                      color: AppColors.textSecondary.withValues(alpha: 0.4)),
                  const SizedBox(height: 12),
                  Text(
                    l10n.noServiceReports,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  if (canCreate && authoringRoute != null) ...[
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () {
                        context.push(authoringRoute);
                      },
                      icon: const Icon(Icons.add),
                      label: Text(l10n.newReport),
                    ),
                  ],
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              if (initialWorkOrderId != null) {
                ref.invalidate(
                    serviceReportsByWorkOrderProvider(initialWorkOrderId!));
                return;
              }
              if (initialAssetId != null) {
                ref.invalidate(serviceReportsForAssetProvider(initialAssetId!));
                return;
              }
              ref.invalidate(serviceReportsProvider);
            },
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              itemCount: reports.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final report = reports[index];
                return _ReportCard(
                  report: report,
                  onTap: () =>
                      context.push('$prefix/service-reports/${report.id}'),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

String? serviceReportAuthoringRoute({
  required String prefix,
  required String? workOrderId,
}) {
  if (workOrderId == null || workOrderId.isEmpty) return null;
  final encodedWorkOrderId = Uri.encodeComponent(workOrderId);
  return '$prefix/service-reports/new-v2?workOrderId=$encodedWorkOrderId';
}

class _ReportCard extends StatelessWidget {
  final ServiceReport report;
  final VoidCallback onTap;

  const _ReportCard({required this.report, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final date = report.createdAt != null
        ? DateFormat('MMM d, yyyy').format(report.createdAt!)
        : '—';
    final hasSig = report.techSignatureUrl != null;

    return InkWell(
      onTap: onTap,
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
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.description_outlined,
                  color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Report — ${report.workOrderId.substring(0, 8).toUpperCase()}',
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      if (report.syncStatus != SyncStatusValues.synced) ...[
                        _ReportSyncChip(syncStatus: report.syncStatus),
                        const SizedBox(width: 6),
                      ],
                      if (hasSig)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.draw_outlined,
                                  size: 10, color: AppColors.success),
                              SizedBox(width: 3),
                              Text(
                                'Signed',
                                style: TextStyle(
                                  color: AppColors.success,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (report.complaint != null)
                    Text(
                      report.complaint!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.calendar_today_outlined,
                          size: 11, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        date,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right,
                color: AppColors.textSecondary, size: 20),
          ],
        ),
      ),
    );
  }
}

class _ReportSyncChip extends StatelessWidget {
  final String syncStatus;

  const _ReportSyncChip({required this.syncStatus});

  @override
  Widget build(BuildContext context) {
    final isFailed = syncStatus == SyncStatusValues.failed ||
        syncStatus == SyncStatusValues.conflict;
    final color = isFailed ? AppColors.error : AppColors.warning;
    final label = isFailed ? 'Sync failed' : 'Pending sync';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
