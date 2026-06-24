import '../workflow_test_support.dart';

/// Backlog: A002, A003, A010, A020, A034
void main() {
  workflowTddGroup('pm_checklist', 'PM checklist workflow (A002, A003, A010, A020, A034)', () {
    backlogAcceptanceTests('pm_checklist', [
      'A002',
      'A003',
      'A010',
      'A020',
      'A034',
    ]);
  });
}
