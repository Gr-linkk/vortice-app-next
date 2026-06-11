import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/work_orders/work_order_detail_actions_policy.dart';
import 'package:vortice_app/features/work_orders/work_order_detail_support.dart';
import 'package:vortice_app/models/profile.dart';
import 'package:vortice_app/models/saved_checklist.dart';
import 'package:vortice_app/models/work_order.dart';

void main() {
  group('workOrderRoutePrefixForRole', () {
    test('maps staff and client roles to existing route prefixes', () {
      expect(workOrderRoutePrefixForRole(UserRole.owner), '/owner');
      expect(workOrderRoutePrefixForRole(UserRole.employee), '/employee');
      expect(workOrderRoutePrefixForRole(UserRole.clientAdmin), '/client');
      expect(workOrderRoutePrefixForRole(UserRole.clientMechanic), '/client');
      expect(workOrderRoutePrefixForRole(null), '/owner');
    });
  });

  group('workOrderStatusColor', () {
    test('maps active work to warning and closed work to success', () {
      expect(
        workOrderStatusColor(WorkOrderStatus.inProgress),
        AppColors.warning,
      );
      expect(workOrderStatusColor(WorkOrderStatus.closed), AppColors.success);
    });
  });

  group('savedChecklistFlaggedCount', () {
    test('counts monitor and action responses only', () {
      final row = SavedChecklist(
        id: 'sc-1',
        assetId: 'asset-1',
        clientId: 'client-1',
        templateId: 'tpl-1',
        templateName: 'Daily',
        checklistType: SavedChecklistType.maintenance,
        sourceType: 'client',
        submittedBy: 'user-1',
        submittedAt: DateTime(2026, 6, 1),
        snapshot: {
          'items': [
            {'response': 'pass'},
            {'response': 'monitor'},
            {'response': 'action'},
            {'response': 'n/a'},
          ],
        },
      );

      expect(savedChecklistFlaggedCount(row), 2);
    });
  });

  group('WorkOrderDetailActionsPolicy', () {
    test('hides checklist actions for closed or invoiced work orders', () {
      expect(
        WorkOrderDetailActionsPolicy.canOpenChecklist(
          canUseChecklist: true,
          checklistTemplateId: 'tpl-1',
          status: WorkOrderStatus.closed,
        ),
        isFalse,
      );
      expect(
        WorkOrderDetailActionsPolicy.canOpenChecklist(
          canUseChecklist: true,
          checklistTemplateId: 'tpl-1',
          status: WorkOrderStatus.invoiced,
        ),
        isFalse,
      );
    });

    test('canUseChecklist requires role and PM capability', () {
      expect(
        WorkOrderDetailActionsPolicy.canUseChecklist(
          isOwnerOrEmployee: true,
          isAssignedContributor: false,
          pmChecklistsAllowed: true,
        ),
        isTrue,
      );
      expect(
        WorkOrderDetailActionsPolicy.canUseChecklist(
          isOwnerOrEmployee: false,
          isAssignedContributor: true,
          pmChecklistsAllowed: true,
        ),
        isTrue,
      );
      expect(
        WorkOrderDetailActionsPolicy.canUseChecklist(
          isOwnerOrEmployee: true,
          isAssignedContributor: false,
          pmChecklistsAllowed: false,
        ),
        isFalse,
      );
    });

    test('shows actions section when status or checklist actions are available', () {
      expect(
        WorkOrderDetailActionsPolicy.showsActionsSection(
          canManageStatus: true,
          canOpenChecklist: false,
        ),
        isTrue,
      );
      expect(
        WorkOrderDetailActionsPolicy.showsActionsSection(
          canManageStatus: false,
          canOpenChecklist: true,
        ),
        isTrue,
      );
      expect(
        WorkOrderDetailActionsPolicy.showsActionsSection(
          canManageStatus: false,
          canOpenChecklist: false,
        ),
        isFalse,
      );
    });

    test('shows start and invoice actions only for allowed states', () {
      expect(
        WorkOrderDetailActionsPolicy.canStartWorkOrder(
          canManageStatus: true,
          status: WorkOrderStatus.assigned,
        ),
        isTrue,
      );
      expect(
        WorkOrderDetailActionsPolicy.canGenerateInvoice(
          isOwner: true,
          status: WorkOrderStatus.pendingReview,
        ),
        isTrue,
      );
      expect(
        WorkOrderDetailActionsPolicy.canGenerateInvoice(
          isOwner: false,
          status: WorkOrderStatus.pendingReview,
        ),
        isFalse,
      );
    });
  });
}
