import 'package:flutter/material.dart';
import 'package:vortice_app/core/app_dropdown_field.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/core/unsaved_form_guard.dart';

import 'package:vortice_app/features/checklists/checklist_procedure_source.dart';
import 'checklist_source_picker.dart';

class ChecklistStepScreen extends StatefulWidget {
  const ChecklistStepScreen({
    super.key,
    this.initial = const {},
    this.clientId,
  });
  final Map<String, dynamic> initial;
  final String? clientId;
  @override
  State<ChecklistStepScreen> createState() => _ChecklistStepScreenState();
}

class _ChecklistStepScreenState extends State<ChecklistStepScreen> {
  final _form = GlobalKey<FormState>();
  final _text = <String, TextEditingController>{};
  late String _type, _equipmentState;
  ChecklistProcedureSource? _source;
  late bool _photo, _critical, _na;
  bool _dirty = false;
  @override
  void initState() {
    super.initState();
    final definition = widget.initial['definition'] as Map? ?? {};
    for (final name in ['description_en', 'description_es', 'category']) {
      _text[name] = TextEditingController(
        text: widget.initial[name] as String? ?? '',
      );
    }
    for (final name in ['guidance', 'unit', 'min', 'max']) {
      _text[name] = TextEditingController(
        text: definition[name]?.toString() ?? '',
      );
    }
    _type = definition['input_type'] as String? ?? 'check';
    _equipmentState = definition['equipment_state'] as String? ?? '';
    _source = ChecklistProcedureSource.fromDefinition(definition);
    _text['source_section'] = TextEditingController(
      text: _source?.section ?? '',
    );
    _photo = widget.initial['requires_photo'] == true;
    _critical = definition['critical'] == true;
    _na = definition['allow_na'] != false;
  }

