import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/service_reports/service_report_authoring_policy.dart';

void main() {
  group('hasServiceReportAuthoringWorkOrder', () {
    test('requires a non-empty work order id', () {
      expect(hasServiceReportAuthoringWorkOrder(null), isFalse);
      expect(hasServiceReportAuthoringWorkOrder(''), isFalse);
      expect(hasServiceReportAuthoringWorkOrder('   '), isFalse);
      expect(hasServiceReportAuthoringWorkOrder('wo-1'), isTrue);
    });
  });

  group('canOpenServiceReportAuthoring', () {
    test('requires create access and a work order id', () {
      expect(
        canOpenServiceReportAuthoring(
          canCreate: false,
          workOrderId: 'wo-1',
        ),
        isFalse,
      );
      expect(
        canOpenServiceReportAuthoring(
          canCreate: true,
          workOrderId: null,
        ),
        isFalse,
      );
      expect(
        canOpenServiceReportAuthoring(
          canCreate: true,
          workOrderId: 'wo-1',
        ),
        isTrue,
      );
    });
  });

  group('serviceReportAuthoringRedirect', () {
    test('redirects loose authoring entry points to history', () {
      expect(
        serviceReportAuthoringRedirect(
          historyRoute: '/owner/service-reports',
          workOrderId: null,
        ),
        '/owner/service-reports',
      );
    });

    test('allows work-order-scoped authoring entry points', () {
      expect(
        serviceReportAuthoringRedirect(
          historyRoute: '/owner/service-reports',
          workOrderId: 'wo-1',
        ),
        isNull,
      );
    });
  });
}
