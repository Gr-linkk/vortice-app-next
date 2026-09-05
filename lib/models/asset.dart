import 'package:freezed_annotation/freezed_annotation.dart';

part 'asset.freezed.dart';
part 'asset.g.dart';

@freezed
abstract class Asset with _$Asset {
  const factory Asset({
    required String id,
    @JsonKey(name: 'client_id') required String clientId,
    @JsonKey(name: 'asset_type_id') required String assetTypeId,
    required String name,
    String? make,
    String? model,
    int? year,
    @JsonKey(name: 'serial_number') String? serialNumber,
    String? location,
    String? notes,
    @JsonKey(name: 'telemetry_enabled') @Default(false) bool telemetryEnabled,
    @JsonKey(name: 'telemetry_source') String? telemetrySource,
    @JsonKey(name: 'created_at') DateTime? createdAt,
    @JsonKey(name: 'updated_at') DateTime? updatedAt,
  }) = _Asset;

  factory Asset.fromJson(Map<String, dynamic> json) => _$AssetFromJson(json);
}
