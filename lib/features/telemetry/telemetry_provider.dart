import 'package:flutter_riverpod/flutter_riverpod.dart';
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

/// Fetch the latest telemetry reading pinned directly to an asset.
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

/// Count of unacknowledged alerts pinned directly to an asset.
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

/// Unacknowledged alerts pinned directly to a given asset.
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

/// Fleet-level health summary.
/// Pass a clientId (profile id) to scope to one client's fleet;
/// pass null to fetch across all (owner/employee — RLS gives full access).
final fleetHealthProvider =
    FutureProvider.family<FleetHealth, String?>((ref, clientId) async {
  return ref.watch(telemetryRepositoryProvider).fleetHealth(clientId: clientId);
});
