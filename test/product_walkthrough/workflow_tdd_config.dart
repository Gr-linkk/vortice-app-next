/// Toggle workflow TDD files on one at a time.
///
/// 1. Uncomment the workflow key you are implementing.
/// 2. Run only that file, e.g.
///    `flutter test test/product_walkthrough/workflows/wo_lifecycle_workflow_test.dart`
/// 3. Implement until green, wire UI, then move to the next workflow.
const activeWorkflowTdd = <String>{
  'wo_lifecycle',
  'invoice',
  'pm_checklist',
  'client_access',
  'client_field',
  'service_request',
  'parts_log',
};

bool isWorkflowTddActive(String workflowKey) =>
    activeWorkflowTdd.contains(workflowKey);

String workflowTddSkipReason(String workflowKey) =>
    'Workflow TDD inactive. Add "$workflowKey" to activeWorkflowTdd in '
    'test/product_walkthrough/workflow_tdd_config.dart, then run this file.';
