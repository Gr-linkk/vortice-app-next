import 'package:freezed_annotation/freezed_annotation.dart';

part 'pm_parts_requirement.freezed.dart';
part 'pm_parts_requirement.g.dart';

@freezed
class PmPartsRequirement with _$PmPartsRequirement {
  const factory PmPartsRequirement({
    required String id,
    @JsonKey(name: 'template_id') required String templateId,
    required String description,
    @JsonKey(name: 'part_number') String? partNumber,
    @Default(1.0) double qty,
    String? unit,
    String? notes,
    @JsonKey(name: 'created_at') DateTime? createdAt,
  }) = _PmPartsRequirement;

  factory PmPartsRequirement.fromJson(Map<String, dynamic> json) =>
      _$PmPartsRequirementFromJson(json);
}
