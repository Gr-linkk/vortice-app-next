import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/service_reports/service_report_list_screen.dart';

void main() {
  group('serviceReportAuthoringRoute', () {
    test('routes work-order scoped authoring to v2 with the work order id', () {
      expect(
        serviceReportAuthoringRoute(prefix: '/employee', workOrderId: 'wo-1'),
        '/employee/service-reports/new-v2?workOrderId=wo-1',
      );
    });

    test('does not create orphan service reports without a work order', () {
      expect(
        serviceReportAuthoringRoute(prefix: '/owner', workOrderId: null),
        isNull,
      );
      expect(
        serviceReportAuthoringRoute(prefix: '/owner', workOrderId: ''),
        isNull,
      );
    });

    test('encodes work order ids for query parameters', () {
      expect(
        serviceReportAuthoringRoute(
          prefix: '/owner',
          workOrderId: 'wo 1/2',
        ),
        '/owner/service-reports/new-v2?workOrderId=wo%201%2F2',
      );
    });
  });
}
