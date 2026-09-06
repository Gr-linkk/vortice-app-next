import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/clients/client_context_provider.dart';
import 'package:vortice_app/models/profile.dart';
import 'package:vortice_app/models/service_request.dart';

const _serviceRequestSelect =
    '*, asset:assets(name, location), client:profiles!service_requests_client_id_fkey(full_name, email)';

class ServiceRequestSubmitResult {
  const ServiceRequestSubmitResult({required this.success, this.warning});

  final bool success;
  final String? warning;
}

final clientServiceRequestsProvider = FutureProvider<List<ServiceRequest>>((
  ref,
) async {
  final profile = await ref.watch(profileProvider.future);
  if (profile == null || !_canUseClientServiceRequests(profile.role)) {
    return [];
  }

  final clientId = await ref.watch(currentClientIdProvider.future);
  if (clientId == null) return [];

  final data = await supabase
      .from(AppConstants.tServiceRequests)
      .select(_serviceRequestSelect)
      .eq('client_id', clientId)
      .order('created_at', ascending: false);

  return (data as List)
      .map((e) => ServiceRequest.fromJson(e as Map<String, dynamic>))
      .toList();
});

final staffServiceRequestsProvider = FutureProvider<List<ServiceRequest>>((
  ref,
) async {
  final profile = await ref.watch(profileProvider.future);
  if (profile == null || !_canUseStaffServiceRequests(profile.role)) {
    return [];
  }

  final data = await supabase
      .from(AppConstants.tServiceRequests)
      .select(_serviceRequestSelect)
      .eq('status', 'new')
      .order('created_at', ascending: false);

  return (data as List)
      .map((e) => ServiceRequest.fromJson(e as Map<String, dynamic>))
      .toList();
});

final newServiceRequestCountProvider = FutureProvider<int>((ref) async {
  final requests = await ref.watch(staffServiceRequestsProvider.future);
  return requests
      .where((request) => request.status == ServiceRequestStatus.newRequest)
      .length;
});

class ServiceRequestController extends StateNotifier<AsyncValue<void>> {
  ServiceRequestController(this._ref) : super(const AsyncData(null));

  final Ref _ref;

  Future<ServiceRequestSubmitResult> submitRequest({
    required String requestTypeLabel,
    required String description,
    required String contactPhoneOrWhatsapp,
    String? assetId,
    String? otherAssetName,
    double? engineHours,
    List<Uint8List> photos = const [],
  }) async {
    state = const AsyncLoading();
    var success = false;
    String? warning;
    state = await AsyncValue.guard(() async {
      final profile = await _ref.read(profileProvider.future);
      if (profile == null) throw Exception('Not authenticated');

      if (!_canUseClientServiceRequests(profile.role)) {
        throw Exception(
          'Service requests are available to client/admin users.',
        );
      }

      final clientId = await _ref.read(currentClientIdProvider.future);
      if (clientId == null) {
        throw Exception('Unable to resolve client account for this request.');
      }

      final inserted = await supabase
          .from(AppConstants.tServiceRequests)
          .insert({
            'client_id': clientId,
            if (assetId != null) 'asset_id': assetId,
            if (otherAssetName?.trim().isNotEmpty == true)
              'other_asset_name': otherAssetName!.trim(),
            'title': requestTypeLabel.trim(),
            'request_type': _requestTypeValue(requestTypeLabel),
            'description': description.trim(),
            'contact_phone_or_whatsapp': contactPhoneOrWhatsapp.trim(),
            if (engineHours != null) 'engine_hours': engineHours,
            'urgency': 'normal',
            'status': 'new',
          })
          .select('id')
          .single();

      final requestId = inserted['id'] as String;

      if (photos.isNotEmpty) {
        try {
          final photoUrls = await _uploadServiceRequestPhotos(
            requestId: requestId,
            photos: photos,
          );
          await supabase
              .from(AppConstants.tServiceRequests)
              .update({'photo_urls': photoUrls})
              .eq('id', requestId);
        } catch (_) {
          warning = 'Request sent, but photos could not be attached.';
        }
      }

      _ref.invalidate(clientServiceRequestsProvider);
      _ref.invalidate(staffServiceRequestsProvider);
      _ref.invalidate(newServiceRequestCountProvider);
      success = true;
    });
    return ServiceRequestSubmitResult(success: success, warning: warning);
  }

  Future<List<String>> _uploadServiceRequestPhotos({
    required String requestId,
    required List<Uint8List> photos,
  }) async {
    final urls = <String>[];
    for (var i = 0; i < photos.length; i++) {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final path = '$requestId/${i}_$ts.jpg';
      await supabase.storage
          .from(AppConstants.bucketServiceRequestPhotos)
          .uploadBinary(
            path,
            photos[i],
            fileOptions: const FileOptions(contentType: 'image/jpeg'),
          )
          .timeout(const Duration(seconds: 6));
      urls.add(path);
    }
    return urls;
  }

  Future<bool> updateStatus(String id, ServiceRequestStatus status) async {
    state = const AsyncLoading();
    var success = false;
    state = await AsyncValue.guard(() async {
      final profile = await _ref.read(profileProvider.future);
      if (profile == null) throw Exception('Not authenticated');
      if (status == ServiceRequestStatus.newRequest) {
        throw Exception('Cannot reset a request to new in this MVP.');
      }

      await supabase
          .from(AppConstants.tServiceRequests)
          .update({
            'status': status == ServiceRequestStatus.resolved
                ? 'resolved'
                : 'declined',
            'handled_at': DateTime.now().toIso8601String(),
            'handled_by': profile.id,
          })
          .eq('id', id);

      _ref.invalidate(clientServiceRequestsProvider);
      _ref.invalidate(staffServiceRequestsProvider);
      _ref.invalidate(newServiceRequestCountProvider);
      success = true;
    });
    return success;
  }

  Future<bool> markGeneratedWorkOrder({
    required String id,
    required String workOrderId,
  }) async {
    state = const AsyncLoading();
    var success = false;
    state = await AsyncValue.guard(() async {
      final profile = await _ref.read(profileProvider.future);
      if (profile == null) throw Exception('Not authenticated');

      await supabase
          .from(AppConstants.tServiceRequests)
          .update({
            'status': 'resolved',
            'generated_work_order_id': workOrderId,
            'handled_at': DateTime.now().toIso8601String(),
            'handled_by': profile.id,
          })
          .eq('id', id);

      _ref.invalidate(clientServiceRequestsProvider);
      _ref.invalidate(staffServiceRequestsProvider);
      _ref.invalidate(newServiceRequestCountProvider);
      success = true;
    });
    return success;
  }
}

final serviceRequestControllerProvider =
    StateNotifierProvider<ServiceRequestController, AsyncValue<void>>((ref) {
      return ServiceRequestController(ref);
    });

String _requestTypeValue(String label) {
  switch (label.trim().toLowerCase()) {
    case 'breakdown':
      return 'breakdown';
    case 'service / maintenance':
      return 'service_maintenance';
    case 'safety concern':
      return 'safety_concern';
    default:
      return 'other_issue';
  }
}

bool _canUseClientServiceRequests(UserRole role) {
  return role == UserRole.client || role == UserRole.clientAdmin;
}

bool _canUseStaffServiceRequests(UserRole role) {
  return role == UserRole.owner || role == UserRole.employee;
}
