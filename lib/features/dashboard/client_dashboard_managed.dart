import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/assets/asset_provider.dart';
import 'package:vortice_app/features/operator/operator_runs_provider.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/invoices/invoice_provider.dart';
import 'package:vortice_app/features/notifications/notification_provider.dart';
import 'package:vortice_app/features/service_reports/service_report_provider.dart';
import 'package:vortice_app/models/asset.dart';
import 'package:vortice_app/models/invoice.dart';

/// Managed Tier (T1+) client dashboard.
/// Clients do NOT see work orders — only service reports, invoices, vessels, flags.
class ClientDashboardManaged extends ConsumerWidget {
  const ClientDashboardManaged({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).valueOrNull;
    final assetsAsync = ref.watch(visibleAssetsProvider);
    final invoicesAsync = ref.watch(invoicesProvider);
    final reportsAsync = ref.watch(clientServiceReportsProvider);
    final flagsAsync = ref.watch(clientFlaggedIssuesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Dashboard'),
        actions: [
          const _MBellButton(route: '/client/notifications'),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () =>
                ref.read(authControllerProvider.notifier).signOut(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(visibleAssetsProvider);
          ref.invalidate(invoicesProvider);
          ref.invalidate(clientServiceReportsProvider);
          ref.invalidate(clientFlaggedIssuesProvider);
        },
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            // ── Greeting ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
              child: Text(
                'Welcome back${profile?.fullName.isNotEmpty == true ? ', ${profile!.fullName.split(' ').first}' : ''}!',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                DateFormat('EEEE, MMMM d').format(DateTime.now()),
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13),
              ),
            ),

            // ── Scheduled Maintenance ────────────────────────────────────
            const _SectionHeader(title: 'Scheduled Maintenance'),
            const _MEmptyStateTile(
              icon: Icons.event_available_outlined,
              message:
                  'Your Vórtice team will contact you to schedule upcoming work.',
            ),

            // ── Recent Service ───────────────────────────────────────────
            const _SectionHeader(title: 'Recent Service'),
            reportsAsync.when(
              loading: () => const _MLoadingTile(),
              error: (_, __) => const SizedBox.shrink(),
              data: (reports) {
                final thirtyDaysAgo =
                    DateTime.now().subtract(const Duration(days: 30));
                final recent = reports.where((r) {
                  final createdAt = r['created_at'] != null
                      ? DateTime.tryParse(r['created_at'] as String)
                      : null;
                  return createdAt != null && createdAt.isAfter(thirtyDaysAgo);
                }).toList();
                if (recent.isEmpty) {
                  return const _MEmptyStateTile(
                    icon: Icons.history_outlined,
                    message: 'No service in the last 30 days.',
                  );
                }
                return Column(
                  children: recent.take(5).map((r) {
                    final assetName =
                        ((r['work_orders'] as Map<String, dynamic>?)?['assets']
                            as Map<String, dynamic>?)?['name'] as String?;
                    final createdAt = r['created_at'] != null
                        ? DateTime.tryParse(r['created_at'] as String)
                        : null;
                    return ListTile(
                      onTap: () =>
                          context.push('/client/service-reports/${r['id']}'),
                      leading: const CircleAvatar(
                        backgroundColor: AppColors.surfaceVariant,
                        child: Icon(Icons.build_outlined,
                            size: 18, color: AppColors.textSecondary),
                      ),
                      title: Text(
                        r['correction'] as String? ??
                            r['comments'] as String? ??
                            'Service completed',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        [
                          if (assetName != null) assetName,
                          if (createdAt != null)
                            DateFormat('MMM d, yyyy').format(createdAt),
                        ].join(' • '),
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12),
                      ),
                    );
                  }).toList(),
                );
              },
            ),

