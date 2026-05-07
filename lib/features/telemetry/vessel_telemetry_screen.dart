import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/assets/asset_provider.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/engines/engine_provider.dart';
import 'package:vortice_app/features/reminders/reminder_provider.dart';
import 'package:vortice_app/features/subscription/tier_gate.dart';
import 'package:vortice_app/features/subscription/upgrade_prompt.dart';
import 'package:vortice_app/features/telemetry/telemetry_provider.dart';
import 'package:vortice_app/features/service_reports/service_report_provider.dart';
import 'package:vortice_app/models/asset.dart';
import 'package:vortice_app/models/asset_engine.dart';
import 'package:vortice_app/models/subscription_tier.dart';
import 'package:vortice_app/models/telemetry_alert.dart';

/// Live telemetry view for a single vessel / asset.
/// Polling interval: 30 seconds.
class VesselTelemetryScreen extends ConsumerStatefulWidget {
  final String assetId;

  const VesselTelemetryScreen({super.key, required this.assetId});

  @override
  ConsumerState<VesselTelemetryScreen> createState() =>
      _VesselTelemetryScreenState();
}

class _VesselTelemetryScreenState extends ConsumerState<VesselTelemetryScreen> {
  Timer? _pollingTimer;
  AssetEngine? _selectedEngine;

  @override
  void initState() {
    super.initState();
    // Start 30-second polling once the widget is mounted
    _pollingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      ref.invalidate(latestTelemetryForAssetProvider(widget.assetId));
      ref.invalidate(alertsForAssetProvider(widget.assetId));
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).valueOrNull;

    // Tier gate
    if (!hasTier(profile, SubscriptionTier.telemetry)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Vessel Telemetry')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: UpgradePrompt(requiredTier: SubscriptionTier.telemetry),
          ),
        ),
      );
    }

    final assetAsync = ref.watch(assetByIdProvider(widget.assetId));
    final enginesAsync = ref.watch(enginesForAssetProvider(widget.assetId));

    return assetAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Vessel Telemetry')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (err, _) => Scaffold(
        appBar: AppBar(title: const Text('Vessel Telemetry')),
        body: Center(
          child: Text(err.toString(),
              style: const TextStyle(color: AppColors.error)),
        ),
      ),
      data: (asset) {
        if (asset == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Vessel Telemetry')),
            body: const Center(child: Text('Asset not found.')),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(asset.name),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh',
                onPressed: () {
                  ref.invalidate(
                      latestTelemetryForAssetProvider(widget.assetId));
                  ref.invalidate(alertsForAssetProvider(widget.assetId));
                },
              ),
            ],
          ),
          body: _Body(
            asset: asset,
            enginesAsync: enginesAsync,
            selectedEngine: _selectedEngine,
            onEngineSelected: (e) => setState(() => _selectedEngine = e),
            ref: ref,
          ),
        );
      },
    );
  }
}

class _Body extends StatelessWidget {
  final Asset asset;
  final AsyncValue<List<AssetEngine>> enginesAsync;
  final AssetEngine? selectedEngine;
  final ValueChanged<AssetEngine> onEngineSelected;
  final WidgetRef ref;

  const _Body({
    required this.asset,
    required this.enginesAsync,
    required this.selectedEngine,
    required this.onEngineSelected,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    return enginesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(
        child: Text(err.toString(),
            style: const TextStyle(color: AppColors.error)),
      ),
      data: (engines) {
        final engine =
            selectedEngine ?? (engines.isNotEmpty ? engines.first : null);

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(latestTelemetryForAssetProvider(asset.id));
            ref.invalidate(alertsForAssetProvider(asset.id));
          },
          child: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              // ── Engine selector ────────────────────────────────────────
              if (engines.length > 1) ...[
                const SizedBox(height: 12),
                SizedBox(
                  height: 40,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: engines.length,
                    itemBuilder: (_, i) {
                      final e = engines[i];
                      final selected = engine?.id == e.id;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(e.label),
                          selected: selected,
                          onSelected: (_) => onEngineSelected(e),
                          selectedColor:
                              AppColors.primary.withValues(alpha: 0.2),
                          labelStyle: TextStyle(
                            color: selected
                                ? AppColors.primary
                                : AppColors.textSecondary,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],

              // ── Live gauges ────────────────────────────────────────────
              _LiveGaugesSection(assetId: asset.id, ref: ref),

              // ── Active fault codes ─────────────────────────────────────
              _FaultCodesSection(assetId: asset.id, ref: ref),

              // ── Optional engine context ───────────────────────────────────
              if (engine != null) _EngineInfoSection(engine: engine),

              // ── Maintenance schedule ───────────────────────────────────
              _MaintenanceSection(assetId: asset.id, ref: ref),

              // ── Service history ────────────────────────────────────────
              _ServiceHistorySection(assetId: asset.id),
            ],
          ),
        );
      },
    );
  }
}

