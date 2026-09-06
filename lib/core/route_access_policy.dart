import 'package:vortice_app/models/profile.dart';
import 'package:vortice_app/features/fleet/fleet_policy.dart';
import 'package:vortice_app/features/maintenance/maintenance_models.dart';

bool isVorticeStaffRole(UserRole? role) =>
    role == UserRole.owner || role == UserRole.employee;

bool isClientSideRole(UserRole? role) =>
    role == UserRole.client ||
    role == UserRole.clientAdmin ||
    role == UserRole.clientMechanic ||
    role == UserRole.clientOperator ||
    role == UserRole.operator;

bool isClientInternalWorkOrderRoute(String location) =>
    location == '/client/work-orders' ||
    location.startsWith('/client/work-orders/') ||
    location.startsWith('/client/checklists/');

bool isClientServiceReportAuthoringRoute(String location) =>
    location == '/client/service-reports/new';

bool isRetiredMeetingRequestRoute(String location) =>
    location == '/meeting-request';

String? resolveRouteAccessRedirect({
  required UserRole? role,
  required String location,
  required String Function(UserRole? role) dashboardRouteForRole,
}) {
  if (role == null) return null;
  if (location == '/fleet/overview' && !canManageFleet(role)) {
    return dashboardRouteForRole(role);
  }
  if ((location == '/maintenance' || location.startsWith('/maintenance/')) &&
      !canUseMaintenance(role)) {
    return dashboardRouteForRole(role);
  }

  if (isRetiredMeetingRequestRoute(location)) {
    return dashboardRouteForRole(role);
  }

  if (isClientInternalWorkOrderRoute(location)) {
    return dashboardRouteForRole(role);
  }

  if (isClientServiceReportAuthoringRoute(location) &&
      !isVorticeStaffRole(role)) {
    return '/client/service-reports';
  }

  return null;
}
