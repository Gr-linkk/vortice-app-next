import 'package:freezed_annotation/freezed_annotation.dart';

part 'asset_service_interval.freezed.dart';
part 'asset_service_interval.g.dart';

@freezed
class AssetServiceInterval with _$AssetServiceInterval {
  const factory AssetServiceInterval({
    required String id,
    @JsonKey(name: 'asset_id') required String assetId,
    @JsonKey(name: 'interval_hours') required double intervalHours,
    @JsonKey(name: 'checklist_template_id') String? checklistTemplateId,
    String? label,
    @Default(true) bool enabled,
    @JsonKey(name: 'created_at') DateTime? createdAt,
    @JsonKey(name: 'updated_at') DateTime? updatedAt,
  }) = _AssetServiceInterval;

  factory AssetServiceInterval.fromJson(Map<String, dynamic> json) =>
      _$AssetServiceIntervalFromJson(json);
}