  @override
  void dispose() {
    for (final controller in _text.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(context, <String, dynamic>{
      ...widget.initial,
      'description_en': _text['description_en']!.text.trim(),
      'description_es': _text['description_es']!.text.trim(),
      'category': _text['category']!.text.trim(),
      'requires_photo': _photo,
      'definition': {
        ...?widget.initial['definition'] as Map<String, dynamic>?,
        'input_type': _type,
        'equipment_state': _equipmentState,
        'procedure_source': _source == null
            ? null
            : ChecklistProcedureSource(
                _source!.document,
                _source!.page,
                _text['source_section']!.text.trim(),
              ).toJson(),
        'source_document_id': null,
        'source_page': null,
        'critical': _critical,
        'allow_na': _na,
        'guidance': _text['guidance']!.text.trim(),
        'min': null,
        'max': null,
        if (_type == 'number') ...{
          'unit': _text['unit']!.text.trim(),
          'min': double.tryParse(_text['min']!.text.replaceAll(',', '.')),
          'max': double.tryParse(_text['max']!.text.replaceAll(',', '.')),
        },
      },
    });
  }

  @override
  Widget build(BuildContext context) {
    final es = isSpanish(context);
    Widget field(
      String name,
      String en,
      String spanish, {
      int max = 2000,
      bool required = false,
      bool numeric = false,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: _text[name],
        maxLength: max,
        minLines: 1,
        maxLines: numeric ? 1 : 4,
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(decimal: true, signed: true)
            : TextInputType.multiline,
        decoration: InputDecoration(labelText: es ? spanish : en),
        validator: (value) {
          if (required && (value?.trim().length ?? 0) < 3) {
            return es ? 'Describe el paso' : 'Describe this step';
          }
          if (numeric && value!.trim().isNotEmpty) {
            final number = double.tryParse(value.replaceAll(',', '.'));
            if (number == null || !number.isFinite) {
              return es ? 'Ingresa un número válido' : 'Enter a valid number';
            }
            final min = double.tryParse(
              _text['min']!.text.replaceAll(',', '.'),
            );
            if (name == 'max' && min != null && number < min) {
              return es
                  ? 'El máximo debe ser mayor o igual al mínimo'
                  : 'Maximum must be at least the minimum';
            }
          }
          return null;
        },
      ),
    );
    return UnsavedFormGuard(
      isDirty: () => _dirty,
      controllers: _text.values.toList(),
      fallbackRoute: '/checklist-library',
      child: Scaffold(
        appBar: AppBar(title: Text(es ? 'Editar paso' : 'Edit checklist step')),
        body: Form(
          key: _form,
          onChanged: () => _dirty = true,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              field(
                'category',
                'Section (optional)',
                'Sección (opcional)',
                max: 100,
              ),
              field(
                'description_en',
                'Instruction',
                'Instrucción',
                required: true,
              ),
              field(
                'description_es',
                'Spanish translation (optional)',
                'Traducción al español (opcional)',
              ),
              AppDropdownField<String>(
                initialValue: _equipmentState,
                decoration: InputDecoration(
                  labelText: es ? 'Estado del equipo' : 'Equipment state',
                ),
                items: [
                  for (final entry in checklistEquipmentStates.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(es ? entry.value.$2 : entry.value.$1),
                    ),
                ],
                onChanged: (value) => setState(() {
                  _equipmentState = value!;
                  _dirty = true;
                }),
              ),
              const SizedBox(height: 16),
              if (widget.clientId != null)
                TextButton.icon(
                  icon: const Icon(Icons.menu_book_outlined),
                  label: Text(
                    _source == null
                        ? (es
                              ? 'Vincular procedimiento'
                              : 'Link procedure page')
                        : (es
                              ? 'Cambiar procedimiento'
                              : 'Change procedure page'),
                  ),
                  onPressed: () async {
                    final source =
                        await Navigator.push<ChecklistProcedureSource>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChecklistSourcePicker(
                              clientId: widget.clientId!,
                            ),
                          ),
                        );
                    if (source != null && mounted) {
                      setState(() {
                        _source = source;
                        _text['source_section']!.clear();
                        _dirty = true;
                      });
                    }
                  },
                ),
              if (_source != null) ...[
                ChecklistProcedureLink(
                  item: {
                    'definition': {'procedure_source': _source!.toJson()},
                  },
                ),
                field(
                  'source_section',
                  'Manual section or printed page (optional)',
                  'Secci?n o p?gina impresa (opcional)',
                  max: 200,
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _source = null;
                    _dirty = true;
                  }),
                  child: Text(es ? 'Quitar v?nculo' : 'Remove procedure link'),
                ),
              ],
              field(
                'guidance',
                'How to check (optional)',
                'Cómo revisar (opcional)',
              ),
              AppDropdownField<String>(
                initialValue: _type,
                decoration: InputDecoration(
                  labelText: es ? 'Tipo de respuesta' : 'Response type',
                ),
                items: [
                  for (final choice in [
                    ('check', es ? 'Correcto / Falla' : 'Pass / Fail'),
                    ('number', es ? 'Lectura numérica' : 'Numeric reading'),
                    ('text', es ? 'Respuesta escrita' : 'Written response'),
                  ])
                    DropdownMenuItem(value: choice.$1, child: Text(choice.$2)),
                ],
                onChanged: (value) => setState(() {
                  _type = value!;
                  _dirty = true;
                }),
              ),
              const SizedBox(height: 16),
              if (_type == 'number') ...[
                field('unit', 'Units', 'Unidades', max: 40),
                field(
                  'min',
                  'Minimum (optional)',
                  'Mínimo (opcional)',
                  numeric: true,
                  max: 40,
                ),
                field(
                  'max',
                  'Maximum (optional)',
                  'Máximo (opcional)',
                  numeric: true,
                  max: 40,
                ),
              ],
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(es ? 'Foto requerida' : 'Require a photo'),
                value: _photo,
                onChanged: (value) => setState(() {
                  _photo = value;
                  _dirty = true;
                }),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(es ? 'Paso crítico' : 'Critical step'),
                subtitle: Text(
                  es
                      ? 'Una falla requiere revisión prioritaria.'
                      : 'A failure needs priority review.',
                ),
                value: _critical,
                onChanged: (value) => setState(() {
                  _critical = value;
                  _dirty = true;
                }),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(es ? 'Permitir No aplica' : 'Allow Not applicable'),
                value: _na,
                onChanged: (value) => setState(() {
                  _na = value;
                  _dirty = true;
                }),
              ),
              const SizedBox(height: 16),
              SafeArea(
                top: false,
                child: FilledButton(
                  onPressed: _save,
                  child: Text(es ? 'Guardar paso' : 'Save step'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
