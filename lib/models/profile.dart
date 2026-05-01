import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:vortice_app/models/subscription_tier.dart';

part 'profile.freezed.dart';
part 'profile.g.dart';

enum UserRole {
  @JsonValue('owner') owner,
  @JsonValue('employee') employee,
  @JsonValue('client') client,
  @JsonValue('operator') operator,       // merged: was also client_operator
  @JsonValue('client_admin') clientAdmin,
  @JsonValue('client_mechanic') clientMechanic,
  @JsonValue('client_operator') clientOperator, // legacy — maps to operator in DB migration
}

@freezed
class Profile with _$Profile {
  const factory Profile({
    required String id,
    required String email,
    @JsonKey(name: 'full_name') required String fullName,
    @JsonKey(defaultValue: UserRole.employee) required UserRole role,
    String? phone,
    @JsonKey(name: 'preferred_language') @Default('en') String preferredLanguage,
    @JsonKey(name: 'org_code_used') String? orgCodeUsed,
    @JsonKey(name: 'org_id') String? orgId,
    @JsonKey(name: 'billable_rate') double? billableRate,
    @JsonKey(name: 'subscription_tier', fromJson: _tierFromJson, toJson: _tierToJson)
        @Default(SubscriptionTier.free)
        SubscriptionTier subscriptionTier,
    @JsonKey(name: 'created_at') DateTime? createdAt,
    @JsonKey(name: 'updated_at') DateTime? updatedAt,
  }) = _Profile;

  factory Profile.fromJson(Map<String, dynamic> json) => _$ProfileFromJson(json);
}

// ── Subscription tier JSON helpers (used by Freezed) ────────────────────────

SubscriptionTier _tierFromJson(dynamic v) {
  if (v == null) return SubscriptionTier.free;
  if (v is int) return SubscriptionTier.fromInt(v);
  if (v is String) return SubscriptionTier.fromInt(int.tryParse(v) ?? 0);
  return SubscriptionTier.free;
}

int _tierToJson(SubscriptionTier tier) => tier.value;
