import 'package:vortice_app/models/profile.dart';

/// Central route policy for role-owned navigation boundaries.
///
/// Capability checks still live in capability gates because they may require
/// async client-org lookup. This policy owns the synchronous role decisions
/// that must be enforced before a route can build.
class RouteAccessPolicy {
  const RouteAccessPolicy._();

  static const clientDashboard = '/client/dashboard';

  static bool isClientSideRole(UserRole? role) => switch (role) {
        UserRole.client ||
        UserRole.clientAdmin ||
        UserRole.clientMechanic ||
        UserRole.clientOperator ||
        UserRole.operator =>
          true,
        _ => false,
      };

  static bool isVorticeStaffRole(UserRole? role) => switch (role) {
        UserRole.owner || UserRole.employee => true,
        _ => false,
      };

  static bool canAccessClientInvoices(UserRole? role) => switch (role) {
        UserRole.client || UserRole.clientAdmin => true,
        _ => false,
      };

  static bool canAccessClientChecklistRoute(UserRole? role) => switch (role) {
        UserRole.client ||
        UserRole.clientAdmin ||
        UserRole.clientMechanic =>
          true,
        _ => false,
      };

  static bool canAccessInternalWorkOrders(UserRole? role) =>
      isVorticeStaffRole(role);

  static bool canAccessLocation(UserRole? role, String location) =>
      redirectFor(role, location) == null;

  static String? redirectFor(UserRole? role, String location) {
    if (role == null) return null;
    if (location == clientDashboard) return null;

    if (isClientSideRole(role)) {
      if (_isStaffRoute(location)) return clientDashboard;
      if (_isClientWorkOrderRoute(location)) return clientDashboard;
      if (_isClientInvoiceRoute(location) && !canAccessClientInvoices(role)) {
        return clientDashboard;
      }
      if (_isClientChecklistRoute(location) &&
          !canAccessClientChecklistRoute(role)) {
        return clientDashboard;
      }
    }

    return null;
  }

  static bool _isStaffRoute(String location) =>
      location == '/owner' ||
      location.startsWith('/owner/') ||
      location == '/employee' ||
      location.startsWith('/employee/');

  static bool _isClientWorkOrderRoute(String location) =>
      location == '/client/work-orders' ||
      location.startsWith('/client/work-orders/');

  static bool _isClientChecklistRoute(String location) =>
      location.startsWith('/client/checklists/');

  static bool _isClientInvoiceRoute(String location) =>
      location == '/client/invoices' ||
      location.startsWith('/client/invoices/');
}
