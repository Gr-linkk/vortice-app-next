import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/assets/asset_provider.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/invoices/invoice_provider.dart';
import 'package:vortice_app/features/notifications/notification_provider.dart';
import 'package:vortice_app/features/parts/pm_kits_screen.dart';
import 'package:vortice_app/features/reminders/reminder_provider.dart';
import 'package:vortice_app/features/subscription/tier_gate.dart';
import 'package:vortice_app/features/subscription/upgrade_prompt.dart';
import 'package:vortice_app/features/telemetry/telemetry_provider.dart';
import 'package:vortice_app/features/telemetry/telemetry_repository.dart';
import 'package:vortice_app/models/asset.dart';
import 'package:vortice_app/models/invoice.dart';
import 'package:vortice_app/models/subscription_tier.dart';
import 'package:vortice_app/models/telemetry_alert.dart';

/// Telemetry tier (T3+) client dashboard.
/// Shows fleet health, live alerts, fleet grid, maintenance, and invoices.
class ClientDashboardTelemetry extends ConsumerWidget {
  const ClientDashboardTelemetry({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).valueOrNull;

    // Tier gate
    if (!hasTier(profile, SubscriptionTier.telemetry)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Fleet Dashboard')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: UpgradePrompt(requiredTier: SubscriptionTier.telemetry),
          ),
        ),
      );
    }

    final assetsAsync = ref.watch(assetsProvider);
    final invoicesAsync = ref.watch(invoicesProvider);
    final remindersAsync = ref.watch(remindersProvider);
    final clientId = profile?.id;
    final fleetHealthAsync = ref.watch(fleetHealthProvider(clientId));
    final activeAlertsAsync = ref.watch(activeAlertsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fleet Dashboard'),
        actions: [
          _BellButton(route: '/client/notifications'),
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
          ref.invalidate(remindersProvider);
          ref.invalidate(fleetHealthProvider(clientId));
          ref.invalidate(activeAlertsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            // ── Fleet Health Bar ─────────────────────────────────────────────
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: fleetHealthAsync.when(
                loading: () => const _FleetHealthSkeleton(),
                error: (_, __) => const SizedBox.shrink(),
                data: (health) => _FleetHealthBar(health: health),
              ),
            ),

            // ── Active Alerts ────────────────────────────────────────────────
            _SectionHeader(title: 'Active Alerts'),
            activeAlertsAsync.when(
              loading: () => const _LoadingTile(),
              error: (err, _) => _ErrorTile(message: err.toString()),
              data: (alerts) {
                if (alerts.isEmpty) {
                  return Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.success.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: AppColors.success.withOpacity(0.3)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.check_circle,
                              color: AppColors.success, size: 22),
                          SizedBox(width: 12),
                          Text(
                            'All vessels nominal',
                            style: TextStyle(
                                color: AppColors.success,
                                fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return Column(
                  children:
                      alerts.take(5).map((a) => _AlertTile(alert: a)).toList(),
                );
              },
            ),

            // ── Fleet Grid ───────────────────────────────────────────────────
            _SectionHeader(title: 'Fleet'),
            assetsAsync.when(
              loading: () => const _LoadingTile(),
              error: (err, _) => _ErrorTile(message: err.toString()),
              data: (assets) {
                if (assets.isEmpty) {
                  return const _EmptyStateTile(
                    icon: Icons.directions_boat_outlined,
                    message: 'No vessels yet. Contact Vórtice to get started.',
                  );
                }
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 1.2,
                    ),
                    itemCount: assets.length,
                    itemBuilder: (_, i) =>
                        _VesselCard(asset: assets[i], ref: ref),
                  ),
                );
              },
            ),

            // ── Upcoming Maintenance ─────────────────────────────────────────
            _SectionHeader(title: 'Upcoming Maintenance'),
            remindersAsync.when(
              loading: () => const _LoadingTile(),
              error: (err, _) => _ErrorTile(message: err.toString()),
              data: (reminders) {
                if (reminders.isEmpty) {
                  return const _EmptyStateTile(
                    icon: Icons.event_available_outlined,
                    message: 'No upcoming maintenance.',
                  );
                }
                return Column(
                  children: reminders
                      .take(5)
                      .map((r) => _MaintenanceTile(item: r))
                      .toList(),
                );
              },
            ),

            // ── Open Invoices ────────────────────────────────────────────────
            _SectionHeader(title: 'Open Invoices'),
            invoicesAsync.when(
              loading: () => const _LoadingTile(),
              error: (err, _) => _ErrorTile(message: err.toString()),
              data: (invoices) {
                final open = invoices
                    .where((i) =>
                        i.status == InvoiceStatus.sent ||
                        i.status == InvoiceStatus.draft)
                    .toList();
                if (open.isEmpty) {
                  return const _EmptyStateTile(
                    icon: Icons.receipt_long_outlined,
                    message: 'No open invoices.',
                  );
                }
                return Column(
                  children: open
                      .take(5)
                      .map((inv) => _InvoiceTile(invoice: inv))
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ── Fleet Health Bar ──────────────────────────────────────────────────────────

class _FleetHealthBar extends StatelessWidget {
  final FleetHealth health;

  const _FleetHealthBar({required this.health});

  Color get _statusColor {
    if (health.activeAlertCount == 0) return AppColors.success;
    return AppColors.warning;
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _HealthStat(
            icon: Icons.directions_boat,
            value: '${health.vesselCount}',
            label: 'vessels',
            color: AppColors.primary,
          ),
          _Divider(),
          _HealthStat(
            icon: Icons.warning_amber,
            value: '${health.activeAlertCount}',
            label: 'active alerts',
            color: health.activeAlertCount == 0
                ? AppColors.success
                : AppColors.warning,
          ),
          _Divider(),
          _HealthStat(
            icon: Icons.schedule,
            value: '${health.upcomingServiceCount}',
            label: 'services',
            color: AppColors.textSecondary,
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 40,
      color: AppColors.divider,
    );
  }
}

class _HealthStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _HealthStat({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
        ),
      ],
    );
  }
}

class _FleetHealthSkeleton extends StatelessWidget {
  const _FleetHealthSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: const Border.fromBorderSide(
            BorderSide(color: AppColors.cardBorder)),
      ),
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}

