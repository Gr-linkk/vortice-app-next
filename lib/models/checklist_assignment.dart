import 'package:freezed_annotation/freezed_annotation.dart';

part 'checklist_assignment.freezed.dart';
part 'checklist_assignment.g.dart';

enum AssignmentStatus { pending, inProgress, completed, cancelled }

@freezed
abstract class ChecklistAssignment with _$ChecklistAssignment {
  const factory ChecklistAssignment({
    required String id,
    @JsonKey(name: 'template_id') required String templateId,
    @JsonKey(name: 'asset_id') String? assetId,
    @JsonKey(name: 'assigned_to') required String assignedTo,
    @JsonKey(name: 'assigned_by') required String assignedBy,
    @JsonKey(name: 'org_id') required String orgId,
    @Default(AssignmentStatus.pending)
    @JsonKey(name: 'status', fromJson: _statusFromJson, toJson: _statusToJson)
    AssignmentStatus status,
    @JsonKey(name: 'due_date') DateTime? dueDate,
    @JsonKey(name: 'completed_at') DateTime? completedAt,
    String? notes,
    @JsonKey(name: 'created_at') DateTime? createdAt,
    @JsonKey(name: 'updated_at') DateTime? updatedAt,
  }) = _ChecklistAssignment;

  factory ChecklistAssignment.fromJson(Map<String, dynamic> json) =>
      _$ChecklistAssignmentFromJson(json);
}

AssignmentStatus _statusFromJson(String v) => switch (v) {
      'in_progress' => AssignmentStatus.inProgress,
      'completed' => AssignmentStatus.completed,
      'cancelled' => AssignmentStatus.cancelled,
      _ => AssignmentStatus.pending,
    };

String _statusToJson(AssignmentStatus s) => switch (s) {
      AssignmentStatus.inProgress => 'in_progress',
      AssignmentStatus.completed => 'completed',
      AssignmentStatus.cancelled => 'cancelled',
      AssignmentStatus.pending => 'pending',
    };
