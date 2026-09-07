import 'package:flutter/material.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/features/checklists/checklist_answer_fields.dart';
import 'checklist_builder_repository.dart';

class ChecklistPreviewScreen extends StatefulWidget {
  const ChecklistPreviewScreen({super.key, required this.draft});
  final Map<String, dynamic> draft;
  @override
  State<ChecklistPreviewScreen> createState() => _ChecklistPreviewScreenState();
}

class _ChecklistPreviewScreenState extends State<ChecklistPreviewScreen> {
  final _results = <int, String?>{}, _values = <int, String>{};
  @override
  Widget build(BuildContext context) {
    final es = isSpanish(context), items = checklistRows(widget.draft['items']);
    return Scaffold(
      appBar: AppBar(title: Text(es ? 'Vista previa' : 'Preview checklist')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            widget.draft['name'] as String? ?? '',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          Text(
            es
                ? 'Prueba los pasos. Las respuestas de esta vista previa no se guardan.'
                : 'Try the steps. Preview answers are not saved.',
          ),
          if ((widget.draft['description'] as String? ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(widget.draft['description'] as String),
            ),
          for (var i = 0; i < items.length; i++)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ChecklistAnswerFields(
                      item: items[i],
                      result: _results[i],
                      value: _values[i] ?? '',
                      onResult: (value) => setState(() => _results[i] = value),
                      onValue: (value) => setState(() => _values[i] = value),
                    ),
                    if (items[i]['requires_photo'] == true)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          es
                              ? 'Foto requerida al completar este paso.'
                              : 'Photo required when completing this step.',
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
