import '../workflow_test_support.dart';

/// Backlog: A027, A028
void main() {
  workflowTddGroup('service_request', 'Service request workflow (A027, A028)', () {
    backlogAcceptanceTests('service_request', ['A027', 'A028']);
  });
}
