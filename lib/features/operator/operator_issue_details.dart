import 'package:flutter/material.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/core/localized_text.dart';

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
                labelText: localizedText(
                  context,
                  'Describe the issue',
                  'Describe el problema',
                  'Décrivez le problème',
                ),
                helperText: localizedText(
                  context,
                  'You can use your keyboard’s dictation.',
                  'Puedes usar el dictado de tu teclado.',
                  'Vous pouvez utiliser la dictée de votre clavier.',
                ),
              ),
              onChanged: (text) => onChanged({...value, 'message': text}),
            ),
          ),
        choices(
          localizedText(context, 'Urgency', 'Urgencia', 'Urgence'),
          'urgency',
          urgency,
          [
            ('normal', es ? 'Normal' : 'Normal'),
            ('urgent', localizedText(context, 'Urgent', 'Urgente', 'Urgente')),
          ],
        ),
        choices(
          localizedText(
            context,
            'Does the equipment appear safe to operate?',
            '¿Parece seguro operar?',
            'L’équipement semble-t-il sécuritaire à utiliser ?',
          ),
          'safe_to_operate',
          safe,
          [
            (
              'safe',
              localizedText(
                context,
                'Appears safe',
                'Parece seguro',
                'Semble sécuritaire',
              ),
            ),
            (
              'unsafe',
              localizedText(
                context,
                'Unsafe',
                'No es seguro',
                'Non sécuritaire',
              ),
            ),
            (
              'unknown',
              localizedText(context, 'Unsure', 'No estoy seguro', 'Incertain'),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            localizedText(
              context,
              'Your manager will review this assessment and evidence.',
              'El responsable revisará tu evaluación y la evidencia.',
              'La personne responsable examinera votre évaluation et les preuves jointes.',
            ),
          ),
        ),
      ],
    );
  }
}
