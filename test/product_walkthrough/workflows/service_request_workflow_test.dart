import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/service_requests/service_request_workflow_policy.dart';

import '../workflow_test_support.dart';

/// Backlog: A027, A028
void main() {
  workflowTddGroup('service_request', 'Service request workflow (A027, A028)', () {
    test('A027 client submit and owner work-order handoff', () {
      expect(
        ServiceRequestWorkflowPolicy.clientCanSubmitServiceRequest(),
        isTrue,
      );
      expect(
        ServiceRequestWorkflowPolicy.ownerCanGenerateWorkOrderFromRequest(),
        isTrue,
      );
      expect(
        ServiceRequestWorkflowPolicy.maintenanceDraftCarriesServiceRequestId(),
        isTrue,
      );
    });

    test('A028 client sees accepted acknowledgment', () {
      expect(
        ServiceRequestWorkflowPolicy.clientSeesAcceptedStatusLabel(),
        isTrue,
      );
      expect(
        ServiceRequestWorkflowPolicy.clientAcknowledgmentIncludesHandledTimestamp(),
        isTrue,
      );
      expect(
        ServiceRequestWorkflowPolicy.clientStatusWordingIsClientFriendly(),
        isTrue,
      );
    });
  });
}
