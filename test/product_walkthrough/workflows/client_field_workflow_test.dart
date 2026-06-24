import '../workflow_test_support.dart';

/// Backlog: A041, A042, A045, A048
void main() {
  workflowTddGroup('client_field', 'Client field workflow (A041, A042, A045, A048)', () {
    backlogAcceptanceTests('client_field', [
      'A041',
      'A042',
      'A045',
      'A048',
    ]);
  });
}
