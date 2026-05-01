import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/models/telemetry_reading.dart';
import 'package:vortice_app/models/telemetry_alert.dart';

// ────────────────────────────────────────────────────────────────────────────
// TELEMETRY READINGS PROVIDERS
// ────────────────────────────────────────────────────────────────────────────

/// Fetch the latest telemetry reading for an engine
final latestTelemetryProvider =
    FutureProvider.family<TelemetryReading?, String>((ref, engineId) async {
  final data = await supabase
      .from(AppConstants.tTelemetryReadings)
      .select()
      .eq('engine_id', engineId)
      .order('ts', ascending: false)
      .limit(1)
      .maybeSingle();

  if (data == null) return null;
  return TelemetryReading.fromJson(data);
});

/// Fetch telemetry readings for an engine within a date range
final telemetryHistoryProvider = FutureProvider.family<List<TelemetryReading>,
    ({String engineId, DateTime from, DateTime to})>((ref, params) async {
  final data = await supabase
      .from(AppConstants.tTelemetryReadings)
      .select()
      .eq('engine_id', params.engineId)
      .gte('ts', params.from.toIso8601String())
      .lte('ts', params.to.toIso8601String())
      .order('ts', ascending: false)
      .limit(500);

  return (data as List)
      .map((e) => TelemetryReading.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// Fetch all telemetry readings for an engine (recent, limited)
final telemetryForEngineProvider =
    FutureProvider.family<List<TelemetryReading>, String>((ref, engineId) async {
  final data = await supabase
      .from(AppConstants.tTelemetryReadings)
      .select()
      .eq('engine_id', engineId)
      .order('ts', ascending: false)
      .limit(100);

  return (data as List)
      .map((e) => TelemetryReading.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ────────────────────────────────────────────────────────────────────────────
// TELEMETRY ALERTS PROVIDERS
// ────────────────────────────────────────────────────────────────────────────

/// Fetch unacknowledged alerts for an engine
final unacknowledgedAlertsProvider =
    FutureProvider.family<List<TelemetryAlert>, String>((ref, engineId) async {
  final data = await supabase
      .from(AppConstants.tTelemetryAlerts)
      .select()
      .eq('engine_id', engineId)
      .eq('acknowledged', false)
      .order('created_at', ascending: false);

  return (data as List)
      .map((e) => TelemetryAlert.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// Fetch all alerts for an engine
final alertsForEngineProvider =
    FutureProvider.family<List<TelemetryAlert>, String>((ref, engineId) async {
  final data = await supabase
      .from(AppConstants.tTelemetryAlerts)
      .select()
      .eq('engine_id', engineId)
      .order('created_at', ascending: false)
      .limit(50);

  return (data as List)
      .map((e) => TelemetryAlert.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// Count of unacknowledged alerts for an asset (all engines)
final unacknowledgedAlertCountProvider =
    FutureProvider.family<int, String>((ref, assetId) async {
  // First get all engine IDs for this asset
  final engines = await supabase
      .from(AppConstants.tAssetEngines)
      .select('id')
      .eq('asset_id', assetId);

  if ((engines as List).isEmpty) return 0;

  final engineIds = (engines as List).map((e) => e['id'] as String).toList();

  final countData = await supabase
      .from(AppConstants.tTelemetryAlerts)
      .select('id')
      .inFilter('engine_id', engineIds)
      .eq('acknowledged', false)
      .count();

  return countData.count ?? 0;
});

// ────────────────────────────────────────────────────────────────────────────
// TELEMETRY CONTROLLER
// ────────────────────────────────────────────────────────────────────────────

class TelemetryController extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;
  TelemetryController(this._ref) : super(const AsyncData(null));

  /// Acknowledge an alert
  Future<bool> acknowledgeAlert(String alertId, String userId) async {
    state = const AsyncLoading();
    bool success = false;
    state = await AsyncValue.guard(() async {
      await supabase.from(AppConstants.tTelemetryAlerts).update({
        'acknowledged': true,
        'acknowledged_by': userId,
        'acknowledged_at': DateTime.now().toIso8601String(),
      }).eq('id', alertId);
      success = true;
    });
    return success;
  }

  /// Mark an alert as resolved
  Future<bool> resolveAlert(String alertId) async {
    state = const AsyncLoading();
    bool success = false;
    state = await AsyncValue.guard(() async {
      await supabase.from(AppConstants.tTelemetryAlerts).update({
        'resolved': true,
        'resolved_at': DateTime.now().toIso8601String(),
      }).eq('id', alertId);
      success = true;
    });
    return success;
  }
}

final telemetryControllerProvider =
    StateNotifierProvider<TelemetryController, AsyncValue<void>>((ref) {
  return TelemetryController(ref);
});

// ────────────────────────────────────────────────────────────────────────────
// ACTIVE ALERTS (all unacknowledged, across all engines)
// ────────────────────────────────────────────────────────────────────────────

/// All unacknowledged alerts across every engine (owner / employee view)
final activeAlertsProvider = FutureProvider<List<TelemetryAlert>>((ref) async {
  final data = await supabase
      .from(AppConstants.tTelemetryAlerts)
      .select()
      .eq('acknowledged', false)
      .order('created_at', ascending: false);

  return (data as List)
      .map((e) => TelemetryAlert.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// Unacknowledged alerts for all engines belonging to a given asset
final alertsForAssetProvider =
    FutureProvider.family<List<TelemetryAlert>, String>((ref, assetId) async {
  final engines = await supabase
      .from(AppConstants.tAssetEngines)
      .select('id')
      .eq('asset_id', assetId);

  if ((engines as List).isEmpty) return [];

  final engineIds =
      (engines as List).map((e) => e['id'] as String).toList();

  final data = await supabase
      .from(AppConstants.tTelemetryAlerts)
      .select()
      .inFilter('engine_id', engineIds)
      .eq('acknowledged', false)
      .order('created_at', ascending: false);

  return (data as List)
      .map((e) => TelemetryAlert.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// Readings for the last N hours (convenience wrapper used by the dashboard)
final readingsHistoryProvider = FutureProvider.family<List<TelemetryReading>,
    ({String engineId, int hours})>((ref, params) async {
  final from = DateTime.now().subtract(Duration(hours: params.hours));
  final data = await supabase
      .from(AppConstants.tTelemetryReadings)
      .select()
      .eq('engine_id', params.engineId)
      .gte('ts', from.toIso8601String())
      .order('ts', ascending: false)
      .limit(500);

  return (data as List)
      .map((e) => TelemetryReading.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ────────────────────────────────────────────────────────────────────────────
// FLEET HEALTH
// ────────────────────────────────────────────────────────────────────────────

class FleetHealth {
  final int vesselCount;
  final int activeAlertCount;
  final int upcomingServiceCount;

  const FleetHealth({
    required this.vesselCount,
    required this.activeAlertCount,
    required this.upcomingServiceCount,
  });

  bool get hasAlerts => activeAlertCount > 0;
}

/// Fleet-level health summary.
/// Pass a clientId (profile id) to scope to one client's fleet;
/// pass null to fetch across all (owner/employee — RLS gives full access).
final fleetHealthProvider =
    FutureProvider.family<FleetHealth, String?>((ref, clientId) async {
  // ── Vessel count ──────────────────────────────────────────────────────
  final assetsQuery = supabase.from(AppConstants.tAssets).select('id');
  final assetsData = clientId != null
      ? await assetsQuery.eq('client_id', clientId)
      : await assetsQuery;
  final vesselCount = (assetsData as List).length;

  // ── Active alert count ────────────────────────────────────────────────
  int alertCount = 0;
  if (vesselCount > 0) {
    final assetIds =
        (assetsData as List).map((e) => e['id'] as String).toList();

    final enginesData = await supabase
        .from(AppConstants.tAssetEngines)
        .select('id')
        .inFilter('asset_id', assetIds);

    if ((enginesData as List).isNotEmpty) {
      final engineIds =
          (enginesData as List).map((e) => e['id'] as String).toList();
      final alertResult = await supabase
          .from(AppConstants.tTelemetryAlerts)
          .select('id')
          .inFilter('engine_id', engineIds)
          .eq('acknowledged', false)
          .count();
      alertCount = alertResult.count ?? 0;
    }
  }

  // ── Upcoming services ─────────────────────────────────────────────────
  // Count reminders that are not yet acknowledged
  int serviceCount = 0;
  if (vesselCount > 0) {
    final assetIds =
        (assetsData as List).map((e) => e['id'] as String).toList();
    final remindersResult = await supabase
        .from(AppConstants.tServiceReminders)
        .select('id')
        .inFilter('asset_id', assetIds)
        .eq('acknowledged', false)
        .count();
    serviceCount = remindersResult.count ?? 0;
  }

  return FleetHealth(
    vesselCount: vesselCount,
    activeAlertCount: alertCount,
    upcomingServiceCount: serviceCount,
  );
});
