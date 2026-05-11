import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/service_reports/service_report_workflow.dart';
import 'package:vortice_app/models/profile.dart';
import 'package:vortice_app/models/work_order.dart';

void main() {
  group('ServiceReportWorkflow', () {
    test('staff can create reports, clients get read-only visibility', () {
      expect(ServiceReportWorkflow.canCreateOrUpdateReport(UserRole.owner),
          isTrue);
      expect(ServiceReportWorkflow.canCreateOrUpdateReport(UserRole.employee),
          isTrue);
      expect(ServiceReportWorkflow.canCreateOrUpdateReport(UserRole.client),
          isFalse);
      expect(
          ServiceReportWorkflow.canCreateOrUpdateReport(
              UserRole.clientMechanic),
          isFalse);

      expect(ServiceReportWorkflow.canViewReport(UserRole.client), isTrue);
      expect(
          ServiceReportWorkflow.canViewReport(UserRole.clientMechanic), isTrue);
      expect(ServiceReportWorkflow.canViewReport(UserRole.operator), isTrue);
    });

    test('reports can attach to closed work orders but not invoiced ones', () {
      expect(
        ServiceReportWorkflow.canAttachReportToWorkOrder(WorkOrderStatus.draft),
        isTrue,
      );
      expect(
        ServiceReportWorkflow.canAttachReportToWorkOrder(
            WorkOrderStatus.inProgress),
        isTrue,
      );
      expect(
        ServiceReportWorkflow.canAttachReportToWorkOrder(
            WorkOrderStatus.closed),
        isTrue,
      );
      expect(
        ServiceReportWorkflow.canAttachReportToWorkOrder(
            WorkOrderStatus.invoiced),
        isFalse,
      );
    });
  });
}
