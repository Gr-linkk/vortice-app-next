import 'package:freezed_annotation/freezed_annotation.dart';

part 'parts_catalog.freezed.dart';
part 'parts_catalog.g.dart';

@freezed
abstract class PartsCatalog with _$PartsCatalog {
  const factory PartsCatalog({
    required String id,
    @JsonKey(name: 'part_number') String? partNumber,
    required String description,
    String? manufacturer,
    String? category,
    @JsonKey(name: 'unit_cost') double? unitCost,
    String? supplier,
    String? notes,
    @JsonKey(name: 'created_at') DateTime? createdAt,
    @JsonKey(name: 'updated_at') DateTime? updatedAt,
  }) = _PartsCatalog;

  factory PartsCatalog.fromJson(Map<String, dynamic> json) =>
      _$PartsCatalogFromJson(json);
}
