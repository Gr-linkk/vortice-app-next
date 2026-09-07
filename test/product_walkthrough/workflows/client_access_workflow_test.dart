import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/clients/client_access_workflow_policy.dart';

/// Backlog: A030, A031, A033, A036, A044
void main() {
  group('Client access workflow (A030, A031, A033, A036, A044)', () {
    test('A030 client WO routes redirect', () {
      expect(
        ClientAccessWorkflowPolicy.clientWorkOrderRoutesRedirectToDashboard(),
        isTrue,
      );
    });

    test('A031 client mechanics can start checklists', () {
      expect(
        ClientAccessWorkflowPolicy.clientMechanicCanStartChecklist(),
        isTrue,
      );
    });

    test('A033 clients view but do not author service reports', () {
      expect(
        ClientAccessWorkflowPolicy.clientCanViewButNotAuthorServiceReports(),
        isTrue,
      );
      expect(
        ClientAccessWorkflowPolicy.clientServiceReportAuthoringIsBlocked(),
        isTrue,
      );
    });

    test('A036 maintenance and operations checklist types stay distinct', () {
      expect(
        ClientAccessWorkflowPolicy.savedChecklistTypesAreDistinct(),
        isTrue,
      );
      expect(
        ClientAccessWorkflowPolicy.operatorsDoNotSeeMaintenancePlan(),
        isTrue,
      );
    });
  });
}
