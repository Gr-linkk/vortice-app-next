import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/checklists/checklist_submission_orchestrator.dart';
import 'package:vortice_app/features/operator/operator_issue_details.dart';
import 'package:vortice_app/models/checklist_item.dart';

void main() {
  const reading = ChecklistItem(
    id: 'reading',
    templateId: 'template',
    descriptionEn: 'Record pressure',
    definition: {'input_type': 'number', 'max': 50},
  );
  test(
    'a numeric failure keeps its reading and needs a separate issue message',
    () {
      final notes = {'reading': '72'};
      expect(
        () => validateOperationsChecklist(
          [reading],
          {'reading': 'action'},
          notes,
          23,
          issues: {},
        ),
        throwsA(isA<OperationsChecklistValidationException>()),
      );
      validateOperationsChecklist(
        [reading],
        {'reading': 'action'},
        notes,
        23,
        issues: {
          'reading': {
            'message': 'Pressure rises after shutdown',
            'urgency': 'urgent',
            'safe_to_operate': 'unsafe',
          },
        },
      );
      expect(notes['reading'], '72');
    },
  );
  test('a removed flag cannot submit stale issue metadata', () {
    expect(
      () => validateOperationsChecklist(
        [reading],
        {'reading': 'pass'},
        {'reading': '40'},
        23,
        issues: {
          'reading': {'message': 'Old issue'},
        },
      ),
      throwsA(isA<OperationsChecklistValidationException>()),
    );
  });
  testWidgets('safety and urgency edits retain dictated message', (
    tester,
  ) async {
    Map<String, dynamic> issue = {
      'message': 'Coolant leaking',
      'urgency': 'normal',
      'safe_to_operate': 'unknown',
    };
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => OperatorIssueDetails(
              value: issue,
              separateMessage: true,
              onChanged: (value) => setState(() => issue = value),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Urgent'));
    await tester.pump();
    await tester.tap(find.text('Unsafe'));
    await tester.pump();
    expect(issue, {
      'message': 'Coolant leaking',
      'urgency': 'urgent',
      'safe_to_operate': 'unsafe',
    });
  });
}
