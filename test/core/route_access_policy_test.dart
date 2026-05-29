import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/core/route_access_policy.dart';
import 'package:vortice_app/models/profile.dart';

void main() {
  group('RouteAccessPolicy', () {
    test('redirects client-side direct work order routes to client dashboard',
        () {
      const clientRoles = [
        UserRole.client,
        UserRole.clientAdmin,
        UserRole.clientMechanic,
        UserRole.clientOperator,
        UserRole.operator,
      ];

      for (final role in clientRoles) {
        expect(
          RouteAccessPolicy.redirectFor(role, '/client/work-orders'),
          RouteAccessPolicy.clientDashboard,
          reason: '$role should not list internal work orders',
        );
        expect(
          RouteAccessPolicy.redirectFor(role, '/client/work-orders/wo-1'),
          RouteAccessPolicy.clientDashboard,
          reason: '$role should not open internal work order detail',
        );
      }
    });

    test('keeps checklist collaboration route available for client mechanics',
        () {
      expect(
        RouteAccessPolicy.redirectFor(
          UserRole.clientMechanic,
          '/client/checklists/wo-1',
        ),
        isNull,
      );
      expect(
        RouteAccessPolicy.redirectFor(
          UserRole.clientAdmin,
          '/client/checklists/wo-1',
        ),
        isNull,
      );
    });

    test('treats operator as client-side operations scope', () {
      expect(RouteAccessPolicy.isClientSideRole(UserRole.operator), isTrue);
      expect(
        RouteAccessPolicy.redirectFor(UserRole.operator, '/client/invoices'),
        RouteAccessPolicy.clientDashboard,
      );
      expect(
        RouteAccessPolicy.redirectFor(
            UserRole.operator, '/client/checklists/wo-1'),
        RouteAccessPolicy.clientDashboard,
      );
    });

    test('keeps client admin invoice access under client route scope', () {
      expect(
        RouteAccessPolicy.redirectFor(UserRole.clientAdmin, '/client/invoices'),
        isNull,
      );
      expect(
        RouteAccessPolicy.redirectFor(
            UserRole.clientAdmin, '/client/invoices/inv-1'),
        isNull,
      );
      expect(
        RouteAccessPolicy.redirectFor(
            UserRole.clientMechanic, '/client/invoices'),
        RouteAccessPolicy.clientDashboard,
      );
    });

    test('blocks client-side roles from staff route prefixes', () {
      expect(
        RouteAccessPolicy.redirectFor(
            UserRole.clientMechanic, '/owner/work-orders/wo-1'),
        RouteAccessPolicy.clientDashboard,
      );
      expect(
        RouteAccessPolicy.redirectFor(
            UserRole.clientAdmin, '/employee/checklists/wo-1'),
        RouteAccessPolicy.clientDashboard,
      );
    });

    test('does not block Vortice staff work order routes', () {
      expect(
        RouteAccessPolicy.redirectFor(
            UserRole.owner, '/owner/work-orders/wo-1'),
        isNull,
      );
      expect(
        RouteAccessPolicy.redirectFor(
            UserRole.employee, '/employee/checklists/wo-1'),
        isNull,
      );
    });
  });
}
