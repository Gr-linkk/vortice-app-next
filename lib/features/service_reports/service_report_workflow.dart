import 'package:vortice_app/models/profile.dart';
import 'package:vortice_app/models/work_order.dart';

class ServiceReportWorkflow {
  const ServiceReportWorkflow._();

  static bool canCreateOrUpdateReport(UserRole? role) =>
      role == UserRole.owner || role == UserRole.employee;

  static bool canViewReport(UserRole? role) => switch (role) {
        UserRole.owner ||
        UserRole.employee ||
        UserRole.client ||
        UserRole.clientAdmin ||
        UserRole.clientMechanic =>
          true,
        _ => false,
      };

  static bool canAttachReportToWorkOrder(WorkOrderStatus status) => true;
}
