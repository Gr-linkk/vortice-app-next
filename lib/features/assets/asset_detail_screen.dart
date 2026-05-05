import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/asset_icons.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/assets/asset_provider.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/engines/engine_provider.dart';
import 'package:vortice_app/features/service_intervals/service_interval_provider.dart';
import 'package:vortice_app/features/telemetry/telemetry_provider.dart';
import 'package:vortice_app/features/telemetry/device_pairing_screen.dart';
import 'package:vortice_app/features/subscription/tier_gate.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/features/assets/edit_asset_screen.dart';
import 'package:vortice_app/models/asset.dart';
import 'package:vortice_app/models/asset_engine.dart';
import 'package:vortice_app/models/asset_service_interval.dart';
import 'package:vortice_app/features/clients/client_provider.dart';
import 'package:vortice_app/models/profile.dart';
import 'package:vortice_app/models/subscription_tier.dart';

class AssetDetailScreen extends ConsumerWidget {
  final String assetId;
  const AssetDetailScreen({super.key, required this.assetId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final assetAsync = ref.watch(assetByIdProvider(assetId));
    final profile = ref.watch(profileProvider).valueOrNull;
    final canEdit = profile?.role == UserRole.owner;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.assetDetail),
        actions: [
          if (canEdit)
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: l10n.edit,
              onPressed: () async {
                final asset = assetAsync.valueOrNull;
                if (asset == null) return;
                final updated = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EditAssetScreen(asset: asset),
                  ),
                );
                if (updated == true) {
                  ref.invalidate(assetByIdProvider(assetId));
                }
              },
            ),
          if (canEdit)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (v) async {
                if (v == 'delete') {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: AppColors.surface,
                      title: Text(l10n.confirmDelete),
                      content: Text(l10n.confirmDeleteMessage),
                      actions: [
                        TextButton(
                          onPressed: () => ctx.pop(false),
                          child: Text(l10n.cancel),
                        ),
                        TextButton(
                          onPressed: () => ctx.pop(true),
                          child: Text(l10n.delete,
                              style: const TextStyle(color: AppColors.error)),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true && context.mounted) {
                    await ref
                        .read(assetControllerProvider.notifier)
                        .deleteAsset(assetId);
                    if (context.mounted) context.pop();
                  }
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      const Icon(Icons.delete_outline,
                          color: AppColors.error, size: 18),
                      const SizedBox(width: 8),
                      Text(l10n.delete,
                          style: const TextStyle(color: AppColors.error)),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: assetAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Text(err.toString(),
              style: const TextStyle(color: AppColors.error)),
        ),
        data: (asset) {
          if (asset == null) {
            return Center(child: Text(l10n.assetNotFound));
          }
          return _AssetDetailBody(asset: asset);
        },
      ),
    );
  }
}

class _AssetDetailBody extends ConsumerWidget {
  final Asset asset;
  const _AssetDetailBody({required this.asset});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final role = ref.watch(profileProvider).valueOrNull?.role;
    final prefix = switch (role) {
      UserRole.owner => '/owner',
      UserRole.employee => '/employee',
      UserRole.client => '/client',
      UserRole.operator => '/operator',
      UserRole.clientAdmin => '/client',
      UserRole.clientMechanic => '/client',
      UserRole.clientOperator => '/client',
      null => '/owner',
    };

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Header card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: const Border.fromBorderSide(
                BorderSide(color: AppColors.cardBorder)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: AppColors.primary.withOpacity(0.15),
                    child: Icon(assetIconFor(asset.assetTypeId),
                        color: AppColors.primary, size: 30),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(asset.name,
                            style: Theme.of(context).textTheme.titleLarge),
                        if (asset.model != null || asset.make != null)
                          Text(
                            [asset.make, asset.model]
                                .whereType<String>()
                                .join(' · '),
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 13),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Details section
        _SectionHeader(title: l10n.assetDetails),
        _DetailRow(label: l10n.serialNumber, value: asset.serialNumber),
        _DetailRow(label: l10n.year, value: asset.year?.toString()),
        _DetailRow(label: l10n.location, value: asset.location),
        if (role == UserRole.owner) _ClientAssignRow(asset: asset),
        // Engines card (owner only)
        if (role == UserRole.owner) ...[
          const SizedBox(height: 16),
          _EnginesCard(assetId: asset.id, routePrefix: prefix),
        ],
        if (_canSeeMaintenancePlan(role)) ...[
          const SizedBox(height: 16),
          _MaintenancePlanCard(
            assetId: asset.id,
            routePrefix: prefix,
            readOnly: role != UserRole.owner,
          ),
        ],
        // Device status strip + Live Telemetry
        const SizedBox(height: 16),
        _DeviceStatusStrip(assetId: asset.id),
        const SizedBox(height: 16),
        _TelemetrySection(assetId: asset.id, routePrefix: prefix),
        if (asset.notes != null) ...[
          const SizedBox(height: 8),
          _SectionHeader(title: l10n.notes),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Text(
              asset.notes!,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.primary,
              letterSpacing: 1.2,
            ),
      ),
    );
  }
}

