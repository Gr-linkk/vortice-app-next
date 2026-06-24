import '../workflow_test_support.dart';

/// Backlog: A021, A022, A023, A024, A025
void main() {
  workflowTddGroup('parts_log', 'Parts log workflow (A021, A022, A023, A024, A025)', () {
    backlogAcceptanceTests('parts_log', [
      'A021',
      'A022',
      'A023',
      'A024',
      'A025',
    ]);
  });
}
