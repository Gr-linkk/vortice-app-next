import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/orgs/org_admin_support.dart';
import 'package:vortice_app/models/client_capability.dart';
import 'package:vortice_app/models/invoice.dart';
import 'package:vortice_app/models/profile.dart';

Profile _profile({required String id, required UserRole role}) => Profile(
  id: id,
  email: '$id@example.com',
  fullName: 'Member $id',
  role: role,
);

ClientCapabilitySwitchboard _switchboard({
  bool pmChecklists = true,
  bool operationalChecklists = true,
}) => ClientCapabilitySwitchboard(
  clientId: 'client-1',
  enabledByCapability: {
    ClientCapability.pmChecklists: pmChecklists,
    ClientCapability.operationalChecklists: operationalChecklists,
  },
);

void main() {
  test('uses the supplied dark palette', () {
    expect(
      orgAdminMemberRoleColor(AppPalette.dark, UserRole.clientMechanic),
      AppPalette.dark.primary,
    );
  });
  group('orgAdminMemberRoleColor', () {
    test('maps org member roles to theme colors', () {
      expect(
        orgAdminMemberRoleColor(AppPalette.light, UserRole.clientMechanic),
        AppPalette.light.primary,
      );
      expect(
        orgAdminMemberRoleColor(AppPalette.light, UserRole.clientOperator),
        AppPalette.light.warning,
      );
      expect(
        orgAdminMemberRoleColor(AppPalette.light, UserRole.clientAdmin),
        AppPalette.light.success,
      );
      expect(
        orgAdminMemberRoleColor(AppPalette.light, UserRole.owner),
        AppPalette.light.textSecondary,
      );
    });
  });

  group('orgAdminMemberRoleLabel', () {
    test('maps org member roles to display labels', () {
      expect(orgAdminMemberRoleLabel(UserRole.clientMechanic), 'Mechanic');
      expect(orgAdminMemberRoleLabel(UserRole.clientOperator), 'Operator');
      expect(orgAdminMemberRoleLabel(UserRole.clientAdmin), 'Admin');
      expect(orgAdminMemberRoleLabel(UserRole.owner), 'owner');
    });
  });

  group('orgAdminCapabilityForRole', () {
    test('maps mechanic and operator roles to checklist capabilities', () {
      expect(
        orgAdminCapabilityForRole(UserRole.clientMechanic),
        ClientCapability.pmChecklists,
      );
      expect(
        orgAdminCapabilityForRole(UserRole.clientOperator),
        ClientCapability.operationalChecklists,
      );
      expect(
        orgAdminCapabilityForRole(UserRole.operator),
        ClientCapability.operationalChecklists,
      );
      expect(orgAdminCapabilityForRole(UserRole.clientAdmin), isNull);
    });
  });

  group('isOrgMemberWorkflowDisabled', () {
    test('returns false when role has no capability mapping', () {
      expect(
        isOrgMemberWorkflowDisabled(
          role: UserRole.clientAdmin,
          capabilities: _switchboard(pmChecklists: false),
        ),
        isFalse,
      );
    });

    test('returns true when required capability is disabled', () {
      expect(
        isOrgMemberWorkflowDisabled(
          role: UserRole.clientMechanic,
          capabilities: _switchboard(pmChecklists: false),
        ),
        isTrue,
      );
      expect(
        isOrgMemberWorkflowDisabled(
          role: UserRole.clientOperator,
          capabilities: _switchboard(operationalChecklists: false),
        ),
        isTrue,
      );
    });

    test('returns false when required capability is enabled', () {
      expect(
        isOrgMemberWorkflowDisabled(
          role: UserRole.clientMechanic,
          capabilities: _switchboard(pmChecklists: true),
        ),
        isFalse,
      );
    });
  });

  group('requiredCapabilityForInviteRole', () {
    test('maps invite role strings to checklist capabilities', () {
      expect(
        requiredCapabilityForInviteRole('client_mechanic'),
        ClientCapability.pmChecklists,
      );
      expect(
        requiredCapabilityForInviteRole('client_operator'),
        ClientCapability.operationalChecklists,
      );
    });
  });

  group('orgAdminInvoiceStatusColor', () {
    test('maps invoice statuses to theme colors', () {
      expect(
        orgAdminInvoiceStatusColor(AppPalette.light, InvoiceStatus.paid),
        AppPalette.light.success,
      );
      expect(
        orgAdminInvoiceStatusColor(AppPalette.light, InvoiceStatus.sent),
        AppPalette.light.warning,
      );
      expect(
        orgAdminInvoiceStatusColor(AppPalette.light, InvoiceStatus.draft),
        AppPalette.light.textSecondary,
      );
      expect(
        orgAdminInvoiceStatusColor(AppPalette.light, InvoiceStatus.voided),
        AppPalette.light.error,
      );
    });
  });

  group('orgAdminChecklistAssignmentStatusColor', () {
    test('maps assignment statuses to theme colors', () {
      expect(
        orgAdminChecklistAssignmentStatusColor(AppPalette.light, 'completed'),
        AppPalette.light.success,
      );
      expect(
        orgAdminChecklistAssignmentStatusColor(AppPalette.light, 'in_progress'),
        AppPalette.light.warning,
      );
      expect(
        orgAdminChecklistAssignmentStatusColor(AppPalette.light, 'cancelled'),
        AppPalette.light.textSecondary,
      );
      expect(
        orgAdminChecklistAssignmentStatusColor(AppPalette.light, 'pending'),
        AppPalette.light.primary,
      );
    });
  });

  group('isMemberEligibleForChecklistType', () {
    test('filters PM checklists to mechanics only', () {
      expect(
        isMemberEligibleForChecklistType(
          _profile(id: 'm1', role: UserRole.clientMechanic),
          'pm',
        ),
        isTrue,
      );
      expect(
        isMemberEligibleForChecklistType(
          _profile(id: 'o1', role: UserRole.clientOperator),
          'pm',
        ),
        isFalse,
      );
    });

    test('filters pre-op checklists to operators', () {
      expect(
        isMemberEligibleForChecklistType(
          _profile(id: 'o1', role: UserRole.clientOperator),
          'operator_daily',
        ),
        isTrue,
      );
      expect(
        isMemberEligibleForChecklistType(
          _profile(id: 'o2', role: UserRole.operator),
          'operator_daily',
        ),
        isTrue,
      );
      expect(
        isMemberEligibleForChecklistType(
          _profile(id: 'm1', role: UserRole.clientMechanic),
          'operator_daily',
        ),
        isFalse,
      );
    });
  });

  group('filterMembersForChecklistType', () {
    test('returns only eligible members for the checklist type', () {
      final members = [
        _profile(id: 'm1', role: UserRole.clientMechanic),
        _profile(id: 'o1', role: UserRole.clientOperator),
        _profile(id: 'o2', role: UserRole.operator),
        _profile(id: 'a1', role: UserRole.clientAdmin),
      ];

      expect(
        filterMembersForChecklistType(members, 'pm').map((m) => m.id).toList(),
        ['m1'],
      );
      expect(
        filterMembersForChecklistType(
          members,
          'operator_daily',
        ).map((m) => m.id).toList(),
        ['o1', 'o2'],
      );
    });
  });
}
