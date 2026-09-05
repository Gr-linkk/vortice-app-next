import 'package:freezed_annotation/freezed_annotation.dart';

part 'client_org.freezed.dart';
part 'client_org.g.dart';

@freezed
abstract class ClientOrg with _$ClientOrg {
  const factory ClientOrg({
    required String id,
    required String name,
    @JsonKey(name: 'owner_profile_id') required String ownerProfileId,
    @JsonKey(name: 'subscription_tier') @Default(0) int subscriptionTier,
    @JsonKey(name: 'created_at') DateTime? createdAt,
  }) = _ClientOrg;

  factory ClientOrg.fromJson(Map<String, dynamic> json) =>
      _$ClientOrgFromJson(json);
}
