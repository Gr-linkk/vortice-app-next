import 'package:vortice_app/core/route_access_policy.dart';
import 'package:vortice_app/core/router_redirect.dart';
import 'package:vortice_app/features/assets/asset_workflow_policy.dart';
import 'package:vortice_app/features/service_reports/service_report_workflow.dart';
import 'package:vortice_app/models/profile.dart';
import 'package:vortice_app/models/saved_checklist.dart';

/// Codified client access and role-boundary rules (A030, A031, A033, A036, A044).
class ClientAccessWorkflowPolicy {
  const ClientAccessWorkflowPolicy._();

  static bool clientWorkOrderRoutesRedirectToDashboard() {
    return resolveRouteAccessRedirect(
          role: UserRole.client,
          location: '/client/work-orders',
          dashboardRouteForRole: dashboardRouteForRole,
        ) ==
        dashboardRouteForRole(UserRole.client);
  }

  static bool ownerCanManageClientAssetVisibility() =>
      AssetWorkflowPolicy.canManageAsset(UserRole.owner);

  static bool clientMechanicCanStartChecklist() {
    return AssetWorkflowPolicy.canStartClientChecklist(UserRole.clientMechanic);
  }

  static bool clientCanViewButNotAuthorServiceReports() {
    return ServiceReportWorkflow.canViewReport(UserRole.client) &&
        !ServiceReportWorkflow.canCreateOrUpdateReport(UserRole.client);
  }

  static bool clientServiceReportAuthoringIsBlocked() {
    final redirect = resolveRouteAccessRedirect(
      role: UserRole.client,
      location: '/client/service-reports/new',
      dashboardRouteForRole: dashboardRouteForRole,
    );
    return redirect == '/client/service-reports';
  }

  static bool savedChecklistTypesAreDistinct() {
    return SavedChecklistType.maintenance != SavedChecklistType.operations;
  }

  static bool operatorsDoNotSeeMaintenancePlan() {
    return !AssetWorkflowPolicy.canSeeMaintenancePlan(UserRole.operator) &&
        !AssetWorkflowPolicy.canSeeMaintenancePlan(UserRole.clientOperator);
  }
}
