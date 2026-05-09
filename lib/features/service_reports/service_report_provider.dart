import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/models/service_report.dart';
import 'package:vortice_app/models/service_report_photo.dart';

final serviceReportsProvider = FutureProvider<List<ServiceReport>>((ref) async {
  final data = await supabase
      .from(AppConstants.tServiceReports)
      .select()
      .order('created_at', ascending: false);
  return (data as List)
      .map((e) => ServiceReport.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// Service reports with asset name — used by client dashboards
final clientServiceReportsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final data = await supabase
      .from(AppConstants.tServiceReports)
      .select(
          'id, correction, comments, created_at, work_order_id, work_orders(asset_id, assets(name))')
      .order('created_at', ascending: false)
      .limit(10);
  return List<Map<String, dynamic>>.from(data as List);
});

final serviceReportByWorkOrderProvider =
    FutureProvider.family<ServiceReport?, String>((ref, workOrderId) async {
  final data = await supabase
      .from(AppConstants.tServiceReports)
      .select()
      .eq('work_order_id', workOrderId)
      .maybeSingle();
  if (data == null) return null;
  return ServiceReport.fromJson(data);
});

class ServiceReportController extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;
  ServiceReportController(this._ref) : super(const AsyncData(null));

  /// Creates/upserts a service report. Returns the report ID on success, null on failure.
  Future<String?> createReport({
    String? workOrderId,
    String? complaint,
    String? cause,
    String? correction,
    String? collateral,
    String? comments,
    String? techSignatureUrl,
  }) async {
    state = const AsyncLoading();
    String? reportId;
    state = await AsyncValue.guard(() async {
      final result = await supabase
          .from(AppConstants.tServiceReports)
          .upsert({
            'work_order_id':
                workOrderId?.isNotEmpty == true ? workOrderId : null,
            'complaint': complaint,
            'cause': cause,
            'correction': correction,
            'collateral': collateral,
            'comments': comments,
            'tech_signature_url': techSignatureUrl,
            'signed_at': techSignatureUrl != null
                ? DateTime.now().toIso8601String()
                : null,
          }, onConflict: 'work_order_id')
          .select('id')
          .single()
          .timeout(const Duration(seconds: 4));
      reportId = result['id'] as String;
      _ref.invalidate(serviceReportsProvider);
      if (workOrderId != null) {
        _ref.invalidate(serviceReportByWorkOrderProvider(workOrderId));
      }
    });
    return reportId;
  }
}

final serviceReportControllerProvider =
    StateNotifierProvider<ServiceReportController, AsyncValue<void>>((ref) {
  return ServiceReportController(ref);
});

// ── Service Report Photos ────────────────────────────────────────────────────

final serviceReportPhotosProvider =
    FutureProvider.family<List<ServiceReportPhoto>, String>(
        (ref, reportId) async {
  final data = await supabase
      .from(AppConstants.tServiceReportPhotos)
      .select()
      .eq('service_report_id', reportId)
      .order('sort_order');
  return (data as List)
      .map((e) => ServiceReportPhoto.fromJson(e as Map<String, dynamic>))
      .toList();
});

class ServiceReportPhotoController extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;
  ServiceReportPhotoController(this._ref) : super(const AsyncData(null));

  Future<bool> addPhoto({
    required String serviceReportId,
    required String photoUrl,
    String? caption,
    int sortOrder = 0,
    String? uploadedBy,
  }) async {
    state = const AsyncLoading();
    bool success = false;
    state = await AsyncValue.guard(() async {
      await supabase.from(AppConstants.tServiceReportPhotos).insert({
        'service_report_id': serviceReportId,
        'photo_url': photoUrl,
        'caption': caption,
        'sort_order': sortOrder,
        'uploaded_by': uploadedBy,
      }).timeout(const Duration(seconds: 4));
      _ref.invalidate(serviceReportPhotosProvider(serviceReportId));
      success = true;
    });
    return success;
  }

  Future<bool> deletePhoto(String photoId, String serviceReportId) async {
    state = const AsyncLoading();
    bool success = false;
    state = await AsyncValue.guard(() async {
      await supabase
          .from(AppConstants.tServiceReportPhotos)
          .delete()
          .eq('id', photoId)
          .timeout(const Duration(seconds: 4));
      _ref.invalidate(serviceReportPhotosProvider(serviceReportId));
      success = true;
    });
    return success;
  }
}

final serviceReportPhotoControllerProvider =
    StateNotifierProvider<ServiceReportPhotoController, AsyncValue<void>>(
        (ref) {
  return ServiceReportPhotoController(ref);
});
