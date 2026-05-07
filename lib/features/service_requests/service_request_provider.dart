import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/clients/client_context_provider.dart';
import 'package:vortice_app/models/profile.dart';
import 'package:vortice_app/models/service_request.dart';

const _serviceRequestSelect =
    '*, asset:assets(name), client:profiles!service_requests_client_id_fkey(full_name, email)';

final clientServiceRequestsProvider =
    FutureProvider<List<ServiceRequest>>((ref) async {
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

final staffServiceRequestsProvider =
    FutureProvider<List<ServiceRequest>>((ref) async {
  final profile = await ref.watch(profileProvider.future);
  if (profile == null || !_canUseStaffServiceRequests(profile.role)) {
    return [];
  }

  final data = await supabase
      .from(AppConstants.tServiceRequests)
      .select(_serviceRequestSelect)
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

  Future<bool> submitRequest({
    required String title,
    required String description,
    required ServiceRequestUrgency urgency,
    String? assetId,
  }) async {
    state = const AsyncLoading();
    var success = false;
    state = await AsyncValue.guard(() async {
      final profile = await _ref.read(profileProvider.future);
      if (profile == null) throw Exception('Not authenticated');

      if (!_canUseClientServiceRequests(profile.role)) {
        throw Exception(
            'Service requests are available to client/admin users.');
      }

      final clientId = await _ref.read(currentClientIdProvider.future);
      if (clientId == null) {
        throw Exception('Unable to resolve client account for this request.');
      }

      await supabase.from(AppConstants.tServiceRequests).insert({
        'client_id': clientId,
        if (assetId != null) 'asset_id': assetId,
        'title': title.trim(),
        'description': description.trim(),
        'urgency':
            urgency == ServiceRequestUrgency.urgent ? 'urgent' : 'normal',
        'status': 'new',
      });

      _ref.invalidate(clientServiceRequestsProvider);
      _ref.invalidate(staffServiceRequestsProvider);
      _ref.invalidate(newServiceRequestCountProvider);
      success = true;
    });
    return success;
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

      await supabase.from(AppConstants.tServiceRequests).update({
        'status':
            status == ServiceRequestStatus.resolved ? 'resolved' : 'declined',
        'handled_at': DateTime.now().toIso8601String(),
        'handled_by': profile.id,
      }).eq('id', id);

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

bool _canUseClientServiceRequests(UserRole role) {
  return role == UserRole.client || role == UserRole.clientAdmin;
}

bool _canUseStaffServiceRequests(UserRole role) {
  return role == UserRole.owner || role == UserRole.employee;
}
