import 'package:freezed_annotation/freezed_annotation.dart';

part 'parts_inventory.freezed.dart';
part 'parts_inventory.g.dart';

@freezed
class PartsInventory with _$PartsInventory {
  const factory PartsInventory({
    required String id,
    required String description,
    @JsonKey(name: 'part_number') String? partNumber,
    @JsonKey(name: 'qty_on_hand') @Default(0.0) double qtyOnHand,
    @JsonKey(name: 'min_stock_level') @Default(0.0) double minStockLevel,
    String? location,
    String? supplier,
    @JsonKey(name: 'last_unit_cost') @Default(0.0) double lastUnitCost,
    @JsonKey(name: 'created_at') DateTime? createdAt,
    @JsonKey(name: 'updated_at') DateTime? updatedAt,
  }) = _PartsInventory;

  factory PartsInventory.fromJson(Map<String, dynamic> json) =>
      _$PartsInventoryFromJson(json);
}
