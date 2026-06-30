import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/clients/client_field_workflow_policy.dart';

import '../workflow_test_support.dart';

/// Backlog: A041, A042, A045, A048
void main() {
  workflowTddGroup('client_field', 'Client field workflow (A041, A042, A045, A048)', () {
    test('A041 client mechanic can start checklists and view history', () {
      expect(
        ClientFieldWorkflowPolicy.clientMechanicCanStartChecklist(),
        isTrue,
      );
      expect(
        ClientFieldWorkflowPolicy.clientMechanicCanSeeChecklistHistory(),
        isTrue,
      );
    });

    test('A042 checklist notes stay separate from service report authoring', () {
      expect(
        ClientFieldWorkflowPolicy
            .checklistNotesAreDistinctFromServiceReportAuthoring(),
        isTrue,
      );
    });

    test('A045 operator checklist run shows asset context', () {
      expect(
        ClientFieldWorkflowPolicy.operatorChecklistRunShowsAssetContext(),
        isTrue,
      );
    });

    test('A048 operator offline draft is persisted locally', () {
      expect(
        ClientFieldWorkflowPolicy.operatorOfflineDraftIsPersistedLocally(),
        isTrue,
      );
    });
  });
}
