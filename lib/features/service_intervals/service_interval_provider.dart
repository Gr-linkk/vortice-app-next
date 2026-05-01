import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/models/asset_service_interval.dart';

// ── Fetch intervals for a specific asset ─────────────────────────────────────

final serviceIntervalsProvider =
    FutureProvider.family<List<AssetServiceInterval>, String>(
        (ref, assetId) async {
  final data = await supabase
      .from(AppConstants.tAssetServiceIntervals)
      .select()
      .eq('asset_id', assetId)
      .order('interval_hours');
  return (data as List)
      .map((e) => AssetServiceInterval.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ── CRUD controller ───────────────────────────────────────────────────────────

class ServiceIntervalController extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;
  ServiceIntervalController(this._ref) : super(const AsyncData(null));

  Future<bool> createInterval({
    required String assetId,
    required double intervalHours,
    String? checklistTemplateId,
    String? label,
  }) async {
    state = const AsyncLoading();
    bool success = false;
    state = await AsyncValue.guard(() async {
      await supabase.from(AppConstants.tAssetServiceIntervals).insert({
        'asset_id': assetId,
        'interval_hours': intervalHours,
        if (checklistTemplateId != null)
          'checklist_template_id': checklistTemplateId,
        if (label != null && label.isNotEmpty) 'label': label,
        'enabled': true,
      });
      _ref.invalidate(serviceIntervalsProvider(assetId));
      success = true;
    });
    return success;
  }

  Future<bool> updateInterval(
    String id, {
    required String assetId,
    double? intervalHours,
    String? checklistTemplateId,
    String? label,
    bool? enabled,
  }) async {
    state = const AsyncLoading();
    bool success = false;
    state = await AsyncValue.guard(() async {
      await supabase.from(AppConstants.tAssetServiceIntervals).update({
        if (intervalHours != null) 'interval_hours': intervalHours,
        if (checklistTemplateId != null)
          'checklist_template_id': checklistTemplateId,
        if (label != null) 'label': label,
        if (enabled != null) 'enabled': enabled,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', id);
      _ref.invalidate(serviceIntervalsProvider(assetId));
      success = true;
    });
    return success;
  }

  Future<bool> deleteInterval(String id, String assetId) async {
    state = const AsyncLoading();
    bool success = false;
    state = await AsyncValue.guard(() async {
      await supabase
          .from(AppConstants.tAssetServiceIntervals)
          .delete()
          .eq('id', id);
      _ref.invalidate(serviceIntervalsProvider(assetId));
      success = true;
    });
    return success;
  }
}

final serviceIntervalControllerProvider =
    StateNotifierProvider<ServiceIntervalController, AsyncValue<void>>((ref) {
  return ServiceIntervalController(ref);
});
