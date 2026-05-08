import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/assets/asset_workflow_policy.dart';
import 'package:vortice_app/models/profile.dart';

void main() {
  group('AssetWorkflowPolicy', () {
    test('maps each role to the existing asset route prefix', () {
      expect(AssetWorkflowPolicy.routePrefixForRole(UserRole.owner), '/owner');
      expect(
        AssetWorkflowPolicy.routePrefixForRole(UserRole.employee),
        '/employee',
      );
      expect(
          AssetWorkflowPolicy.routePrefixForRole(UserRole.client), '/client');
      expect(
        AssetWorkflowPolicy.routePrefixForRole(UserRole.operator),
        '/operator',
      );
      expect(
        AssetWorkflowPolicy.routePrefixForRole(UserRole.clientAdmin),
        '/client',
      );
      expect(
        AssetWorkflowPolicy.routePrefixForRole(UserRole.clientMechanic),
        '/client',
      );
      expect(
        AssetWorkflowPolicy.routePrefixForRole(UserRole.clientOperator),
        '/client',
      );
      expect(AssetWorkflowPolicy.routePrefixForRole(null), '/owner');
    });

    test('allows checklist history for roles that previously saw the card', () {
      const visibleRoles = [
        UserRole.owner,
        UserRole.employee,
        UserRole.client,
        UserRole.clientAdmin,
        UserRole.clientMechanic,
        UserRole.operator,
        UserRole.clientOperator,
      ];

      for (final role in visibleRoles) {
        expect(
          AssetWorkflowPolicy.canSeeChecklistHistory(role),
          isTrue,
          reason: '$role should see checklist history',
        );
      }
      expect(AssetWorkflowPolicy.canSeeChecklistHistory(null), isFalse);
    });

    test('allows maintenance plan for owner and client maintenance roles only',
        () {
      const visibleRoles = [
        UserRole.owner,
        UserRole.client,
        UserRole.clientAdmin,
        UserRole.clientMechanic,
      ];
      const hiddenRoles = [
        UserRole.employee,
        UserRole.operator,
        UserRole.clientOperator,
      ];

      for (final role in visibleRoles) {
        expect(
          AssetWorkflowPolicy.canSeeMaintenancePlan(role),
          isTrue,
          reason: '$role should see maintenance plan',
        );
      }
      for (final role in hiddenRoles) {
        expect(
          AssetWorkflowPolicy.canSeeMaintenancePlan(role),
          isFalse,
          reason: '$role should not see maintenance plan',
        );
      }
      expect(AssetWorkflowPolicy.canSeeMaintenancePlan(null), isFalse);
    });

    test('allows client maintenance roles to start client-side checklists', () {
      const allowedRoles = [
        UserRole.client,
        UserRole.clientAdmin,
        UserRole.clientMechanic,
      ];
      const hiddenRoles = [
        UserRole.owner,
        UserRole.employee,
        UserRole.operator,
        UserRole.clientOperator,
      ];

      for (final role in allowedRoles) {
        expect(
          AssetWorkflowPolicy.canStartClientChecklist(role),
          isTrue,
          reason: '$role should start client-side checklists',
        );
      }
      for (final role in hiddenRoles) {
        expect(
          AssetWorkflowPolicy.canStartClientChecklist(role),
          isFalse,
          reason: '$role should not start client-side checklists',
        );
      }
      expect(AssetWorkflowPolicy.canStartClientChecklist(null), isFalse);
    });

    test('keeps asset management and engine visibility owner-only', () {
      for (final role in UserRole.values) {
        final expected = role == UserRole.owner;
        expect(
          AssetWorkflowPolicy.canManageAsset(role),
          expected,
          reason: '$role management policy changed',
        );
        expect(
          AssetWorkflowPolicy.canSeeEngines(role),
          expected,
          reason: '$role engine policy changed',
        );
      }

      expect(AssetWorkflowPolicy.canManageAsset(null), isFalse);
      expect(AssetWorkflowPolicy.canSeeEngines(null), isFalse);
    });
  });
}
