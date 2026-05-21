import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/features/service_reports/service_report_repository.dart';
import 'package:vortice_app/models/service_report.dart';
import 'package:vortice_app/models/service_report_photo.dart';

final serviceReportsProvider = FutureProvider<List<ServiceReport>>((ref) {
  return ref.watch(serviceReportRepositoryProvider).listAll();
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

final serviceReportByIdProvider =
    FutureProvider.family<ServiceReport?, String>((ref, reportId) {
  return ref.watch(serviceReportRepositoryProvider).getById(reportId);
});

final serviceReportsByWorkOrderProvider =
    FutureProvider.family<List<ServiceReport>, String>((ref, workOrderId) {
  return ref
      .watch(serviceReportRepositoryProvider)
      .listByWorkOrder(workOrderId);
});

final serviceReportsForAssetProvider =
    FutureProvider.family<List<ServiceReport>, String>((ref, assetId) {
  return ref.watch(serviceReportRepositoryProvider).listForAsset(assetId);
});

class ServiceReportController extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;
  ServiceReportController(this._ref) : super(const AsyncData(null));

  /// Creates a new service report locally first, then attempts remote sync.
  Future<ServiceReportSubmitResult?> createReport({
    String? reportId,
    required String workOrderId,
    String? complaint,
    String? cause,
    String? correction,
    String? collateral,
    String? comments,
    String? techSignatureUrl,
  }) async {
    state = const AsyncLoading();
    ServiceReportSubmitResult? result;
    state = await AsyncValue.guard(() async {
      result =
          await _ref.read(serviceReportRepositoryProvider).createLocalFirst(
                reportId: reportId,
                workOrderId: workOrderId,
                complaint: complaint,
                cause: cause,
                correction: correction,
                collateral: collateral,
                comments: comments,
                techSignatureUrl: techSignatureUrl,
              );
      _ref.invalidate(serviceReportsProvider);
      _ref.invalidate(clientServiceReportsProvider);
      _ref.invalidate(serviceReportsByWorkOrderProvider(workOrderId));
    });
    return result;
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
