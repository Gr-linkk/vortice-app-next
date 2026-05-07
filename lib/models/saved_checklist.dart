import 'package:freezed_annotation/freezed_annotation.dart';

enum SavedChecklistType {
  @JsonValue('maintenance')
  maintenance,
  @JsonValue('operations')
  operations,
}

class SavedChecklist {
  final String id;
  final String assetId;
  final String clientId;
  final String? templateId;
  final String templateName;
  final SavedChecklistType checklistType;
  final String sourceType;
  final String? submittedBy;
  final String? submittedByRole;
  final DateTime submittedAt;
  final double? currentHours;
  final String? generalNotes;
  final String? workOrderId;
  final String? assignmentId;
  final Map<String, dynamic> snapshot;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const SavedChecklist({
    required this.id,
    required this.assetId,
    required this.clientId,
    this.templateId,
    required this.templateName,
    required this.checklistType,
    required this.sourceType,
    this.submittedBy,
    this.submittedByRole,
    required this.submittedAt,
    this.currentHours,
    this.generalNotes,
    this.workOrderId,
    this.assignmentId,
    required this.snapshot,
    this.createdAt,
    this.updatedAt,
  });

  factory SavedChecklist.fromJson(Map<String, dynamic> json) {
    return SavedChecklist(
      id: json['id'] as String,
      assetId: json['asset_id'] as String,
      clientId: json['client_id'] as String,
      templateId: json['template_id'] as String?,
      templateName: json['template_name'] as String,
      checklistType: _typeFromJson(json['checklist_type'] as String?),
      sourceType: json['source_type'] as String,
      submittedBy: json['submitted_by'] as String?,
      submittedByRole: json['submitted_by_role'] as String?,
      submittedAt: DateTime.parse(json['submitted_at'] as String),
      currentHours: (json['current_hours'] as num?)?.toDouble(),
      generalNotes: json['general_notes'] as String?,
      workOrderId: json['work_order_id'] as String?,
      assignmentId: json['assignment_id'] as String?,
      snapshot: Map<String, dynamic>.from(json['snapshot'] as Map),
      createdAt: json['created_at'] == null
          ? null
          : DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] == null
          ? null
          : DateTime.parse(json['updated_at'] as String),
    );
  }
}

SavedChecklistType _typeFromJson(String? value) {
  return value == 'operations'
      ? SavedChecklistType.operations
      : SavedChecklistType.maintenance;
}
