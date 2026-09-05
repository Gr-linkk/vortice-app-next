import 'package:freezed_annotation/freezed_annotation.dart';

part 'asset_type.freezed.dart';
part 'asset_type.g.dart';

@freezed
abstract class AssetTypeModel with _$AssetTypeModel {
  const factory AssetTypeModel({
    required String id,
    required String name,
    String? category,
    @JsonKey(name: 'icon_name') String? iconName,
    @JsonKey(name: 'created_at') DateTime? createdAt,
  }) = _AssetTypeModel;

  factory AssetTypeModel.fromJson(Map<String, dynamic> json) =>
      _$AssetTypeModelFromJson(json);
}
