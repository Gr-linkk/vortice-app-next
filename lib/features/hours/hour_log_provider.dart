import 'package:vortice_app/core/retryable_rpc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/features/engines/engine_provider.dart';
import 'package:vortice_app/models/hour_log.dart';

// ── Fetch hour logs for an engine ──────────────────────────────────────────

final hourLogsForEngineProvider = FutureProvider.family<List<HourLog>, String>((
  ref,
  engineId,
) async {
  final remote = await supabase
      .from(AppConstants.tHourLogs)
      .select()
      .eq('engine_id', engineId)
      .order('logged_at', ascending: false);

  return (remote as List)
      .map((e) => HourLog.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ── Hour log controller ────────────────────────────────────────────────────

class HourLogController extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;
  HourLogController(this._ref) : super(const AsyncData(null));

  Future<bool> logHours({
    required String engineId,
    required String assetId,
    required double hours,
    String? notes,
  }) async {
    state = const AsyncLoading();
    bool success = false;
    state = await AsyncValue.guard(() async {
      await authenticatedRetryableRpc().call('record_manual_meter', {
        'p_engine': engineId,
        'p_asset': assetId,
        'p_hours': hours,
        'p_notes': notes,
      }, captureTime: true);

      _ref.invalidate(hourLogsForEngineProvider(engineId));
      _ref.invalidate(enginesForAssetProvider(assetId));
      success = true;
    });
    return success;
  }
}

final hourLogControllerProvider =
    StateNotifierProvider<HourLogController, AsyncValue<void>>((ref) {
      return HourLogController(ref);
    });
