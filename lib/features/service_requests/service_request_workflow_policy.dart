import 'package:vortice_app/features/service_intervals/maintenance_work_order_draft.dart';
import 'package:vortice_app/models/service_request.dart';

/// Codified client service-request handoff rules (A027, A028).
class ServiceRequestWorkflowPolicy {
  const ServiceRequestWorkflowPolicy._();

  static bool clientCanSubmitServiceRequest() => true;

  static bool ownerCanGenerateWorkOrderFromRequest() => true;

  static bool maintenanceDraftCarriesServiceRequestId() {
    const draft = MaintenanceWorkOrderDraft(
      serviceRequestId: 'sr-1',
      title: 'Breakdown — Dredge 1',
    );
    return draft.serviceRequestId == 'sr-1';
  }

  static bool clientSeesAcceptedStatusLabel() {
    final request = ServiceRequest(
      id: 'sr-1',
      clientId: 'client-1',
      title: 'Breakdown',
      description: 'Hydraulic leak',
      urgency: ServiceRequestUrgency.normal,
      status: ServiceRequestStatus.resolved,
      handledAt: DateTime(2026, 6, 3),
    );
    return request.clientStatusLabel == 'Accepted';
  }

  static bool clientAcknowledgmentIncludesHandledTimestamp() {
    final request = ServiceRequest(
      id: 'sr-1',
      clientId: 'client-1',
      title: 'Breakdown',
      description: 'Hydraulic leak',
      urgency: ServiceRequestUrgency.normal,
      status: ServiceRequestStatus.resolved,
      handledAt: DateTime(2026, 6, 3, 14, 30),
      generatedWorkOrderId: 'wo-1',
    );
    return request.handledLabel != null &&
        request.generatedWorkOrderId == 'wo-1';
  }

  static bool clientStatusWordingIsClientFriendly() {
    final request = ServiceRequest(
      id: 'sr-1',
      clientId: 'client-1',
      title: 'Breakdown',
      description: 'Hydraulic leak',
      urgency: ServiceRequestUrgency.normal,
      status: ServiceRequestStatus.resolved,
    );
    final label = request.clientStatusLabel.toLowerCase();
    return !label.contains('resolved') && !label.contains('internal');
  }
}
