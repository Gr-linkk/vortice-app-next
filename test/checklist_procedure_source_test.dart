import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/checklist_builder/checklist_step_screen.dart';
import 'package:vortice_app/features/checklists/checklist_procedure_source.dart';

void main() {
  test(
    'legacy manual citations survive and malformed page numbers are rejected',
    () {
      final source = ChecklistProcedureSource.fromDefinition({
        'source_document_id': 'manual',
        'source_page': 3,
      });
      expect(source?.page, 3);
      expect(
        ChecklistProcedureSource.fromDefinition({
          'procedure_source': {'document_id': 'manual', 'page': 1.5},
        }),
        isNull,
      );
      expect(
        ChecklistProcedureSource.fromDefinition({
          'procedure_source': {'document_id': 'manual', 'page': 31},
        }),
        isNull,
      );
      expect(
        ChecklistProcedureSource.fromDefinition({
          'procedure_source': {
            'document_id': 'manual',
            'page': 2,
            'section': 'Engine 7.2',
          },
        })?.section,
        'Engine 7.2',
      );
    },
  );

  testWidgets(
    'editing instructions retains frozen equipment state and source',
    (tester) async {
      Map<String, dynamic>? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  saved = await Navigator.push<Map<String, dynamic>>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ChecklistStepScreen(
                        initial: {
                          'description_en': 'Inspect cooling system',
                          'definition': {
                            'equipment_state': 'stopped',
                            'input_type': 'check',
                            'guidance': 'Wait for pressure to fall',
                          },
                        },
                      ),
                    ),
                  );
                },
                child: const Text('Edit'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.text('Stopped'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Save step'),
        350,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('Save step'));
      await tester.pumpAndSettle();
      expect(saved?['definition']['equipment_state'], 'stopped');
      expect(saved?['definition']['guidance'], 'Wait for pressure to fall');
    },
  );
}