// ── Live Gauges Section ───────────────────────────────────────────────────────

class _LiveGaugesSection extends StatelessWidget {
  final String assetId;
  final WidgetRef ref;

  const _LiveGaugesSection({required this.assetId, required this.ref});

  @override
  Widget build(BuildContext context) {
    final readingAsync = ref.watch(latestTelemetryForAssetProvider(assetId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('Live Data', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(width: 8),
              readingAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (reading) => Text(
                  reading != null
                      ? 'Last updated: ${_formatTime(reading.ts)}'
                      : '',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        readingAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (err, _) => Padding(
            padding: const EdgeInsets.all(16),
            child: Text(err.toString(),
                style: const TextStyle(color: AppColors.error)),
          ),
          data: (reading) {
            if (reading == null) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    'Waiting for data...',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.4,
                children: [
                  _GaugeCard(
                    label: 'RPM',
                    value: reading.rpm?.toStringAsFixed(0),
                    unit: '',
                    color: AppColors.primary,
                  ),
                  _GaugeCard(
                    label: 'Coolant',
                    value: reading.coolantTemp?.toStringAsFixed(1),
                    unit: '°C',
                    color: _coolantColor(reading.coolantTemp),
                  ),
                  _GaugeCard(
                    label: 'Oil Pressure',
                    value: reading.oilPressure?.toStringAsFixed(1),
                    unit: 'PSI',
                    color: AppColors.primary,
                  ),
                  _GaugeCard(
                    label: 'Fuel Rate',
                    value: reading.fuelRate?.toStringAsFixed(2),
                    unit: 'L/hr',
                    color: AppColors.textSecondary,
                  ),
                  _GaugeCard(
                    label: 'Battery',
                    value: reading.batteryV?.toStringAsFixed(2),
                    unit: 'V',
                    color: _batteryColor(reading.batteryV),
                  ),
                  _GaugeCard(
                    label: 'Boost',
                    value: reading.boostPsi?.toStringAsFixed(1),
                    unit: 'PSI',
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Color _coolantColor(double? temp) {
    if (temp == null) return AppColors.textSecondary;
    if (temp > 95) return AppColors.error;
    if (temp > 85) return AppColors.warning;
    return AppColors.success;
  }

  Color _batteryColor(double? v) {
    if (v == null) return AppColors.textSecondary;
    if (v < 12.0) return AppColors.error;
    if (v < 12.4) return AppColors.warning;
    return AppColors.success;
  }

  String _formatTime(DateTime dt) {
    return DateFormat('HH:mm:ss').format(dt.toLocal());
  }
}

class _GaugeCard extends StatelessWidget {
  final String label;
  final String? value;
  final String unit;
  final Color color;

  const _GaugeCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style:
                const TextStyle(color: AppColors.textSecondary, fontSize: 11),
          ),
          const Spacer(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value ?? '—',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(
                  unit,
                  style: TextStyle(fontSize: 12, color: color),
                ),
              ],
            ],
          ),
          Container(
            margin: const EdgeInsets.only(top: 6),
            height: 3,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Fault Codes Section ───────────────────────────────────────────────────────

class _FaultCodesSection extends StatelessWidget {
  final String assetId;
  final WidgetRef ref;

  const _FaultCodesSection({required this.assetId, required this.ref});

  @override
  Widget build(BuildContext context) {
    final alertsAsync = ref.watch(alertsForAssetProvider(assetId));

    return alertsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (alerts) {
        if (alerts.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
              child: Text('Fault Codes',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            ...alerts.map(
                (a) => _FaultCodeTile(alert: a, assetId: assetId, ref: ref)),
          ],
        );
      },
    );
  }
}

class _FaultCodeTile extends StatelessWidget {
  final TelemetryAlert alert;
  final String assetId;
  final WidgetRef ref;

  const _FaultCodeTile(
      {required this.alert, required this.assetId, required this.ref});

  @override
  Widget build(BuildContext context) {
    final severityColor = switch (alert.severity) {
      AlertSeverity.critical => AppColors.error,
      AlertSeverity.warning => AppColors.warning,
      _ => AppColors.primary,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: severityColor.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber, color: severityColor, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (alert.spn != null)
                    Text(
                      'SPN ${alert.spn}  FMI ${alert.fmi ?? '?'}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                          fontSize: 13),
                    )
                  else
                    Text(
                      alert.alertType.name.toUpperCase(),
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                          fontSize: 13),
                    ),
                  if (alert.message != null)
                    Text(
                      alert.message!,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                ],
              ),
            ),
            if (!alert.acknowledged)
              TextButton(
                onPressed: () async {
                  final profile = ref.read(profileProvider).valueOrNull;
                  if (profile == null) return;
                  await ref
                      .read(telemetryControllerProvider.notifier)
                      .acknowledgeAlert(alert.id, profile.id);
                  ref.invalidate(alertsForAssetProvider(assetId));
                },
                child: const Text('Acknowledge'),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Engine Info Section ───────────────────────────────────────────────────────

class _EngineInfoSection extends StatelessWidget {
  final AssetEngine engine;

  const _EngineInfoSection({required this.engine});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Text('Engine Data',
              style: Theme.of(context).textTheme.titleMedium),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: const Border.fromBorderSide(
                  BorderSide(color: AppColors.cardBorder)),
            ),
            child: Column(
              children: [
                _InfoRow(label: 'Label', value: engine.label),
                if (engine.make != null)
                  _InfoRow(label: 'Make', value: engine.make!),
                if (engine.model != null)
                  _InfoRow(label: 'Model', value: engine.model!),
                if (engine.serialNumber != null)
                  _InfoRow(label: 'Serial', value: engine.serialNumber!),
                _InfoRow(
                  label: 'Engine Hours',
                  value: engine.currentHours.toStringAsFixed(1),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13)),
          Text(value,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

// ── Maintenance Schedule Section ──────────────────────────────────────────────

class _MaintenanceSection extends StatelessWidget {
  final String assetId;
  final WidgetRef ref;

  const _MaintenanceSection({required this.assetId, required this.ref});

  @override
  Widget build(BuildContext context) {
    final remindersAsync = ref.watch(remindersProvider);

    return remindersAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (reminders) {
        final assetReminders =
            reminders.where((r) => r.reminder.assetId == assetId).toList();

        if (assetReminders.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
              child: Text('Maintenance Schedule',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            ...assetReminders.take(5).map(
                  (r) => Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: const Border.fromBorderSide(
                            BorderSide(color: AppColors.cardBorder)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.schedule,
                              color: AppColors.textSecondary, size: 18),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '${r.reminder.intervalHours} hr service',
                              style: const TextStyle(
                                  color: AppColors.textPrimary, fontSize: 13),
                            ),
                          ),
                          Text(
                            r.hoursRemaining <= 0
                                ? 'Overdue'
                                : '${r.hoursRemaining.toStringAsFixed(0)} hrs',
                            style: TextStyle(
                              color: r.hoursRemaining <= 0
                                  ? AppColors.error
                                  : AppColors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }
}

// ── Service History Section ───────────────────────────────────────────────────

class _ServiceHistorySection extends ConsumerWidget {
  final String assetId;
  const _ServiceHistorySection({required this.assetId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportsAsync = ref.watch(serviceReportsProvider);

    return reportsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (reports) {
        final assetReports = reports.take(5).toList();

        if (assetReports.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
              child: Text('Service History',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            ...assetReports.map(
              (r) => Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: const Border.fromBorderSide(
                        BorderSide(color: AppColors.cardBorder)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.build_outlined,
                          color: AppColors.success, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          r.correction ?? r.comments ?? 'Service completed',
                          style: Theme.of(context).textTheme.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (r.createdAt != null)
                        Text(
                          DateFormat('MMM d').format(r.createdAt!),
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 12),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
