import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/debug/route_qa_screen.dart';
import 'package:vortice_app/models/profile.dart';

void main() {
  group('RouteQaResult', () {
    test('passes when expected and actual redirects match', () {
      const result = RouteQaResult(
        roleLabel: 'Client Mechanic',
        route: '/client/work-orders',
        expectedRedirect: '/client/dashboard',
        actualRedirect: '/client/dashboard',
      );

      expect(result.passed, isTrue);
      expect(result.displayResult, 'Redirects to /client/dashboard');
    });

    test('passes allowed routes when no redirect is expected', () {
      const result = RouteQaResult(
        roleLabel: 'Client Admin',
        route: '/client/service-reports',
        expectedRedirect: null,
        actualRedirect: null,
      );

      expect(result.passed, isTrue);
      expect(result.displayResult, 'Allowed');
    });

    test('fails when a sensitive route is allowed unexpectedly', () {
      const result = RouteQaResult(
        roleLabel: 'Client Mechanic',
        route: '/client/work-orders/wo-test',
        expectedRedirect: '/client/dashboard',
        actualRedirect: null,
      );

      expect(result.passed, isFalse);
    });
  });

  group('expectedRouteQaRedirect', () {
    test('expects client-side roles to redirect off internal work-order routes',
        () {
      expect(
        expectedRouteQaRedirect(
          role: UserRole.clientMechanic,
          location: '/client/work-orders/wo-test',
        ),
        '/client/dashboard',
      );
    });

    test('expects client service-report authoring to redirect to history', () {
      expect(
        expectedRouteQaRedirect(
          role: UserRole.clientAdmin,
          location: '/client/service-reports/new',
        ),
        '/client/service-reports',
      );
    });

    test('allows client-safe history routes', () {
      expect(
        expectedRouteQaRedirect(
          role: UserRole.clientAdmin,
          location: '/client/service-reports',
        ),
        isNull,
      );
    });
  });
}
