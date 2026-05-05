import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/features/telemetry/telemetry_repository.dart';
import 'package:vortice_app/models/telemetry_alert.dart';
import 'package:vortice_app/models/telemetry_reading.dart';

final telemetryRepositoryProvider = Provider<TelemetryRepository>((ref) {
  return TelemetryRepository(supabase);
});

// ────────────────────────────────────────────────────────────────────────────
// TELEMETRY READINGS PROVIDERS
// ────────────────────────────────────────────────────────────────────────────

/// Fetch the latest telemetry reading for an asset via its first engine.
final latestTelemetryForAssetProvider =
    FutureProvider.family<TelemetryReading?, String>((ref, assetId) async {
  return ref.watch(telemetryRepositoryProvider).latestReadingForAsset(assetId);
});

/// Fetch the latest telemetry reading for an engine.
final latestTelemetryProvider =
    FutureProvider.family<TelemetryReading?, String>((ref, engineId) async {
  return ref
      .watch(telemetryRepositoryProvider)
      .latestReadingForEngine(engineId);
});

/// Fetch telemetry readings for an engine within a date range.
final telemetryHistoryProvider = FutureProvider.family<List<TelemetryReading>,
    ({String engineId, DateTime from, DateTime to})>((ref, params) async {
  return ref.watch(telemetryRepositoryProvider).readingsForEngine(
        engineId: params.engineId,
        from: params.from,
        to: params.to,
      );
});

/// Fetch all telemetry readings for an engine (recent, limited).
final telemetryForEngineProvider =
    FutureProvider.family<List<TelemetryReading>, String>(
        (ref, engineId) async {
  return ref
      .watch(telemetryRepositoryProvider)
      .readingsForEngine(engineId: engineId, limit: 100);
});

// ────────────────────────────────────────────────────────────────────────────
// TELEMETRY ALERTS PROVIDERS
// ────────────────────────────────────────────────────────────────────────────

/// Fetch unacknowledged alerts for an engine.
final unacknowledgedAlertsProvider =
    FutureProvider.family<List<TelemetryAlert>, String>((ref, engineId) async {
  return ref
      .watch(telemetryRepositoryProvider)
      .unacknowledgedAlertsForEngine(engineId);
});

/// Fetch all alerts for an engine.
final alertsForEngineProvider =
    FutureProvider.family<List<TelemetryAlert>, String>((ref, engineId) async {
  return ref.watch(telemetryRepositoryProvider).alertsForEngine(engineId);
});

/// Count of unacknowledged alerts for an asset (all engines).
final unacknowledgedAlertCountProvider =
    FutureProvider.family<int, String>((ref, assetId) async {
  return ref
      .watch(telemetryRepositoryProvider)
      .unacknowledgedAlertCountForAsset(assetId);
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
      await _ref
          .read(telemetryRepositoryProvider)
          .acknowledgeAlert(alertId, userId);
      success = true;
    });
    return success;
  }

  /// Mark an alert as resolved
  Future<bool> resolveAlert(String alertId) async {
    state = const AsyncLoading();
    bool success = false;
    state = await AsyncValue.guard(() async {
      await _ref.read(telemetryRepositoryProvider).resolveAlert(alertId);
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

/// All unacknowledged alerts across every engine (owner / employee view).
final activeAlertsProvider = FutureProvider<List<TelemetryAlert>>((ref) async {
  return ref.watch(telemetryRepositoryProvider).activeAlerts();
});

/// Unacknowledged alerts for all engines belonging to a given asset.
final alertsForAssetProvider =
    FutureProvider.family<List<TelemetryAlert>, String>((ref, assetId) async {
  return ref
      .watch(telemetryRepositoryProvider)
      .unacknowledgedAlertsForAsset(assetId);
});

/// Readings for the last N hours (convenience wrapper used by the dashboard).
final readingsHistoryProvider = FutureProvider.family<List<TelemetryReading>,
    ({String engineId, int hours})>((ref, params) async {
  final from = DateTime.now().subtract(Duration(hours: params.hours));
  return ref
      .watch(telemetryRepositoryProvider)
      .readingsForEngine(engineId: params.engineId, from: from);
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
    final assetIds = assetsData.map((e) => e['id'] as String).toList();

    final enginesData = await supabase
        .from(AppConstants.tAssetEngines)
        .select('id')
        .inFilter('asset_id', assetIds);

    if ((enginesData as List).isNotEmpty) {
      final engineIds = enginesData.map((e) => e['id'] as String).toList();
      final alertResult = await supabase
          .from(AppConstants.tTelemetryAlerts)
          .select('id')
          .inFilter('engine_id', engineIds)
          .eq('acknowledged', false)
          .count();
      alertCount = alertResult.count;
    }
  }

  // ── Upcoming services ─────────────────────────────────────────────────
  // Count reminders that are not yet acknowledged
  int serviceCount = 0;
  if (vesselCount > 0) {
    final assetIds = assetsData.map((e) => e['id'] as String).toList();
    final remindersResult = await supabase
        .from(AppConstants.tServiceReminders)
        .select('id')
        .inFilter('asset_id', assetIds)
        .eq('acknowledged', false)
        .count();
    serviceCount = remindersResult.count;
  }

  return FleetHealth(
    vesselCount: vesselCount,
    activeAlertCount: alertCount,
    upcomingServiceCount: serviceCount,
  );
});
