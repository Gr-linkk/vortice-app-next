import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/assets/asset_provider.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/dashboard/client_dashboard_managed.dart';
import 'package:vortice_app/features/dashboard/client_mechanic_dashboard.dart';
import 'package:vortice_app/features/dashboard/client_operator_dashboard.dart';
import 'package:vortice_app/features/invoices/invoice_provider.dart';
import 'package:vortice_app/features/notifications/notification_provider.dart';
import 'package:vortice_app/features/service_requests/service_request_provider.dart';
import 'package:vortice_app/models/asset.dart';
import 'package:vortice_app/models/invoice.dart';
import 'package:vortice_app/models/profile.dart';

// ── ClientDashboardRouter — dispatches based on role ────────────────────────

class ClientDashboardRouter extends ConsumerWidget {
  const ClientDashboardRouter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).valueOrNull;
    final role = profile?.role ?? UserRole.client;

    return switch (role) {
      UserRole.clientMechanic => const ClientMechanicDashboard(),
      UserRole.clientOperator => const ClientOperatorDashboard(), // legacy
      UserRole.operator => const ClientOperatorDashboard(), // merged
      _ => const ClientDashboardManaged(),
    };
  }
}

// ── Free Tier Dashboard (T0) ────────────────────────────────────────────────

class ClientDashboardFree extends ConsumerWidget {
  const ClientDashboardFree({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).valueOrNull;
    final assetsAsync = ref.watch(assetsProvider);
    final invoicesAsync = ref.watch(invoicesProvider);
    final serviceRequestsAsync = ref.watch(clientServiceRequestsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Dashboard'),
        actions: [
          const _BellButton(route: '/client/notifications'),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () =>
                ref.read(authControllerProvider.notifier).signOut(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(assetsProvider);
          ref.invalidate(invoicesProvider);
          ref.invalidate(clientServiceRequestsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            // ── Greeting ────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile?.fullName.isNotEmpty == true
                        ? 'Welcome, ${profile!.fullName.split(' ').first}.'
                        : 'Welcome.',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Your Vórtice team is managing your equipment.',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),

            // ── My Vessels ──────────────────────────────────────────────────
            const _SectionHeader(title: 'My Vessels'),
            assetsAsync.when(
              loading: () => const _LoadingTile(),
              error: (err, _) => _ErrorTile(message: err.toString()),
              data: (assets) {
                if (assets.isEmpty) {
                  return const _EmptyStateTile(
                    icon: Icons.directions_boat_outlined,
                    message:
                        'Your vessels will appear here once your technician completes setup.',
                  );
                }
                return Column(
                  children: assets.map((a) => _AssetTile(asset: a)).toList(),
                );
              },
            ),

            // ── Invoices ────────────────────────────────────────────────────
            const _SectionHeader(title: 'Invoices'),
            invoicesAsync.when(
              loading: () => const _LoadingTile(),
              error: (err, _) => _ErrorTile(message: err.toString()),
              data: (invoices) {
                if (invoices.isEmpty) {
                  return const _EmptyStateTile(
                    icon: Icons.receipt_long_outlined,
                    message: 'No invoices yet.',
                  );
                }
                return Column(
                  children: invoices
                      .take(5)
                      .map((inv) => _InvoiceTile(invoice: inv))
                      .toList(),
                );
              },
            ),

            // ── Service Requests ─────────────────────────────────────────────
            const _SectionHeader(title: 'Service Requests'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: ElevatedButton.icon(
                onPressed: () => context.push('/client/service-requests/new'),
                icon: const Icon(Icons.support_agent_outlined),
                label: const Text('Request Service'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            serviceRequestsAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (requests) => requests.isEmpty
                  ? const _EmptyStateTile(
                      icon: Icons.inbox_outlined,
                      message: 'No service requests yet.',
                    )
                  : Column(
                      children: requests.take(3).map((request) {
                        return ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: AppColors.surfaceVariant,
                            child: Icon(Icons.support_agent_outlined,
                                size: 18, color: AppColors.textSecondary),
                          ),
                          title: Text(
                            request.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${request.clientStatusLabel} • ${request.createdLabel}',
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 12),
                          ),
                          onTap: () => context.push('/client/service-requests'),
                        );
                      }).toList(),
                    ),
            ),

            // ── Schedule Consultation Button ─────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
              child: OutlinedButton.icon(
                onPressed: () => context.push('/meeting-request'),
                icon: const Icon(Icons.message_outlined),
                label: const Text('Contact Vórtice'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared sub-widgets ───────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
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

class _EmptyStateTile extends StatelessWidget {
  final IconData icon;
  final String message;
  const _EmptyStateTile({required this.icon, required this.message});

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

class _AssetTile extends StatelessWidget {
  final Asset asset;
  const _AssetTile({required this.asset});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: () => context.push('/client/assets/${asset.id}'),
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
              const Icon(Icons.directions_boat,
                  color: AppColors.primary, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      asset.name,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    if (asset.model != null)
                      Text(
                        asset.model!,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  color: AppColors.textSecondary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _InvoiceTile extends StatelessWidget {
  final Invoice invoice;
  const _InvoiceTile({required this.invoice});

  Color _statusColor() => switch (invoice.status) {
        InvoiceStatus.paid => AppColors.success,
        InvoiceStatus.sent => AppColors.warning,
        InvoiceStatus.draft => AppColors.textSecondary,
        InvoiceStatus.voided => AppColors.error,
      };

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: () => context.push('/client/invoices/${invoice.id}'),
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
              const Icon(Icons.receipt_long_outlined,
                  color: AppColors.primary, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      invoice.invoiceNumber,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    if (invoice.totalUsd != null)
                      Text(
                        '\$${invoice.totalUsd!.toStringAsFixed(2)} USD',
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  invoice.status.name.toUpperCase(),
                  style: TextStyle(
                    color: statusColor,
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

// ── Bell icon with unread badge ──────────────────────────────────────────────

class _BellButton extends ConsumerWidget {
  final String route;
  const _BellButton({required this.route});

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
              width: 17,
              height: 17,
              decoration: const BoxDecoration(
                color: AppColors.error,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  unread > 9 ? '9+' : '$unread',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
