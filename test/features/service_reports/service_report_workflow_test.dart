import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/service_reports/service_report_workflow.dart';
import 'package:vortice_app/models/profile.dart';
import 'package:vortice_app/models/work_order.dart';

void main() {
  group('ServiceReportWorkflow', () {
    test('only staff can create reports', () {
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
      expect(ServiceReportWorkflow.canCreateOrUpdateReport(UserRole.operator),
          isFalse);
    });

    test('clients can view reports but operators cannot', () {
      expect(ServiceReportWorkflow.canViewReport(UserRole.owner), isTrue);
      expect(ServiceReportWorkflow.canViewReport(UserRole.employee), isTrue);
      expect(ServiceReportWorkflow.canViewReport(UserRole.client), isTrue);
      expect(
          ServiceReportWorkflow.canViewReport(UserRole.clientAdmin), isTrue);
      expect(
          ServiceReportWorkflow.canViewReport(UserRole.clientMechanic),
          isTrue);
      expect(ServiceReportWorkflow.canViewReport(UserRole.operator), isFalse);
      expect(
          ServiceReportWorkflow.canViewReport(UserRole.clientOperator),
          isFalse);
    });

    test('reports can attach to invoiced and closed work orders', () {
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
        isTrue,
      );
    });
  });
}
