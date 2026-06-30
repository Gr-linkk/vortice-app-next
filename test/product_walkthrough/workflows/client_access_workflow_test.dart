import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/clients/client_access_workflow_policy.dart';

import '../workflow_test_support.dart';

/// Backlog: A030, A031, A033, A036, A044
void main() {
  workflowTddGroup('client_access', 'Client access workflow (A030, A031, A033, A036, A044)', () {
    test('A030 client assets are scoped and WO routes redirect', () {
      expect(ClientAccessWorkflowPolicy.clientAssetsAreScoped(), isTrue);
      expect(
        ClientAccessWorkflowPolicy.clientWorkOrderRoutesRedirectToDashboard(),
        isTrue,
      );
    });

    test('A031 clients run checklists without editing templates', () {
      expect(
        ClientAccessWorkflowPolicy.clientCanRunChecklistsWithoutEditingTemplates(),
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

    test('A044 client team uses scoped asset access', () {
      expect(
        ClientAccessWorkflowPolicy.clientTeamUsesScopedAssetAccess(),
        isTrue,
      );
    });
  });
}
