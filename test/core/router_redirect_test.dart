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
      const owner = Profile(
        id: 'p-1',
        email: 'owner@vortice.dev',
        role: UserRole.owner,
        fullName: 'Owner',
      );
      expect(
        resolveAuthRedirect(
          authStatus: const AppAuthStatus(
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
      const tech = Profile(
        id: 'p-2',
        email: 'tech@vortice.dev',
        role: UserRole.employee,
        fullName: 'Tech',
      );
      expect(
        resolveAuthRedirect(
          authStatus: const AppAuthStatus(
            isLoading: false,
            isAuthenticated: true,
            profile: tech,
          ),
          location: '/employee/work-orders',
        ),
        isNull,
      );
    });

    test('redirects client-side roles away from internal work-order routes',
        () {
      const mechanic = Profile(
        id: 'p-3',
        email: 'mechanic@vortice.dev',
        role: UserRole.clientMechanic,
        fullName: 'Client Mechanic',
      );
      const status = AppAuthStatus(
        isLoading: false,
        isAuthenticated: true,
        profile: mechanic,
      );

      expect(
        resolveAuthRedirect(
          authStatus: status,
          location: '/client/work-orders',
        ),
        '/client/dashboard',
      );
      expect(
        resolveAuthRedirect(
          authStatus: status,
          location: '/client/work-orders/wo-1',
        ),
        '/client/dashboard',
      );
      expect(
        resolveAuthRedirect(
          authStatus: status,
          location: '/client/checklists/wo-1',
        ),
        '/client/dashboard',
      );
    });

    test('redirects stale meeting request route to the role dashboard', () {
      const owner = Profile(
        id: 'p-4',
        email: 'owner@vortice.dev',
        role: UserRole.owner,
        fullName: 'Owner',
      );

      expect(
        resolveAuthRedirect(
          authStatus: const AppAuthStatus(
            isLoading: false,
            isAuthenticated: true,
            profile: owner,
          ),
          location: '/meeting-request',
        ),
        '/owner/dashboard',
      );
    });

    test('redirects client service-report authoring to report history', () {
      const client = Profile(
        id: 'p-5',
        email: 'client@vortice.dev',
        role: UserRole.clientAdmin,
        fullName: 'Client Admin',
      );

      expect(
        resolveAuthRedirect(
          authStatus: const AppAuthStatus(
            isLoading: false,
            isAuthenticated: true,
            profile: client,
          ),
          location: '/client/service-reports/new',
        ),
        '/client/service-reports',
      );
    });
  });
}
