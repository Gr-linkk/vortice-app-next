import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/models/meeting_request.dart';

final meetingRequestsProvider = FutureProvider<List<MeetingRequest>>((ref) async {
  final data = await supabase
      .from(AppConstants.tMeetingRequests)
      .select()
      .order('created_at', ascending: false);
  return (data as List)
      .map((e) => MeetingRequest.fromJson(e as Map<String, dynamic>))
      .toList();
});

class MeetingRequestController extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;
  MeetingRequestController(this._ref) : super(const AsyncData(null));

  Future<bool> submitRequest({
    String? interest,
    String? vesselCount,
    String? contactMethod,
    String? notes,
  }) async {
    state = const AsyncLoading();
    bool success = false;
    state = await AsyncValue.guard(() async {
      final profile = await _ref.read(profileProvider.future);
      if (profile == null) throw Exception('Not authenticated');

      await supabase.from(AppConstants.tMeetingRequests).insert({
        'profile_id': profile.id,
        if (interest != null) 'interest': interest,
        if (vesselCount != null) 'vessel_count': vesselCount,
        if (contactMethod != null) 'contact_method': contactMethod,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
        'status': 'pending',
      });

      _ref.invalidate(meetingRequestsProvider);
      success = true;
    });
    return success;
  }
}

final meetingRequestControllerProvider =
    StateNotifierProvider<MeetingRequestController, AsyncValue<void>>((ref) {
  return MeetingRequestController(ref);
});
