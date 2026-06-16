import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/core/route_access_policy.dart';
import 'package:vortice_app/models/profile.dart';

String dashboardRouteForRole(UserRole? role) => switch (role) {
      UserRole.owner => '/owner/dashboard',
      UserRole.employee => '/employee/dashboard',
      UserRole.client => '/client/dashboard',
      UserRole.operator => '/client/dashboard',
      UserRole.clientAdmin => '/client/dashboard',
      UserRole.clientMechanic => '/client/dashboard',
      UserRole.clientOperator => '/client/dashboard',
      null => '/login',
    };

bool isAuthRoute(String location) =>
    location == '/login' || location == '/register';

/// Pure redirect decision used by GoRouter — returns a path or null to stay put.
String? resolveAuthRedirect({
  required AppAuthStatus authStatus,
  required String location,
}) {
  if (authStatus.isLoading) return null;

  final onAuthRoute = isAuthRoute(location);

  if (!authStatus.isAuthenticated) {
    return onAuthRoute ? null : '/login';
  }

  if (onAuthRoute) return dashboardRouteForRole(authStatus.profile?.role);

  final routeAccessRedirect = resolveRouteAccessRedirect(
    role: authStatus.profile?.role,
    location: location,
    dashboardRouteForRole: dashboardRouteForRole,
  );
  if (routeAccessRedirect != null) return routeAccessRedirect;

  return null;
}
