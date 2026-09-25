import 'package:freezed_annotation/freezed_annotation.dart';

part 'work_order.freezed.dart';
part 'work_order.g.dart';

enum WorkOrderStatus {
  @JsonValue('draft')
  draft,
  @JsonValue('assigned')
  assigned,
  @JsonValue('in_progress')
  inProgress,
  @JsonValue('on_hold')
  onHold,
  @JsonValue('pending_review')
  pendingReview,
  @JsonValue('invoiced')
  invoiced,
  @JsonValue('closed')
  closed;

  // Returns the DB/API string value (snake_case)
  String get dbValue => switch (this) {
    WorkOrderStatus.inProgress => 'in_progress',
    WorkOrderStatus.onHold => 'on_hold',
    WorkOrderStatus.pendingReview => 'pending_review',
    _ => name,
  };
}

enum WorkOrderJobType {
  @JsonValue('preventative')
  preventative,
  @JsonValue('repair')
  repair,
  @JsonValue('inspection')
  inspection,
  @JsonValue('general')
  general;

  String get dbValue => name;

  String label(bool es, {bool fr = false}) => switch (this) {
    preventative =>
      fr
          ? 'Entretien préventif'
          : es
          ? 'Mantenimiento preventivo'
          : 'Preventive maintenance',
    repair =>
      fr
          ? 'Réparation'
          : es
          ? 'Reparación'
          : 'Repair',
    inspection =>
      fr
          ? 'Inspection'
          : es
          ? 'Inspección'
          : 'Inspection',
    general =>
      fr
          ? 'Travaux généraux'
          : es
          ? 'Trabajo general'
          : 'General work',
  };

  static WorkOrderJobType fromValue(String? value) =>
      values.where((type) => type.dbValue == value).firstOrNull ?? repair;
}

@freezed
abstract class WorkOrder with _$WorkOrder {
  const factory WorkOrder({
    required String id,
    @JsonKey(name: 'organization_relationship_id')
    String? organizationRelationshipId,
    @JsonKey(name: 'provider_organization_id') String? providerOrganizationId,
    @JsonKey(name: 'customer_organization_id') String? customerOrganizationId,
    @JsonKey(name: 'meter_unit') @Default('hours') String meterUnit,
    @JsonKey(name: 'asset_id') required String assetId,
    @JsonKey(name: 'engine_id') String? engineId,
    @JsonKey(name: 'client_id') required String clientId,
    @JsonKey(name: 'assigned_to') String? assignedTo,
    @JsonKey(name: 'created_by') String? createdBy,
    @JsonKey(name: 'checklist_template_id') String? checklistTemplateId,
    @JsonKey(name: 'checklist_template_version') int? checklistTemplateVersion,
    @JsonKey(name: 'job_type') required WorkOrderJobType jobType,
    @JsonKey(defaultValue: WorkOrderStatus.draft)
    required WorkOrderStatus status,
    required String title,
    String? description,
    @JsonKey(name: 'scheduled_date') DateTime? scheduledDate,
    @JsonKey(name: 'started_at') DateTime? startedAt,
    @JsonKey(name: 'completed_at') DateTime? completedAt,
    @JsonKey(name: 'hours_at_start') double? hoursAtStart,
    @JsonKey(name: 'hours_at_end') double? hoursAtEnd,
    @JsonKey(name: 'labour_hours') double? labourHours,
    @JsonKey(name: 'billable_rate') double? billableRate,
    @JsonKey(name: 'wage_rate') double? wageRate,
    @JsonKey(name: 'notes_internal') String? notesInternal,
    @JsonKey(name: 'on_hold_reason') String? onHoldReason,
    @JsonKey(name: 'created_at') DateTime? createdAt,
    @JsonKey(name: 'updated_at') DateTime? updatedAt,
  }) = _WorkOrder;

  factory WorkOrder.fromJson(Map<String, dynamic> json) =>
      _$WorkOrderFromJson(json);
}
