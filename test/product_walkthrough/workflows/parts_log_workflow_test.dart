import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/parts/parts_log_workflow_policy.dart';

import '../workflow_test_support.dart';

/// Backlog: A021, A022, A023, A024, A025
void main() {
  workflowTddGroup('parts_log', 'Parts log workflow (A021, A022, A023, A024, A025)', () {
    test('A021 technician hours attach to work order and invoice flow', () {
      expect(
        PartsLogWorkflowPolicy.employeeCanLogHoursOnWorkOrder(),
        isTrue,
      );
      expect(
        PartsLogWorkflowPolicy.ownerWorkOrderShowsLoggedParts(),
        isTrue,
      );
      expect(PartsLogWorkflowPolicy.invoiceUsesWorkOrderParts(), isTrue);
    });

    test('A022 parts log requires work-order link', () {
      expect(PartsLogWorkflowPolicy.partsLogRequiresWorkOrderLink(), isTrue);
    });

    test('A024 technician unit cost is optional', () {
      expect(PartsLogWorkflowPolicy.technicianUnitCostIsOptional(), isTrue);
    });

    test('A025 parts schema includes notes field', () {
      expect(PartsLogWorkflowPolicy.partsPayloadIncludesNotesField(), isTrue);
    });

    test('owner parts screen is routed from owner dashboard', () {
      expect(PartsLogWorkflowPolicy.ownerPartsScreenIsRouted(), isTrue);
    });
  });
}
