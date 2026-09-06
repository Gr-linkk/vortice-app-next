import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/maintenance/maintenance_models.dart';
import 'package:vortice_app/features/maintenance/maintenance_repository.dart';
import 'package:vortice_app/features/service_reports/service_report_index.dart';
import 'package:vortice_app/features/service_reports/service_report_repository.dart';
import 'package:vortice_app/features/service_reports/service_report_workflow.dart';
import 'package:vortice_app/models/service_report.dart';
import 'package:vortice_app/models/service_report_photo.dart';

final serviceReportsProvider = FutureProvider<List<ServiceReport>>((ref) {
  return ref.watch(serviceReportRepositoryProvider).listAll();
});

/// Service reports with asset name — used by client dashboards
final clientServiceReportsProvider = FutureProvider<List<Map<String, dynamic>>>(
  (ref) async {
    final profile = await ref.watch(profileProvider.future);
    if (!ServiceReportWorkflow.canViewReport(profile?.role)) return [];
    final data = await supabase.rpc('provider_service_reports');
    final jobs = await ref.watch(maintenanceJobsProvider(null).future);
    final result = [
      ...List<Map<String, dynamic>>.from(data as List),
      for (final entry in combineServiceReports([], jobs))
        if (entry.maintenance!.status == 'closed')
          {
            'id': entry.maintenance!.id,
            'maintenance_job_id': entry.maintenance!.id,
            'correction': entry.maintenance!.report['repair'],
            'comments': entry.maintenance!.report['notes'],
            'created_at': entry.date?.toIso8601String(),
            'work_order_id': entry.maintenance!.id,
            'work_orders': {
              'asset_id': entry.maintenance!.assetId,
              'assets': {'name': entry.maintenance!.assetName},
            },
          },
    ];
    result.sort(
      (a, b) => (b['created_at']?.toString() ?? '').compareTo(
        a['created_at']?.toString() ?? '',
      ),
    );
    return result.take(10).toList();
  },
);

final serviceReportByIdProvider = FutureProvider.family<ServiceReport?, String>(
  (ref, reportId) {
    return ref.watch(serviceReportRepositoryProvider).getById(reportId);
  },
);

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

/// Uses checked RPCs for both internal and provider reports. A mention or asset
/// relationship never broadens job access.
final serviceReportIndexProvider = FutureProvider.autoDispose
    .family<List<ServiceReportEntry>, ServiceReportScope>((ref, scope) async {
      final profile = await ref.watch(profileProvider.future);
      if (!ServiceReportWorkflow.canViewReport(profile?.role)) return [];
      final legacy = scope.workOrderId != null
          ? ref.watch(
              serviceReportsByWorkOrderProvider(scope.workOrderId!).future,
            )
          : scope.assetId != null
          ? ref.watch(serviceReportsForAssetProvider(scope.assetId!).future)
          : ref.watch(serviceReportsProvider.future);
      final Future<List<MaintenanceJob>> managed = scope.workOrderId != null
          ? ref
                .watch(maintenanceJobProvider(scope.workOrderId!).future)
                .then((job) => job == null ? <MaintenanceJob>[] : [job])
          : ref.watch(maintenanceJobsProvider(scope.assetId).future);
      final values = await Future.wait<Object>([legacy, managed]);
      return combineServiceReports(
        values[0] as List<ServiceReport>,
        values[1] as List<MaintenanceJob>,
      );
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
      result = await _ref
          .read(serviceReportRepositoryProvider)
          .createLocalFirst(
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
      _ref.invalidate(serviceReportsForAssetProvider);
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
    FutureProvider.family<List<ServiceReportPhoto>, String>((
      ref,
      reportId,
    ) async {
      final profile = await ref.watch(profileProvider.future);
      if (!ServiceReportWorkflow.canViewReport(profile?.role)) return [];
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
      await supabase
          .from(AppConstants.tServiceReportPhotos)
          .insert({
            'service_report_id': serviceReportId,
            'photo_url': photoUrl,
            'caption': caption,
            'sort_order': sortOrder,
            'uploaded_by': uploadedBy,
          })
          .timeout(const Duration(seconds: 4));
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
    StateNotifierProvider<ServiceReportPhotoController, AsyncValue<void>>((
      ref,
    ) {
      return ServiceReportPhotoController(ref);
    });
