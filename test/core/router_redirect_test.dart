import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/core/router_redirect.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/models/profile.dart';

void main() {
  group('dashboardRouteForRole', () {
    test('maps staff and client roles to dashboard routes', () {
      expect(dashboardRouteForRole(UserRole.owner), '/owner/dashboard');
      expect(dashboardRouteForRole(UserRole.employee), '/employee/dashboard');
      expect(dashboardRouteForRole(UserRole.clientAdmin), '/client/dashboard');
      expect(dashboardRouteForRole(UserRole.operator), '/client/dashboard');
      expect(dashboardRouteForRole(null), '/login');
    });
  });

  group('resolveAuthRedirect', () {
    test('holds route while auth is loading', () {
      expect(
        resolveAuthRedirect(
          authStatus: AppAuthStatus.loading,
          location: '/owner/dashboard',
        ),
        isNull,
      );
    });

    test('sends unauthenticated users to login', () {
      expect(
        resolveAuthRedirect(
          authStatus: AppAuthStatus.unauthenticated,
          location: '/owner/dashboard',
        ),
        '/login',
      );
      expect(
        resolveAuthRedirect(
          authStatus: AppAuthStatus.unauthenticated,
          location: '/login',
        ),
        isNull,
      );
    });

    test('redirects authenticated users off auth routes', () {
      final owner = Profile(
        id: 'p-1',
        email: 'owner@vortice.dev',
        role: UserRole.owner,
        fullName: 'Owner',
      );
      expect(
        resolveAuthRedirect(
          authStatus: AppAuthStatus(
            isLoading: false,
            isAuthenticated: true,
            profile: owner,
          ),
          location: '/login',
        ),
        '/owner/dashboard',
      );
    });

    test('leaves authenticated users on in-app routes', () {
      final tech = Profile(
        id: 'p-2',
        email: 'tech@vortice.dev',
        role: UserRole.employee,
        fullName: 'Tech',
      );
      expect(
        resolveAuthRedirect(
          authStatus: AppAuthStatus(
            isLoading: false,
            isAuthenticated: true,
            profile: tech,
          ),
          location: '/employee/work-orders',
        ),
        isNull,
      );
    });
  });
}
