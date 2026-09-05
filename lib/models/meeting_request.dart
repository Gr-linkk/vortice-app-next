import 'package:freezed_annotation/freezed_annotation.dart';

part 'meeting_request.freezed.dart';
part 'meeting_request.g.dart';

@freezed
abstract class MeetingRequest with _$MeetingRequest {
  const factory MeetingRequest({
    required String id,
    @JsonKey(name: 'profile_id') required String profileId,
    String? interest,
    @JsonKey(name: 'vessel_count') String? vesselCount,
    @JsonKey(name: 'contact_method') String? contactMethod,
    String? notes,
    @JsonKey(defaultValue: 'pending') required String status,
    @JsonKey(name: 'created_at') DateTime? createdAt,
  }) = _MeetingRequest;

  factory MeetingRequest.fromJson(Map<String, dynamic> json) =>
      _$MeetingRequestFromJson(json);
}
