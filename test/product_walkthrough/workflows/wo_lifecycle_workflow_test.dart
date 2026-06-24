import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/work_orders/work_order_completion_policy.dart';
import 'package:vortice_app/features/work_orders/work_order_detail_actions_policy.dart';
import 'package:vortice_app/l10n/app_localizations_en.dart';
import 'package:vortice_app/models/work_order.dart';
import 'package:vortice_app/product_walkthrough/product_walkthrough_verifiers.dart';

import '../workflow_test_support.dart';

/// Backlog: A004, A005, A006
/// Walkthrough order: work order detail -> service report -> close/status
void main() {
  workflowTddGroup('wo_lifecycle', 'WO lifecycle (A004, A005, A006)', () {
    group('A004 service report section 4 wording', () {
      test('uses Contingent damage instead of Secondary damage', () {
        final l10n = AppLocalizationsEn();
        expect(
          l10n.srSecondaryDamage.toLowerCase(),
          contains('contingent damage'),
        );
        expect(
          l10n.srSecondaryDamage.toLowerCase(),
          isNot(contains('secondary damage')),
        );
      });
    });

    group('A005 service report required before close', () {
      test('cannot mark completed without a submitted service report', () {
        expect(
          WorkOrderCompletionPolicy.canMarkCompleted(
            status: WorkOrderStatus.inProgress,
            hasSubmittedServiceReport: false,
          ),
          isFalse,
        );
      });

      test('can mark completed when a service report was submitted', () {
        expect(
          WorkOrderCompletionPolicy.canMarkCompleted(
            status: WorkOrderStatus.inProgress,
            hasSubmittedServiceReport: true,
          ),
          isTrue,
        );
      });

      test('explains missing service report before completion', () {
        expect(
          WorkOrderCompletionPolicy.shouldExplainMissingServiceReport(
            status: WorkOrderStatus.inProgress,
            hasSubmittedServiceReport: false,
          ),
          isTrue,
        );
      });

      test('keeps submitted service reports linked from work order detail', () {
        expect(
          verifyProductWalkthroughCheck('A005', 3),
          isTrue,
          reason: 'Backlog A005-3',
        );
      });
    });

    group('A006 status transitions stay coherent with completion rules', () {
      test('legacy detail policy still exposes mark completed on in progress', () {
        expect(
          WorkOrderDetailActionsPolicy.canCompleteWorkOrder(
            canManageStatus: true,
            status: WorkOrderStatus.inProgress,
          ),
          isTrue,
        );
      });

      test('completion policy stays aligned with mandatory service report', () {
        expect(
          WorkOrderCompletionPolicy.canMarkCompleted(
            status: WorkOrderStatus.inProgress,
            hasSubmittedServiceReport: false,
          ),
          isFalse,
        );
      });
    });
  });
}
