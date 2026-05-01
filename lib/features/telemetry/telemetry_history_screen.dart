import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/telemetry/telemetry_provider.dart';
import 'package:vortice_app/features/engines/engine_provider.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/subscription/tier_gate.dart';
import 'package:vortice_app/features/subscription/upgrade_prompt.dart';
import 'package:vortice_app/models/telemetry_reading.dart';
import 'package:vortice_app/models/telemetry_alert.dart';
import 'package:vortice_app/models/subscription_tier.dart';

/// Shows telemetry history for an engine with date range filter
class TelemetryHistoryScreen extends ConsumerStatefulWidget {
  final String engineId;
  final String? assetId;

  const TelemetryHistoryScreen({
    super.key,
    required this.engineId,
    this.assetId,
  });

  @override
  ConsumerState<TelemetryHistoryScreen> createState() =>
      _TelemetryHistoryScreenState();
}

class _TelemetryHistoryScreenState
    extends ConsumerState<TelemetryHistoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DateTimeRange _dateRange = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 7)),
    end: DateTime.now(),
  );

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
      initialDateRange: _dateRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              surface: AppColors.surface,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() => _dateRange = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // Gate: only Telemetry+ tier can view telemetry history
    if (!hasTier(ref.watch(profileProvider).valueOrNull, SubscriptionTier.telemetry)) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.telemetryHistory)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: UpgradePrompt(requiredTier: SubscriptionTier.telemetry),
          ),
        ),
      );
    }

    final engineAsync = ref.watch(engineByIdProvider(widget.engineId));

    return Scaffold(
      appBar: AppBar(
        title: engineAsync.when(
          loading: () => Text(l10n.telemetryHistory),
          error: (_, __) => Text(l10n.telemetryHistory),
          data: (engine) => Text(engine?.label ?? l10n.telemetryHistory),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range),
            onPressed: _selectDateRange,
            tooltip: l10n.selectDateRange,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: l10n.readings),
            Tab(text: l10n.alerts),
          ],
        ),
      ),
      body: Column(
        children: [
          // Date range indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: AppColors.surfaceVariant,
            child: Row(
              children: [
                const Icon(Icons.calendar_today,
                    size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Text(
                  '${_formatDate(_dateRange.start)} - ${_formatDate(_dateRange.end)}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _selectDateRange,
                  child: Text(l10n.change),
                ),
              ],
            ),
          ),

          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _ReadingsTab(
                  engineId: widget.engineId,
                  dateRange: _dateRange,
                ),
                _AlertsTab(engineId: widget.engineId),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}

class _ReadingsTab extends ConsumerWidget {
  final String engineId;
  final DateTimeRange dateRange;

  const _ReadingsTab({
    required this.engineId,
    required this.dateRange,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final readingsAsync = ref.watch(
      telemetryHistoryProvider((
        engineId: engineId,
        from: dateRange.start,
        to: dateRange.end,
      )),
    );

    return readingsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(
        child: Text(err.toString(),
            style: const TextStyle(color: AppColors.error)),
      ),
      data: (readings) {
        if (readings.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.sensors_off,
                    size: 48, color: AppColors.textSecondary),
                const SizedBox(height: 12),
                Text(
                  l10n.noTelemetryData,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(telemetryHistoryProvider((
              engineId: engineId,
              from: dateRange.start,
              to: dateRange.end,
            )));
          },
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: readings.length,
            itemBuilder: (_, i) => _ReadingCard(reading: readings[i]),
          ),
        );
      },
    );
  }
}

class _ReadingCard extends StatelessWidget {
  final TelemetryReading reading;

