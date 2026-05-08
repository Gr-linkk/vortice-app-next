import 'package:vortice_app/models/profile.dart';

/// Central role policy for asset-level workflow navigation.
///
/// Capability checks remain owned by existing capability gates; this policy only
/// captures the role decisions that were local to the asset detail screen.
class AssetWorkflowPolicy {
  const AssetWorkflowPolicy._();

  static String routePrefixForRole(UserRole? role) => switch (role) {
        UserRole.owner => '/owner',
        UserRole.employee => '/employee',
        UserRole.client => '/client',
        UserRole.operator => '/operator',
        UserRole.clientAdmin => '/client',
        UserRole.clientMechanic => '/client',
        UserRole.clientOperator => '/client',
        null => '/owner',
      };

  static bool canSeeMaintenancePlan(UserRole? role) => switch (role) {
        UserRole.owner ||
        UserRole.client ||
        UserRole.clientAdmin ||
        UserRole.clientMechanic =>
          true,
        _ => false,
      };

  static bool canSeeChecklistHistory(UserRole? role) => switch (role) {
        UserRole.owner ||
        UserRole.employee ||
        UserRole.client ||
        UserRole.clientAdmin ||
        UserRole.clientMechanic ||
        UserRole.operator ||
        UserRole.clientOperator =>
          true,
        _ => false,
      };

  static bool canStartClientChecklist(UserRole? role) => switch (role) {
        UserRole.client ||
        UserRole.clientAdmin ||
        UserRole.clientMechanic =>
          true,
        _ => false,
      };

  static bool canManageAsset(UserRole? role) => role == UserRole.owner;

  static bool canSeeEngines(UserRole? role) => role == UserRole.owner;
}
