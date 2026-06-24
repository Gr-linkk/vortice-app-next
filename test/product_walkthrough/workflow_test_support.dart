import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/product_walkthrough/product_walkthrough_checks.dart';
import 'package:vortice_app/product_walkthrough/product_walkthrough_verifiers.dart';

import 'workflow_tdd_config.dart';

void workflowTddGroup(
  String workflowKey,
  String description,
  void Function() body,
) {
  group(
    description,
    body,
    skip: isWorkflowTddActive(workflowKey)
        ? null
        : workflowTddSkipReason(workflowKey),
  );
}

void backlogAcceptanceTests(
  String workflowKey,
  Iterable<String> backlogIds,
) {
  for (final check in productWalkthroughChecksForBacklogIds(backlogIds)) {
    test('${check.id} ${check.description}', () {
      expect(
        verifyProductWalkthroughCheck(check.backlogId, check.checkIndex),
        isTrue,
        reason:
            'Backlog ${check.backlogId} check ${check.checkIndex}: ${check.description}',
      );
    });
  }
}