  const _ReadingCard({required this.reading});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: const CircleAvatar(
          backgroundColor: AppColors.surfaceVariant,
          child: Icon(Icons.sensors, color: AppColors.primary, size: 18),
        ),
        title: Text(
          _formatDateTime(reading.ts),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        subtitle: reading.rpm != null
            ? Text(
                '${reading.rpm!.toStringAsFixed(0)} RPM',
                style:
                    const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              )
            : null,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _DetailRow(label: 'RPM', value: reading.rpm?.toStringAsFixed(0)),
                _DetailRow(
                    label: l10n.coolantTemp,
                    value: reading.coolantTemp != null
                        ? '${reading.coolantTemp!.toStringAsFixed(1)}°C'
                        : null),
                _DetailRow(
                    label: l10n.oilPressure,
                    value: reading.oilPressure != null
                        ? '${reading.oilPressure!.toStringAsFixed(1)} PSI'
                        : null),
                _DetailRow(
                    label: l10n.battery,
                    value: reading.batteryV != null
                        ? '${reading.batteryV!.toStringAsFixed(2)}V'
                        : null),
                _DetailRow(
                    label: l10n.boostPressure,
                    value: reading.boostPsi != null
                        ? '${reading.boostPsi!.toStringAsFixed(1)} PSI'
                        : null),
                _DetailRow(
                    label: l10n.throttle,
                    value: reading.throttlePct != null
                        ? '${reading.throttlePct!.toStringAsFixed(0)}%'
                        : null),
                _DetailRow(
                    label: l10n.fuelRate,
                    value: reading.fuelRate != null
                        ? '${reading.fuelRate!.toStringAsFixed(2)} L/hr'
                        : null),
                _DetailRow(
                    label: l10n.torque,
                    value: reading.torquePct != null
                        ? '${reading.torquePct!.toStringAsFixed(0)}%'
                        : null),
                _DetailRow(
                    label: l10n.engineHours,
                    value: reading.engineHours?.toStringAsFixed(1)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
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
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          Text(value!,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _AlertsTab extends ConsumerWidget {
  final String engineId;

  const _AlertsTab({required this.engineId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final alertsAsync = ref.watch(alertsForEngineProvider(engineId));

    return alertsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(
        child: Text(err.toString(),
            style: const TextStyle(color: AppColors.error)),
      ),
      data: (alerts) {
        if (alerts.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle,
                    size: 48, color: AppColors.success),
                const SizedBox(height: 12),
                Text(
                  l10n.noAlerts,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async =>
              ref.invalidate(alertsForEngineProvider(engineId)),
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: alerts.length,
            itemBuilder: (_, i) => _AlertCard(alert: alerts[i]),
          ),
        );
      },
    );
  }
}

class _AlertCard extends StatelessWidget {
  final TelemetryAlert alert;

  const _AlertCard({required this.alert});

  @override
  Widget build(BuildContext context) {
    final severityColor = switch (alert.severity) {
      AlertSeverity.critical => AppColors.error,
      AlertSeverity.warning => AppColors.warning,
      AlertSeverity.info => AppColors.primary,
      _ => AppColors.primary,
    };

    final icon = switch (alert.alertType) {
      TelemetryAlertType.dtc => Icons.error_outline,
      TelemetryAlertType.threshold => Icons.speed,
      TelemetryAlertType.warning => Icons.warning_amber,
      TelemetryAlertType.critical => Icons.dangerous,
      TelemetryAlertType.info => Icons.info_outline,
      _ => Icons.info_outline,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: severityColor.withOpacity(0.15),
          child: Icon(icon, color: severityColor, size: 20),
        ),
        title: Row(
          children: [
            if (alert.spn != null)
              Text('SPN ${alert.spn}',
                  style: Theme.of(context).textTheme.titleSmall)
            else if (alert.parameter != null)
              Text(alert.parameter!,
                  style: Theme.of(context).textTheme.titleSmall)
            else
              Text(alert.alertType.name.toUpperCase(),
                  style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
            if (!alert.acknowledged)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'NEW',
                  style: TextStyle(
                    color: AppColors.error,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (alert.message != null)
              Text(alert.message!,
                  style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            Text(
              _formatDateTime(alert.createdAt ?? DateTime.now()),
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 11),
            ),
          ],
        ),
        isThreeLine: alert.message != null,
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
