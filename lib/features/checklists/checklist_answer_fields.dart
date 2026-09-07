import 'package:flutter/material.dart';
import 'package:vortice_app/core/user_feedback.dart';

String checklistInputType(Map<String, dynamic> definition) =>
    definition['input_type'] as String? ?? 'check';

String checklistRecordedValue(Map<String, dynamic> definition, String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return '';
  final unit = checklistInputType(definition) == 'number'
      ? definition['unit'] as String?
      : null;
  return unit == null || unit.trim().isEmpty ? text : '$text ${unit.trim()}';
}

String? checklistValueResult(
  Map<String, dynamic> definition,
  String value, {
  String failure = 'action',
}) {
  if (value.trim().isEmpty) return null;
  if (checklistInputType(definition) != 'number') return 'pass';
  final number = double.tryParse(value.trim().replaceAll(',', '.'));
  if (number == null || !number.isFinite) return null;
  final min = (definition['min'] as num?)?.toDouble();
  final max = (definition['max'] as num?)?.toDouble();
  return (min != null && number < min) || (max != null && number > max)
      ? failure
      : 'pass';
}

bool checklistAnswerValid(
  Map<String, dynamic> definition,
  String? result,
  String value,
) {
  if (!const {
    'pass',
    'fail',
    'monitor',
    'alert',
    'action',
    'na',
    'n/a',
  }.contains(result)) {
    return false;
  }
  if (result == 'na' || result == 'n/a') return definition['allow_na'] != false;
  if (checklistInputType(definition) == 'check') return true;
  final expected = checklistValueResult(definition, value);
  return expected != null &&
      (expected != 'action' || result == 'action' || result == 'fail');
}

/// The same answer controls are used in the builder preview and live work.
class ChecklistAnswerFields extends StatelessWidget {
  const ChecklistAnswerFields({
    super.key,
    required this.item,
    required this.result,
    required this.value,
    required this.onResult,
    required this.onValue,
    this.enabled = true,
    this.failure = 'action',
    this.na = 'n/a',
  });
  final Map<String, dynamic> item;
  final String? result;
  final String value, failure, na;
  final bool enabled;
  final ValueChanged<String?> onResult;
  final ValueChanged<String> onValue;

  @override
  Widget build(BuildContext context) {
    final es = isSpanish(context);
    final definition = Map<String, dynamic>.from(
      item['definition'] as Map? ?? {},
    );
    final type = checklistInputType(definition);
    final flagged = ['action', 'fail', 'monitor', 'alert'].contains(result);
    final translation = item['description_es'] as String?;
    final title = es && translation != null && translation.trim().isNotEmpty
        ? translation
        : item['description_en'] as String? ?? '';
    final guidance = definition['guidance'] as String? ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if ((item['category'] as String? ?? '').isNotEmpty)
          Text(
            item['category'] as String,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        if (definition['critical'] == true)
          Text(
            es
                ? 'Paso crítico · una falla requiere revisión'
                : 'Critical step · failure requires review',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (guidance.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(guidance),
          ),
        const SizedBox(height: 12),
        if (type == 'check')
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final choice in [
                ('pass', es ? 'Correcto' : 'Pass'),
                (failure, es ? 'Falla' : 'Fail'),
                if (definition['allow_na'] != false)
                  (na, es ? 'No aplica' : 'Not applicable'),
              ])
                ChoiceChip(
                  label: Text(choice.$2),
                  selected: result == choice.$1,
                  onSelected: enabled ? (_) => onResult(choice.$1) : null,
                ),
            ],
          )
        else ...[
          TextFormField(
            initialValue: value,
            enabled: enabled && result != na,
            minLines: 1,
            maxLines: type == 'number' ? 1 : 4,
            maxLength: type == 'number' ? 40 : 4000,
            keyboardType: type == 'number'
                ? const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  )
                : TextInputType.multiline,
            decoration: InputDecoration(
              labelText: type == 'number'
                  ? (es ? 'Lectura' : 'Reading')
                  : (es ? 'Respuesta' : 'Response'),
              suffixText: definition['unit'] as String?,
              helperText:
                  type == 'number' &&
                      (definition['min'] != null || definition['max'] != null)
                  ? '${es ? 'Rango' : 'Range'}: ${definition['min'] ?? '—'} – ${definition['max'] ?? '—'}'
                  : null,
            ),
            onChanged: (input) {
              final normalized = type == 'number'
                  ? input.replaceAll(',', '.')
                  : input;
              onValue(normalized);
              onResult(
                checklistValueResult(definition, normalized, failure: failure),
              );
            },
          ),
          if (flagged)
            Text(
              es
                  ? 'Fuera de rango · requiere revisión'
                  : 'Outside range · review required',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (definition['allow_na'] != false)
            FilterChip(
              label: Text(es ? 'No aplica' : 'Not applicable'),
              selected: result == na,
              onSelected: enabled
                  ? (selected) => onResult(
                      selected
                          ? na
                          : checklistValueResult(
                              definition,
                              value,
                              failure: failure,
                            ),
                    )
                  : null,
            ),
        ],
        if (type == 'check' && flagged) ...[
          const SizedBox(height: 12),
          TextFormField(
            initialValue: value,
            enabled: enabled,
            minLines: 2,
            maxLines: 4,
            maxLength: 4000,
            decoration: InputDecoration(
              labelText: es ? 'Describe el hallazgo' : 'Describe the finding',
            ),
            onChanged: onValue,
          ),
        ],
      ],
    );
  }
}

class ChecklistEvidenceActions extends StatelessWidget {
  const ChecklistEvidenceActions({
    super.key,
    required this.requiredPhoto,
    required this.onGallery,
    required this.onCamera,
  });
  final bool requiredPhoto;
  final VoidCallback? onGallery, onCamera;
  @override
  Widget build(BuildContext context) {
    final es = isSpanish(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (requiredPhoto) Text(es ? 'Foto requerida' : 'Photo required'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onGallery,
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(es ? 'Elegir foto' : 'Choose photo'),
              ),
              OutlinedButton.icon(
                onPressed: onCamera,
                icon: const Icon(Icons.camera_alt_outlined),
                label: Text(es ? 'Cámara' : 'Camera'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
