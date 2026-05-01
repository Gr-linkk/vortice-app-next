import 'package:freezed_annotation/freezed_annotation.dart';

part 'part.freezed.dart';
part 'part.g.dart';

@freezed
class Part with _$Part {
  const factory Part({
    required String id,
    @JsonKey(name: 'work_order_id') required String workOrderId,
    required String description,
    @JsonKey(name: 'part_number') String? partNumber,
    String? supplier,
    @JsonKey(defaultValue: 1) required double quantity,
    @JsonKey(name: 'unit_cost') @Default(0) double unitCost,
    @JsonKey(name: 'markup_pct') @Default(15.0) double markupPct,
    String? notes,
    @JsonKey(name: 'logged_by') String? loggedBy,
    @JsonKey(name: 'created_at') DateTime? createdAt,
    @JsonKey(name: 'updated_at') DateTime? updatedAt,
  }) = _Part;

  factory Part.fromJson(Map<String, dynamic> json) => _$PartFromJson(json);
}
