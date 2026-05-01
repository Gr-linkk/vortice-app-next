import 'package:freezed_annotation/freezed_annotation.dart';

part 'checklist_template.freezed.dart';
part 'checklist_template.g.dart';

@freezed
class ChecklistTemplate with _$ChecklistTemplate {
  const factory ChecklistTemplate({
    required String id,
    @JsonKey(name: 'asset_type_id') String? assetTypeId,
    @JsonKey(name: 'checklist_type') @Default('pm') String checklistType,
    @Default('general') String category,
    @JsonKey(name: 'interval_hours') int? intervalHours,
    @JsonKey(name: 'interval_label') String? intervalLabel,
    required String name,
    String? description,
    @Default(1) int version,
    @JsonKey(name: 'is_active') @Default(true) bool isActive,
    @JsonKey(name: 'source_doc_id') String? sourceDocId,
    @JsonKey(name: 'created_by') String? createdBy,
    @JsonKey(name: 'created_at') DateTime? createdAt,
    @JsonKey(name: 'updated_at') DateTime? updatedAt,
  }) = _ChecklistTemplate;

  factory ChecklistTemplate.fromJson(Map<String, dynamic> json) =>
      _$ChecklistTemplateFromJson(json);
}
