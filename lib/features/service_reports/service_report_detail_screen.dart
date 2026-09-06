import 'package:vortice_app/core/user_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/service_reports/service_report_provider.dart';
import 'package:vortice_app/features/service_reports/service_report_screen.dart';
import 'package:vortice_app/features/service_reports/service_report_workflow.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/models/service_report.dart';

class ServiceReportDetailScreen extends ConsumerWidget {
  final String reportId;
  const ServiceReportDetailScreen({super.key, required this.reportId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (reportId == 'new') {
      return ServiceReportScreen(
        initialWorkOrderId:
            GoRouterState.of(context).uri.queryParameters['workOrderId'],
      );
    }

    final l10n = AppLocalizations.of(context);
    final profileAsync = ref.watch(profileProvider);
    final role = profileAsync.valueOrNull?.role;
    if (profileAsync.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!ServiceReportWorkflow.canViewReport(role)) {
      return const Scaffold(
        body: Center(
          child: Text(
            'Service reports are not available for this role.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }
    final reportAsync = ref.watch(serviceReportByIdProvider(reportId));

    return Scaffold(
      appBar: AppBar(title: const Text('Service Report Detail')),
      body: reportAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => AppErrorState(error: err, onRetry: () => ref.invalidate(serviceReportByIdProvider(reportId))),
        data: (report) {
          if (report == null) {
            return Center(child: Text(l10n.notFound));
          }
          return _ReportBody(report: report, l10n: l10n);
        },
      ),
    );
  }
}

class _ReportBody extends StatelessWidget {
  final ServiceReport report;
  final AppLocalizations l10n;

  const _ReportBody({required this.report, required this.l10n});

  @override
  Widget build(BuildContext context) {
    final date = report.createdAt != null
        ? DateFormat('MMMM d, yyyy · h:mm a').format(report.createdAt!)
        : '—';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1A2C45), Color(0xFF0F1722)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              border: const Border.fromBorderSide(
                  BorderSide(color: AppColors.cardBorder)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.description_outlined,
                        color: AppColors.primary, size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      'SERVICE REPORT',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const Spacer(),
                    if (report.techSignatureUrl != null)
                      const Row(
                        children: [
                          Icon(Icons.draw_outlined,
                              size: 13, color: AppColors.success),
                          SizedBox(width: 4),
                          Text(
                            'Signed',
                            style: TextStyle(
                                color: AppColors.success,
                                fontSize: 12,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'WO: ${report.workOrderId.substring(0, 8).toUpperCase()}',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined,
                        size: 12, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Text(
                      date,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (report.complaint != null)
            _Section(
              number: '1',
              label: l10n.srComplaint,
              content: report.complaint!,
              color: AppColors.error,
            ),
          if (report.cause != null)
            _Section(
              number: '2',
              label: l10n.srCause,
              content: report.cause!,
              color: AppColors.warning,
            ),
          if (report.correction != null)
            _Section(
              number: '3',
              label: l10n.srCorrection,
              content: report.correction!,
              color: AppColors.success,
            ),
          if (report.collateral != null)
            _Section(
              number: '4',
              label: l10n.srSecondaryDamage,
              content: report.collateral!,
              color: AppColors.primary,
            ),
          if (report.comments != null)
            _Section(
              number: '5',
              label: l10n.srComments,
              content: report.comments!,
              color: AppColors.textSecondary,
            ),
          if (report.techSignatureUrl != null) ...[
            const SizedBox(height: 8),
            _sectionHeader(context, l10n.technicianSignature),
            const SizedBox(height: 8),
            Container(
              height: 120,
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.divider),
              ),
              clipBehavior: Clip.hardEdge,
              child: Image.network(
                report.techSignatureUrl!,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(Icons.broken_image_outlined,
                      color: AppColors.textSecondary),
                ),
              ),
            ),
            if (report.signedAt != null) ...[
              const SizedBox(height: 6),
              Text(
                'Signed ${DateFormat('MMM d, yyyy · h:mm a').format(report.signedAt!)}',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 11),
              ),
            ],
          ],
          _ServiceReportPhotosSection(reportId: report.id),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Text(
      title.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppColors.primary,
            letterSpacing: 1.2,
          ),
    );
  }
}

class _ServiceReportPhotosSection extends ConsumerWidget {
  final String reportId;

  const _ServiceReportPhotosSection({required this.reportId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photosAsync = ref.watch(serviceReportPhotosProvider(reportId));

    return photosAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (photos) {
        if (photos.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Text(
              'PHOTOS',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.primary,
                    letterSpacing: 1.2,
                  ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 112,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: photos.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, index) {
                  final photo = photos[index];
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      photo.photoUrl,
                      width: 112,
                      height: 112,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 112,
                        height: 112,
                        color: AppColors.surfaceVariant,
                        child: const Icon(
                          Icons.broken_image_outlined,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  final String number;
  final String label;
  final String content;
  final Color color;

  const _Section({
    required this.number,
    required this.label,
    required this.content,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
              ),
              child: Center(
                child: Text(
                  number,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      content,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
