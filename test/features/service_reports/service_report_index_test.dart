import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/assets/asset_service_reports_card.dart';
import 'package:vortice_app/features/maintenance/maintenance_models.dart';
import 'package:vortice_app/features/service_reports/service_report_index.dart';
import 'package:vortice_app/features/service_reports/service_report_list_screen.dart';
import 'package:vortice_app/features/service_reports/service_report_provider.dart';
import 'package:vortice_app/models/asset.dart';
import 'package:vortice_app/models/service_report.dart';
import '../fleet/fleet_test_support.dart';
import '../maintenance/maintenance_screen_test.dart' as maintenance;

void main() {
  setUpAll(loadFleetScreenshotFonts);
  for (final es in [false, true]) {
    testWidgets(
      'report index fits narrow large-text ${es ? 'Spanish' : 'English'}',
      (tester) async {
        await maintenance.pumpMaintenance(
          tester,
          const ServiceReportListScreen(initialAssetId: 'asset'),
          maintenance.FixtureMaintenance(
            job: maintenance.jobData(status: 'closed'),
          ),
          es: es,
          width: 320,
          scale: 1.5,
          overrides: [
            serviceReportsForAssetProvider(
              'asset',
            ).overrideWith((_) async => []),
          ],
        );
        expect(find.text('250-hour generator service'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await captureFleet(
          tester,
          'audit-report-index-${es ? 'es' : 'en'}-320-large',
        );
      },
    );
  }
  testWidgets(
    'asset report list includes saved maintenance report and opens its job',
    (tester) async {
      await maintenance.pumpMaintenance(
        tester,
        const ServiceReportListScreen(initialAssetId: 'asset'),
        maintenance.FixtureMaintenance(
          job: maintenance.jobData(status: 'closed'),
        ),
        overrides: [
          serviceReportsForAssetProvider('asset').overrideWith((_) async => []),
        ],
      );
      expect(find.text('No service reports yet.'), findsNothing);
      expect(find.text('250-hour generator service'), findsOneWidget);
      await tester.tap(find.text('250-hour generator service'));
      await tester.pumpAndSettle();
      expect(find.text('Job saved'), findsOneWidget);
    },
  );
  testWidgets('asset report count includes maintenance reports', (
    tester,
  ) async {
    await maintenance.pumpMaintenance(
      tester,
      const Scaffold(
        body: AssetServiceReportsCard(
          asset: Asset(
            id: 'asset',
            clientId: 'company',
            assetTypeId: 'type',
            name: 'Test vessel',
          ),
          routePrefix: '/client',
        ),
      ),
      maintenance.FixtureMaintenance(
        job: maintenance.jobData(status: 'closed'),
      ),
      overrides: [
        serviceReportsForAssetProvider('asset').overrideWith((_) async => []),
      ],
    );
    expect(find.textContaining('1 report'), findsOneWidget);
    expect(find.text('No service reports attached yet'), findsNothing);
  });
  test(
    'report index retains both workflows and excludes jobs without reports',
    () {
      final entries = combineServiceReports(
        [
          ServiceReport(
            id: 'legacy-report',
            workOrderId: 'legacy-job',
            createdAt: DateTime.utc(2026, 9, 1),
          ),
        ],
        [
          MaintenanceJob({
            ...maintenance.jobData(),
            'events': [
              {'kind': 'submit', 'created_at': '2026-09-06T05:00:00Z'},
            ],
          }),
          MaintenanceJob({
            ...maintenance.jobData(),
            'id': 'empty-job',
            'report': null,
          }),
        ],
      );
      expect(entries, hasLength(2));
      expect(entries.first.route('/client'), '/maintenance/jobs/job');
      expect(
        entries.last.route('/client'),
        '/client/service-reports/legacy-report',
      );
      expect(entries.first.date, DateTime.utc(2026, 9, 6, 5));
    },
  );
}
