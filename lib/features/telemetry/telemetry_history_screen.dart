import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/clients/client_capability_gate.dart';
import 'package:vortice_app/features/engines/engine_provider.dart';
import 'package:vortice_app/features/telemetry/telemetry_history_alerts_tab.dart';
import 'package:vortice_app/features/telemetry/telemetry_history_readings_tab.dart';
import 'package:vortice_app/features/telemetry/telemetry_screen_support.dart';
import 'package:vortice_app/models/client_capability.dart';

/// Shows telemetry history for an asset-first telemetry stream, or a legacy engine.
class TelemetryHistoryScreen extends ConsumerStatefulWidget {
  final String? engineId;
  final String? assetId;

  const TelemetryHistoryScreen({
    super.key,
    this.engineId,
    this.assetId,
  }) : assert(assetId != null || engineId != null);

  @override
  ConsumerState<TelemetryHistoryScreen> createState() =>
      _TelemetryHistoryScreenState();
}

class _TelemetryHistoryScreenState extends ConsumerState<TelemetryHistoryScreen>
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
    return ClientCapabilityGate(
      clientId: null,
      capability: ClientCapability.telemetry,
      allowedBuilder: (_) => _buildHistoryScaffold(context, l10n),
      blockedBuilder: (_) => Scaffold(
        appBar: AppBar(title: Text(l10n.telemetryHistory)),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: ClientCapabilityDisabledPanel(
              capability: ClientCapability.telemetry,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryScaffold(
    BuildContext context,
    AppLocalizations l10n,
  ) {
    final engineAsync = widget.engineId == null
        ? null
        : ref.watch(engineByIdProvider(widget.engineId!));

    return Scaffold(
      appBar: AppBar(
        title: engineAsync?.when(
              loading: () => Text(l10n.telemetryHistory),
              error: (_, __) => Text(l10n.telemetryHistory),
              data: (engine) => Text(engine?.label ?? l10n.telemetryHistory),
            ) ??
            Text(l10n.telemetryHistory),
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: AppColors.surfaceVariant,
            child: Row(
              children: [
                const Icon(Icons.calendar_today,
                    size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Text(
                  '${formatTelemetryDate(_dateRange.start)} - ${formatTelemetryDate(_dateRange.end)}',
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
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                TelemetryHistoryReadingsTab(
                  assetId: widget.assetId,
                  engineId: widget.engineId,
                  dateRange: _dateRange,
                ),
                TelemetryHistoryAlertsTab(
                  assetId: widget.assetId,
                  engineId: widget.engineId,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
