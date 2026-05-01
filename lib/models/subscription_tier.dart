/// Subscription tier levels for Vórtice clients.
/// Lower number = less features. Owner/employee bypass all tiers.
enum SubscriptionTier {
  free(0, 'Free'),
  managed(1, 'Managed'),
  planning(2, 'Planning'),
  telemetry(3, 'Telemetry'),
  predictive(4, 'Predictive');

  const SubscriptionTier(this.value, this.displayName);
  final int value;
  final String displayName;

  static SubscriptionTier fromInt(int v) =>
      SubscriptionTier.values.firstWhere((t) => t.value == v, orElse: () => SubscriptionTier.free);

  bool get isManaged => this == SubscriptionTier.managed;
  bool get isFree => this == SubscriptionTier.free;
  bool get hasPlanning => value >= SubscriptionTier.planning.value;
  bool get hasTelemetry => value >= SubscriptionTier.telemetry.value;
  bool get hasPredictive => value >= SubscriptionTier.predictive.value;
}
