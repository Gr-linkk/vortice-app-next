import '../workflow_test_support.dart';

/// Backlog: A030, A031, A033, A036, A044
void main() {
  workflowTddGroup('client_access', 'Client access workflow (A030, A031, A033, A036, A044)', () {
    backlogAcceptanceTests('client_access', [
      'A030',
      'A031',
      'A033',
      'A036',
      'A044',
    ]);
  });
}