            // ── Flagged Issues ───────────────────────────────────────────
            flagsAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (flags) {
                if (flags.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionHeader(
                      title: 'Flagged Issues (${flags.length})',
                      color: AppColors.warning,
                    ),
                    ...flags.map((flag) {
                      final assetName = (flag['assets']
                              as Map<String, dynamic>?)?['name'] as String? ??
                          'Unknown vessel';
                      final isUrgent = flag['severity'] == 'urgent';
                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                (isUrgent ? AppColors.error : AppColors.warning)
                                    .withValues(alpha: 0.15),
                            child: Icon(
                              isUrgent ? Icons.warning : Icons.flag,
                              color: isUrgent
                                  ? AppColors.error
                                  : AppColors.warning,
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
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 12),
                          ),
                          trailing: isUrgent
                              ? Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color:
                                        AppColors.error.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'URGENT',
                                    style: TextStyle(
                                        color: AppColors.error,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold),
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

            // ── Service Request Intake ──────────────────────────────────
            const _SectionHeader(title: 'Need Service?'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: ElevatedButton.icon(
                onPressed: () => context.push('/client/service-requests/new'),
                icon: const Icon(Icons.support_agent_outlined),
                label: const Text('Request Service'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),

            // ── My Vessels ───────────────────────────────────────────────
            const _SectionHeader(title: 'My Vessels'),
            assetsAsync.when(
              loading: () => const _MLoadingTile(),
              error: (err, _) => _MErrorTile(message: err.toString()),
              data: (assets) {
                if (assets.isEmpty) {
                  return const _MEmptyStateTile(
                    icon: Icons.directions_boat_outlined,
                    message: 'No vessels yet. Contact Vórtice to get started.',
                  );
                }
                return Column(
                  children: assets.map((a) => _MAssetTile(asset: a)).toList(),
                );
              },
            ),

            // ── Invoices ─────────────────────────────────────────────────
            const _SectionHeader(title: 'Invoices'),
            invoicesAsync.when(
              loading: () => const _MLoadingTile(),
              error: (err, _) => _MErrorTile(message: err.toString()),
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
            const _SectionHeader(title: 'Service Reports'),
            reportsAsync.when(
              loading: () => const _MLoadingTile(),
              error: (_, __) => const SizedBox.shrink(),
              data: (reports) {
                if (reports.isEmpty) {
                  return const _MEmptyStateTile(
                    icon: Icons.assignment_outlined,
                    message: 'No service reports yet.',
                  );
                }
                return Column(
                  children: reports.take(5).map((r) {
                    final assetName =
                        ((r['work_orders'] as Map<String, dynamic>?)?['assets']
                            as Map<String, dynamic>?)?['name'] as String?;
                    final createdAt = r['created_at'] != null
                        ? DateTime.tryParse(r['created_at'] as String)
                        : null;
                    return ListTile(
                      onTap: () =>
                          context.push('/client/service-reports/${r['id']}'),
                      leading: const CircleAvatar(
                        backgroundColor: AppColors.surfaceVariant,
                        child: Icon(Icons.assignment_outlined,
                            size: 18, color: AppColors.textSecondary),
                      ),
                      title: Text(
                        r['correction'] as String? ??
                            r['comments'] as String? ??
                            'Service report',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        [
                          if (assetName != null) assetName,
                          if (createdAt != null)
                            DateFormat('MMM d, yyyy').format(createdAt),
                        ].join(' • '),
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12),
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

class _SectionHeader extends StatelessWidget {
  final String title;
  final Color? color;
  const _SectionHeader({required this.title, this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color),
      ),
    );
  }
}

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
        child: Text(message,
            style: const TextStyle(color: AppColors.error, fontSize: 13)),
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
            Icon(icon, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(message,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13)),
            ),
          ],
        ),
      );
}

// ── Bell button ────────────────────────────────────────────────────────────────

class _MBellButton extends ConsumerWidget {
  final String route;
  const _MBellButton({required this.route});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadCountProvider);
    return Stack(
      children: [
        IconButton(
          icon: const Icon(Icons.notifications_outlined),
          onPressed: () => context.push(route),
        ),
        if (unread > 0)
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              width: 16,
              height: 16,
              decoration: const BoxDecoration(
                color: AppColors.error,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  unread > 9 ? '9+' : '$unread',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Asset tile ─────────────────────────────────────────────────────────────────

class _MAssetTile extends StatelessWidget {
  final Asset asset;
  const _MAssetTile({required this.asset});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: AppColors.surfaceVariant,
          child: Icon(Icons.directions_boat_outlined,
              size: 20, color: AppColors.primary),
        ),
        title: Text(asset.name),
        subtitle: asset.make != null || asset.model != null
            ? Text(
                [asset.make, asset.model].whereType<String>().join(' '),
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12),
              )
            : null,
        trailing: const Icon(Icons.chevron_right,
            color: AppColors.textSecondary, size: 18),
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
    final color = isPaid ? AppColors.success : AppColors.warning;
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
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
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
                color: color, fontSize: 10, fontWeight: FontWeight.bold),
          ),
        ),
        onTap: () => context.push('/client/invoices/${invoice.id}'),
      ),
    );
  }
}

// ── Service report tile ────────────────────────────────────────────────────────
