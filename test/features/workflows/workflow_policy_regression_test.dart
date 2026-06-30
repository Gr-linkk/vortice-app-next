import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/checklists/checklist_history_display_support.dart';
import 'package:vortice_app/models/service_request.dart';

void main() {
  group('formatChecklistCompletedByDisplay', () {
    test('prefers human name over profile id', () {
      expect(
        formatChecklistCompletedByDisplay(
          completedByName: 'Alex Mechanic',
          completedBy: '00000000-0000-0000-0000-000000000001',
        ),
        'Alex Mechanic',
      );
    });
  });

  group('ServiceRequest client acknowledgment', () {
    test('resolved requests show accepted label and handled timestamp', () {
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

      expect(request.clientStatusLabel, 'Accepted');
      expect(request.handledLabel, isNotNull);
      expect(request.workOrderLinkLabel, 'Work order created');
    });
  });
}
