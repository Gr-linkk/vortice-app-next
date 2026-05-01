import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/models/profile.dart';
import 'package:vortice_app/models/subscription_tier.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';

/// Returns the effective tier for the current user.
/// Owner/employee bypass all gates — they see everything.
SubscriptionTier effectiveTier(Profile? profile) {
  if (profile == null) return SubscriptionTier.free;
  if (profile.role == UserRole.owner ||
      profile.role == UserRole.employee) {
    return SubscriptionTier.predictive;
  }
  return profile.subscriptionTier;
}

final tierProvider = Provider<SubscriptionTier>((ref) {
  final profile = ref.watch(profileProvider).valueOrNull;
  return effectiveTier(profile);
});

/// Check if the current user's tier is at or above the required tier.
bool hasTier(Profile? profile, SubscriptionTier required) {
  return effectiveTier(profile).value >= required.value;
}

/// True if the nav bar should show PM/scheduling tools (Planning+).
bool showPlanning(Profile? profile) {
  return effectiveTier(profile).hasPlanning;
}

/// True if telemetry screens should be accessible (Telemetry+).
bool showTelemetry(Profile? profile) {
  return effectiveTier(profile).hasTelemetry;
}
