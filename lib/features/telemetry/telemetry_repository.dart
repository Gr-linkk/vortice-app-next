import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/models/telemetry_alert.dart';
import 'package:vortice_app/models/telemetry_reading.dart';

class DevicePairingResult {
  final bool linked;
  final String? errorMessage;

  const DevicePairingResult._({required this.linked, this.errorMessage});

  const DevicePairingResult.linked() : this._(linked: true);

  const DevicePairingResult.notFound()
      : this._(
          linked: false,
          errorMessage: 'Code not found. Check the code on your Pi unit.',
        );

  const DevicePairingResult.alreadyLinked()
      : this._(
          linked: false,
          errorMessage: 'This device is already linked to another asset.',
        );
}

class TelemetryRepository {
  final SupabaseClient _supabase;

  const TelemetryRepository(this._supabase);

  Future<TelemetryReading?> latestReadingForEngine(String engineId) async {
    final data = await _supabase
        .from(AppConstants.tTelemetryReadings)
        .select()
        .eq('engine_id', engineId)
        .order('ts', ascending: false)
        .limit(1)
        .maybeSingle();

    if (data == null) return null;
    return TelemetryReading.fromJson(data);
  }

  Future<TelemetryReading?> latestReadingForAsset(String assetId) async {
    final engineId = await _firstEngineIdForAsset(assetId);
    if (engineId == null) return null;
    return latestReadingForEngine(engineId);
  }

  Future<List<TelemetryReading>> readingsForEngine({
    required String engineId,
    DateTime? from,
    DateTime? to,
    int limit = 500,
  }) async {
    var query = _supabase
        .from(AppConstants.tTelemetryReadings)
        .select()
        .eq('engine_id', engineId);

    if (from != null) {
      query = query.gte('ts', from.toIso8601String());
    }
    if (to != null) {
      query = query.lte('ts', to.toIso8601String());
    }

    final data = await query.order('ts', ascending: false).limit(limit);
    return _readingsFromData(data);
  }

  Future<List<TelemetryAlert>> unacknowledgedAlertsForEngine(
    String engineId,
  ) async {
    final data = await _supabase
        .from(AppConstants.tTelemetryAlerts)
        .select()
        .eq('engine_id', engineId)
        .eq('acknowledged', false)
        .order('created_at', ascending: false);

    return _alertsFromData(data);
  }

  Future<List<TelemetryAlert>> alertsForEngine(String engineId) async {
    final data = await _supabase
        .from(AppConstants.tTelemetryAlerts)
        .select()
        .eq('engine_id', engineId)
        .order('created_at', ascending: false)
        .limit(50);

    return _alertsFromData(data);
  }

  Future<List<TelemetryAlert>> unacknowledgedAlertsForAsset(
    String assetId,
  ) async {
    final engineIds = await _engineIdsForAsset(assetId);
    if (engineIds.isEmpty) return [];

    final data = await _supabase
        .from(AppConstants.tTelemetryAlerts)
        .select()
        .inFilter('engine_id', engineIds)
        .eq('acknowledged', false)
        .order('created_at', ascending: false);

    return _alertsFromData(data);
  }

  Future<int> unacknowledgedAlertCountForAsset(String assetId) async {
    final engineIds = await _engineIdsForAsset(assetId);
    if (engineIds.isEmpty) return 0;

    final countData = await _supabase
        .from(AppConstants.tTelemetryAlerts)
        .select('id')
        .inFilter('engine_id', engineIds)
        .eq('acknowledged', false)
        .count();

    return countData.count;
  }

  Future<List<TelemetryAlert>> activeAlerts() async {
    final data = await _supabase
        .from(AppConstants.tTelemetryAlerts)
        .select()
        .eq('acknowledged', false)
        .order('created_at', ascending: false);

    return _alertsFromData(data);
  }

  Future<void> acknowledgeAlert(String alertId, String userId) async {
    await _supabase.from(AppConstants.tTelemetryAlerts).update({
      'acknowledged': true,
      'acknowledged_by': userId,
      'acknowledged_at': DateTime.now().toIso8601String(),
    }).eq('id', alertId);
  }

  Future<void> resolveAlert(String alertId) async {
    await _supabase.from(AppConstants.tTelemetryAlerts).update({
      'resolved': true,
      'resolved_at': DateTime.now().toIso8601String(),
    }).eq('id', alertId);
  }

  Future<Map<String, dynamic>?> deviceForAsset(String assetId) async {
    return _supabase
        .from(AppConstants.tDevices)
        .select()
        .eq('asset_id', assetId)
        .maybeSingle();
  }

  Future<DevicePairingResult> pairDevice({
    required String assetId,
    required String pairingCode,
    String? linkedBy,
  }) async {
    final device = await _supabase
        .from(AppConstants.tDevices)
        .select()
        .eq('pairing_code', pairingCode)
        .isFilter('asset_id', null)
        .maybeSingle();

    if (device == null) {
      final existing = await _supabase
          .from(AppConstants.tDevices)
          .select('asset_id')
          .eq('pairing_code', pairingCode)
          .maybeSingle();

      if (existing != null && existing['asset_id'] != null) {
        return const DevicePairingResult.alreadyLinked();
      }
      return const DevicePairingResult.notFound();
    }

    await _supabase.from(AppConstants.tDevices).update({
      'asset_id': assetId,
      'linked_at': DateTime.now().toIso8601String(),
      if (linkedBy != null) 'linked_by': linkedBy,
    }).eq('id', device['id'] as String);

    return const DevicePairingResult.linked();
  }

  Future<String?> _firstEngineIdForAsset(String assetId) async {
    final data = await _supabase
        .from(AppConstants.tAssetEngines)
        .select('id')
        .eq('asset_id', assetId)
        .limit(1)
        .maybeSingle();

    if (data == null) return null;
    return data['id'] as String;
  }

  Future<List<String>> _engineIdsForAsset(String assetId) async {
    final data = await _supabase
        .from(AppConstants.tAssetEngines)
        .select('id')
        .eq('asset_id', assetId);

    return (data as List).map((e) => e['id'] as String).toList();
  }

  List<TelemetryReading> _readingsFromData(Object? data) {
    return (data as List)
        .map((e) => TelemetryReading.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  List<TelemetryAlert> _alertsFromData(Object? data) {
    return (data as List)
        .map((e) => TelemetryAlert.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