class _EnginesCard extends ConsumerWidget {
  final String assetId;
  final String routePrefix;
  const _EnginesCard({required this.assetId, required this.routePrefix});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final enginesAsync = ref.watch(enginesForAssetProvider(assetId));
    final count = enginesAsync.valueOrNull?.length ?? 0;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => context.push('$routePrefix/assets/$assetId/engines'),
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
            const Icon(Icons.engineering, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.enginesTitle,
                      style: Theme.of(context).textTheme.titleSmall),
                  Text('$count ${l10n.enginesCount}',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

bool _canSeeMaintenancePlan(UserRole? role) => switch (role) {
      UserRole.owner ||
      UserRole.client ||
      UserRole.clientAdmin ||
      UserRole.clientMechanic =>
        true,
      _ => false,
    };

class _MaintenancePlanCard extends ConsumerWidget {
  final String assetId;
  final String routePrefix;
  final bool readOnly;

  const _MaintenancePlanCard({
    required this.assetId,
    required this.routePrefix,
    required this.readOnly,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final intervalsAsync = ref.watch(serviceIntervalsProvider(assetId));
    final intervals = intervalsAsync.valueOrNull ?? <AssetServiceInterval>[];
    final visibleCount = readOnly
        ? intervals.where((interval) => interval.enabled).length
        : intervals.length;
    final withParts = intervals
        .where((interval) =>
            (!readOnly || interval.enabled) &&
            interval.checklistTemplateId != null)
        .length;
    final route = readOnly
        ? '$routePrefix/assets/$assetId/maintenance-plan'
        : '$routePrefix/assets/$assetId/service-intervals';

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => context.push(route),
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
            const Icon(Icons.event_note_outlined, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(readOnly ? 'Parts & Maintenance' : 'Maintenance Plan',
                      style: Theme.of(context).textTheme.titleSmall),
                  Text(
                    intervalsAsync.isLoading
                        ? 'Loading intervals...'
                        : '$visibleCount interval${visibleCount == 1 ? '' : 's'} • $withParts kit${withParts == 1 ? '' : 's'}',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String? value;

  const _DetailRow({required this.label, this.value});

  @override
  Widget build(BuildContext context) {
    if (value == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style:
                  const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value!,
              style:
                  const TextStyle(color: AppColors.textPrimary, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Live Telemetry Section ────────────────────────────────────────────────────

class _TelemetrySection extends ConsumerWidget {
  final String assetId;
  final String routePrefix;
  const _TelemetrySection({required this.assetId, required this.routePrefix});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final enginesAsync = ref.watch(enginesForAssetProvider(assetId));
    final showTelemetry = hasTier(
        ref.watch(profileProvider).valueOrNull, SubscriptionTier.telemetry);
    return Column(
      children: [
        if (!showTelemetry)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warning.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.warning.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.lock_outline,
                    color: AppColors.warning, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.upgradeMessage(SubscriptionTier.telemetry.displayName),
                    style:
                        const TextStyle(color: AppColors.warning, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        if (enginesAsync.valueOrNull?.isEmpty ?? true)
          const SizedBox.shrink()
        else if (showTelemetry)
          ...enginesAsync.when(
            loading: () => const [],
            error: (_, __) => const [],
            data: (engines) => engines
                .map((e) =>
                    _EngineTelemCard(engine: e, routePrefix: routePrefix))
                .toList(),
          )
        else
          ...enginesAsync.when(
            loading: () => const [],
            error: (_, __) => const [],
            data: (engines) =>
                engines.map((e) => _LimitedEngineCard(engine: e)).toList(),
          ),
      ],
    );
  }
}

class _LimitedEngineCard extends StatelessWidget {
  final AssetEngine engine;
  const _LimitedEngineCard({required this.engine});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: const Border.fromBorderSide(
            BorderSide(color: AppColors.cardBorder)),
      ),
      child: Row(
        children: [
          const Icon(Icons.engineering,
              color: AppColors.textSecondary, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(engine.label,
                    style: Theme.of(context).textTheme.titleSmall),
                Text(AppLocalizations.of(context).noTelemetry,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EngineTelemCard extends ConsumerWidget {
  final AssetEngine engine;
  final String routePrefix;
  const _EngineTelemCard({required this.engine, required this.routePrefix});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final readingAsync = ref.watch(latestTelemetryProvider(engine.id));
    final alertsAsync = ref.watch(unacknowledgedAlertsProvider(engine.id));
    final alertCount = alertsAsync.valueOrNull?.length ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: const Border.fromBorderSide(
            BorderSide(color: AppColors.cardBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: label + alert badge + history link
          Row(
            children: [
              const Icon(Icons.speed, color: AppColors.primary, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${l10n.liveTelemetry} — ${engine.label}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (alertCount > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: AppColors.warning.withOpacity(0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.warning_amber,
                          color: AppColors.warning, size: 12),
                      const SizedBox(width: 4),
                      Text(
                        '$alertCount',
                        style: const TextStyle(
                            color: AppColors.warning,
                            fontSize: 11,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                color: AppColors.textSecondary,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () =>
                    ref.invalidate(latestTelemetryProvider(engine.id)),
                tooltip: 'Refresh',
              ),
            ],
          ),
          const SizedBox(height: 12),
          readingAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, __) => Text(l10n.noTelemetry,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
            data: (reading) {
              if (reading == null) {
                return Text(l10n.noTelemetry,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12));
              }
              final ts = reading.ts.toLocal();
              final timeStr =
                  '${ts.year}-${ts.month.toString().padLeft(2, '0')}-'
                  '${ts.day.toString().padLeft(2, '0')} '
                  '${ts.hour.toString().padLeft(2, '0')}:'
                  '${ts.minute.toString().padLeft(2, '0')}';

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${l10n.lastReading}: $timeStr',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 11),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 20,
                    runSpacing: 10,
                    children: [
                      if (reading.rpm != null)
                        _TeleStat(l10n.rpm, reading.rpm!.toStringAsFixed(0)),
                      if (reading.coolantTemp != null)
                        _TeleStat(l10n.coolantTemp,
                            '${reading.coolantTemp!.toStringAsFixed(1)}°C'),
                      if (reading.oilPressure != null)
                        _TeleStat(l10n.oilPressure,
                            '${reading.oilPressure!.toStringAsFixed(1)} PSI'),
                      if (reading.batteryV != null)
                        _TeleStat(l10n.batteryVoltage,
                            '${reading.batteryV!.toStringAsFixed(2)}V'),
                      if (reading.throttlePct != null)
                        _TeleStat(l10n.throttle,
                            '${reading.throttlePct!.toStringAsFixed(0)}%'),
                      if (reading.fuelRate != null)
                        _TeleStat(l10n.fuelRate,
                            '${reading.fuelRate!.toStringAsFixed(2)} L/h'),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () =>
                  context.push('$routePrefix/engines/${engine.id}/telemetry'),
              icon: const Icon(Icons.history, size: 14),
              label: Text(l10n.telemetryHistory,
                  style: const TextStyle(fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Client Assignment Row ────────────────────────────────────────────────────

class _ClientAssignRow extends ConsumerWidget {
  final Asset asset;
  const _ClientAssignRow({required this.asset});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clientsAsync = ref.watch(clientsProvider);

    return clientsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (clients) {
        final assigned =
            clients.where((c) => c.id == asset.clientId).firstOrNull;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 120,
                child: Text(
                  'Client',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13),
                ),
              ),
              Expanded(
                child: Text(
                  assigned?.fullName ?? 'Unassigned',
                  style: TextStyle(
                    color: assigned != null
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8)),
                onPressed: () =>
                    _showReassignSheet(context, ref, clients, asset.clientId),
                child: const Text('Reassign', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showReassignSheet(
    BuildContext context,
    WidgetRef ref,
    List<Profile> clients,
    String? currentClientId,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Assign to Client',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            const Divider(height: 1),
            ...clients.map((client) => ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primary.withOpacity(0.1),
                    child: Text(
                      client.fullName.isNotEmpty
                          ? client.fullName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                          color: AppColors.primary, fontSize: 13),
                    ),
                  ),
                  title: Text(client.fullName),
                  subtitle: Text(client.email ?? '',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary)),
                  trailing: client.id == currentClientId
                      ? const Icon(Icons.check,
                          color: AppColors.primary, size: 18)
                      : null,
                  onTap: () async {
                    ctx.pop();
                    await ref
                        .read(assetControllerProvider.notifier)
                        .updateAsset(asset.id, {'client_id': client.id});
                    ref.invalidate(assetByIdProvider(asset.id));
                  },
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _TeleStat extends StatelessWidget {
  final String label;
  final String value;
  const _TeleStat(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style:
                const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
        Text(value,
            style: const TextStyle(
                color: AppColors.primary,
                fontSize: 14,
                fontWeight: FontWeight.bold)),
      ],
    );
  }
}

// ── Device Status Strip ───────────────────────────────────────────────────────

class _DeviceStatusStrip extends ConsumerWidget {
  final String assetId;
  const _DeviceStatusStrip({required this.assetId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceAsync = ref.watch(devicesProvider(assetId));
    final telemAsync = ref.watch(latestTelemetryForAssetProvider(assetId));
    final role = ref.watch(profileProvider).valueOrNull?.role;
    final isOwner = role == UserRole.owner;

    return deviceAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (device) {
        if (device == null) {
          return _StatusStripContainer(
            child: Row(
              children: [
                const _StatusDot(live: false),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isOwner
                        ? 'No telemetry device'
                        : 'No telemetry device linked',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                  ),
                ),
                if (isOwner)
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: AppColors.surface,
                      shape: const RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.vertical(top: Radius.circular(16)),
                      ),
                      builder: (_) => DevicePairingSheet(
                        assetId: assetId,
                        assetName: '',
                      ),
                    ),
                    child: const Text('Link Device →',
                        style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          );
        }

        final lastSeenStr = device['last_seen'] as String?;
        final lastSeen = lastSeenStr != null
            ? DateTime.tryParse(lastSeenStr)?.toLocal()
            : null;
        final isLive = lastSeen != null &&
            DateTime.now().difference(lastSeen).inMinutes < 5;

        if (isLive) {
          final reading = telemAsync.valueOrNull;
          return _StatusStripContainer(
            child: Row(
              children: [
                const _StatusDot(live: true),
                const SizedBox(width: 8),
                const Text(
                  'LIVE',
                  style: TextStyle(
                    color: AppColors.success,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (reading?.rpm != null) ...[
                  const Text(' · ',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 12)),
                  Text(
                    '${reading!.rpm!.toStringAsFixed(0)} RPM',
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 12),
                  ),
                ],
                if (reading?.coolantTemp != null) ...[
                  const Text(' · ',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 12)),
                  Text(
                    '${reading!.coolantTemp!.toStringAsFixed(1)}°C',
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 12),
                  ),
                ],
                const Spacer(),
                Text(
                  'Last seen ${_minutesAgo(lastSeen)}',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 11),
                ),
              ],
            ),
          );
        } else {
          final lastSeenLabel =
              lastSeen != null ? _relativeTime(lastSeen) : 'Never';
          return _StatusStripContainer(
            child: Row(
              children: [
                const _StatusDot(live: false),
                const SizedBox(width: 8),
                const Text(
                  'Device linked',
                  style: TextStyle(color: AppColors.warning, fontSize: 12),
                ),
                const Text(
                  ' · No recent data',
                  style:
                      TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
                const Spacer(),
                Text(
                  'Last seen $lastSeenLabel',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 11),
                ),
              ],
            ),
          );
        }
      },
    );
  }

  String _minutesAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    return '${diff.inMinutes}m ago';
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _StatusStripContainer extends StatelessWidget {
  final Widget child;
  const _StatusStripContainer({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: const Border.fromBorderSide(
            BorderSide(color: AppColors.cardBorder)),
      ),
      child: child,
    );
  }
}

class _StatusDot extends StatelessWidget {
  final bool live;
  const _StatusDot({required this.live});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: live ? AppColors.success : Colors.transparent,
        border: Border.all(
          color: live ? AppColors.success : AppColors.textSecondary,
          width: 1.5,
        ),
      ),
    );
  }
}
