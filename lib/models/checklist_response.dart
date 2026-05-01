import 'package:freezed_annotation/freezed_annotation.dart';

part 'checklist_response.freezed.dart';
part 'checklist_response.g.dart';

@freezed
class ChecklistResponse with _$ChecklistResponse {
  const factory ChecklistResponse({
    required String id,
    @JsonKey(name: 'work_order_id') required String workOrderId,
    @JsonKey(name: 'checklist_item_id') required String checklistItemId,
    @Default(false) bool completed,
    String? notes,
    @JsonKey(name: 'photo_url') String? photoUrl,
    @JsonKey(name: 'completed_by') String? completedBy,
    @JsonKey(name: 'completed_at') DateTime? completedAt,
    @JsonKey(name: 'created_at') DateTime? createdAt,
  }) = _ChecklistResponse;

  factory ChecklistResponse.fromJson(Map<String, dynamic> json) =>
      _$ChecklistResponseFromJson(json);
}
