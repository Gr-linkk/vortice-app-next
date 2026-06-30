import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/work_orders/work_order_completion_policy.dart';
import 'package:vortice_app/models/service_report.dart';
import 'package:vortice_app/models/work_order.dart';
import 'package:vortice_app/sync/sync_status.dart';

void main() {
  group('WorkOrderCompletionPolicy', () {
    test('blocks completion without a submitted service report', () {
      expect(
        WorkOrderCompletionPolicy.canMarkCompleted(
          status: WorkOrderStatus.inProgress,
          hasSubmittedServiceReport: false,
        ),
        isFalse,
      );
    });

    test('allows completion when a service report was submitted', () {
      expect(
        WorkOrderCompletionPolicy.canMarkCompleted(
          status: WorkOrderStatus.inProgress,
          hasSubmittedServiceReport: true,
        ),
        isTrue,
      );
    });

    test('treats signed reports as submitted', () {
      final report = ServiceReport(
        id: 'sr-1',
        workOrderId: 'wo-1',
        signedAt: DateTime(2026, 6, 18),
      );

      expect(
        WorkOrderCompletionPolicy.isSubmittedServiceReport(report),
        isTrue,
      );
    });

    test('ignores empty pending-create drafts', () {
      const report = ServiceReport(
        id: 'sr-1',
        workOrderId: 'wo-1',
        syncStatus: SyncStatusValues.pendingCreate,
      );

      expect(
        WorkOrderCompletionPolicy.isSubmittedServiceReport(report),
        isFalse,
      );
    });
  });
}
