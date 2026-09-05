import 'package:freezed_annotation/freezed_annotation.dart';

part 'work_order_assignment.freezed.dart';
part 'work_order_assignment.g.dart';

@freezed
abstract class WorkOrderAssignment with _$WorkOrderAssignment {
  const factory WorkOrderAssignment({
    required String id,
    @JsonKey(name: 'work_order_id') required String workOrderId,
    @JsonKey(name: 'profile_id') required String profileId,
    @Default('tech') String role,
    @JsonKey(name: 'hours_logged') double? hoursLogged,
    @JsonKey(name: 'billable_rate') double? billableRate,
    @JsonKey(name: 'started_at') DateTime? startedAt,
    @JsonKey(name: 'completed_at') DateTime? completedAt,
    @JsonKey(name: 'created_at') DateTime? createdAt,
  }) = _WorkOrderAssignment;

  factory WorkOrderAssignment.fromJson(Map<String, dynamic> json) =>
      _$WorkOrderAssignmentFromJson(json);
}
