import 'package:freezed_annotation/freezed_annotation.dart';

part 'asset_engine.freezed.dart';
part 'asset_engine.g.dart';

@freezed
abstract class AssetEngine with _$AssetEngine {
  const factory AssetEngine({
    required String id,
    @JsonKey(name: 'asset_id') required String assetId,
    required String label,
    @Default('main') String kind,
    String? make,
    String? model,
    @JsonKey(name: 'serial_number') String? serialNumber,
    @JsonKey(name: 'current_hours') @Default(0) double currentHours,
    @JsonKey(name: 'telemetry_channel') String? telemetryChannel,
    @JsonKey(name: 'created_at') DateTime? createdAt,
    @JsonKey(name: 'updated_at') DateTime? updatedAt,
  }) = _AssetEngine;

  factory AssetEngine.fromJson(Map<String, dynamic> json) => _$AssetEngineFromJson(json);
}
