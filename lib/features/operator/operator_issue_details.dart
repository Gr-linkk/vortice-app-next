import 'package:flutter/material.dart';
import 'package:vortice_app/core/user_feedback.dart';

class OperatorIssueDetails extends StatelessWidget {
  const OperatorIssueDetails({
    super.key,
    required this.value,
    required this.onChanged,
    this.separateMessage = false,
    this.critical = false,
  });
  final Map<String, dynamic> value;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final bool separateMessage, critical;
  @override
  Widget build(BuildContext context) {
    final es = isSpanish(context);
    final urgency =
        value['urgency'] as String? ?? (critical ? 'urgent' : 'normal');
    final safe = value['safe_to_operate'] as String? ?? 'unknown';
    Widget choices(
      String label,
      String key,
      String selected,
      List<(String, String)> options,
    ) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Text(label, style: Theme.of(context).textTheme.labelLarge),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final option in options)
              ChoiceChip(
                label: Text(option.$2),
                selected: option.$1 == selected,
                onSelected: (_) => onChanged({...value, key: option.$1}),
              ),
          ],
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (separateMessage)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: TextFormField(
              initialValue: value['message'] as String? ?? '',
              minLines: 2,
              maxLines: 5,
              maxLength: 4000,
              decoration: InputDecoration(
                labelText: es ? 'Describe el problema' : 'Describe the issue',
                helperText: es
                    ? 'Puedes usar el dictado de tu teclado.'
                    : 'You can use your keyboard’s dictation.',
              ),
              onChanged: (text) => onChanged({...value, 'message': text}),
            ),
          ),
        choices(es ? 'Urgencia' : 'Urgency', 'urgency', urgency, [
          ('normal', es ? 'Normal' : 'Normal'),
          ('urgent', es ? 'Urgente' : 'Urgent'),
        ]),
        choices(
          es
              ? '¿Parece seguro operar?'
              : 'Does the equipment appear safe to operate?',
          'safe_to_operate',
          safe,
          [
            ('safe', es ? 'Parece seguro' : 'Appears safe'),
            ('unsafe', es ? 'No es seguro' : 'Unsafe'),
            ('unknown', es ? 'No estoy seguro' : 'Unsure'),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            es
                ? 'El responsable revisará tu evaluación y la evidencia.'
                : 'Your manager will review this assessment and evidence.',
          ),
        ),
      ],
    );
  }
}