// ── Alert Tile ────────────────────────────────────────────────────────────────

class _AlertTile extends ConsumerWidget {
  final TelemetryAlert alert;

  const _AlertTile({required this.alert});

  Color get _severityColor => switch (alert.severity) {
        AlertSeverity.critical => AppColors.error,
        AlertSeverity.warning => AppColors.warning,
        _ => AppColors.primary,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = _severityColor;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: () {
          // Navigate to vessel telemetry — need asset id.
          // We navigate to the engine's telemetry history screen as fallback.
          context.push('/client/engines/${alert.engineId}/telemetry');
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.4)),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
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
                            _alertTitle(),
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                    color: color, fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          _alertSeverityLabel(),
                          style: TextStyle(
                            color: color,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    if (alert.message != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        alert.message!,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (alert.value != null && alert.threshold != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        '${alert.value!.toStringAsFixed(1)} / threshold: ${alert.threshold!.toStringAsFixed(1)}',
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 11),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      _formatAgo(alert.createdAt ?? DateTime.now()),
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  color: AppColors.textSecondary, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  String _alertTitle() {
    if (alert.spn != null) return 'SPN ${alert.spn} / FMI ${alert.fmi ?? '?'}';
    return alert.alertType.name.toUpperCase();
  }

  String _alertSeverityLabel() => switch (alert.severity) {
        AlertSeverity.critical => 'CRITICAL',
        AlertSeverity.warning => 'WARNING',
        _ => 'INFO',
      };

  String _formatAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return DateFormat('MMM d').format(dt);
  }
}

// ── Vessel Card ───────────────────────────────────────────────────────────────

class _VesselCard extends StatelessWidget {
  final Asset asset;
  final WidgetRef ref;

  const _VesselCard({required this.asset, required this.ref});

  @override
  Widget build(BuildContext context) {
    // Check for alerts on this asset
    final alertsAsync = ref.watch(alertsForAssetProvider(asset.id));
    final alertCount = alertsAsync.valueOrNull?.length ?? 0;
    final statusColor = alertCount == 0 ? AppColors.success : AppColors.warning;

    return InkWell(
      onTap: () => context.push('/telemetry/vessel/${asset.id}'),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.directions_boat,
                  color: AppColors.primary,
                  size: 22,
                ),
                const Spacer(),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              asset.name,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (alertCount > 0) ...[
              const SizedBox(height: 2),
              Text(
                '$alertCount alert${alertCount > 1 ? 's' : ''}',
                style: const TextStyle(
                    color: AppColors.warning,
                    fontSize: 11,
                    fontWeight: FontWeight.w500),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Maintenance Tile ──────────────────────────────────────────────────────────

class _MaintenanceTile extends StatelessWidget {
  final ReminderWithAsset item;

  const _MaintenanceTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final remaining = item.hoursRemaining;
    final color = remaining <= 0
        ? AppColors.error
        : remaining <= 10
            ? AppColors.warning
            : AppColors.textSecondary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: item.checklistTemplateId != null
            ? () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => PmPartsListSheet(
                    templateId: item.checklistTemplateId!,
                    templateName:
                        '${item.reminder.intervalHours}HR Service — ${item.assetName}',
                  ),
                )
            : null,
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
              const Icon(Icons.build_outlined,
                  color: AppColors.textSecondary, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.assetName,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(
                      '${item.reminder.intervalHours} hr service',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                    if (item.checklistTemplateId != null)
                      const Text(
                        'Tap to view parts list',
                        style:
                            TextStyle(color: AppColors.primary, fontSize: 11),
                      ),
                  ],
                ),
              ),
              Text(
                remaining <= 0
                    ? 'Overdue'
                    : '${remaining.toStringAsFixed(0)} hrs',
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (item.checklistTemplateId != null) ...[
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right,
                    size: 16, color: AppColors.primary)
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Invoice Tile ──────────────────────────────────────────────────────────────

class _InvoiceTile extends StatelessWidget {
  final Invoice invoice;

  const _InvoiceTile({required this.invoice});

  Color get _statusColor => switch (invoice.status) {
        InvoiceStatus.paid => AppColors.success,
        InvoiceStatus.sent => AppColors.warning,
        InvoiceStatus.draft => AppColors.textSecondary,
        InvoiceStatus.voided => AppColors.error,
      };

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor;
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
                  color: statusColor.withOpacity(0.12),
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

// ── Shared sub-widgets ────────────────────────────────────────────────────────

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

// ── Bell icon with unread badge ───────────────────────────────────────────────

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
