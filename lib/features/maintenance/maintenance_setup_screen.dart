import 'package:vortice_app/core/app_dropdown_field.dart';
import 'package:vortice_app/features/assurance/assurance_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:vortice_app/core/unsaved_form_guard.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'maintenance_models.dart';
import 'maintenance_repository.dart';
import 'maintenance_refresh.dart';

class MaintenanceSetupScreen extends ConsumerStatefulWidget {
  const MaintenanceSetupScreen({
    super.key,
    required this.kind,
    this.assetId,
    this.initial = const {},
    this.catalog = const {},
    this.reviewedSave,
    this.reviewContext,
  });
  final String kind;
  final String? assetId;
  final Map<String, dynamic> initial, catalog;
  final Widget? reviewContext;
  final Future<void> Function(String operation, Map<String, dynamic> data)?
  reviewedSave;
  @override
  ConsumerState<MaintenanceSetupScreen> createState() =>
      _MaintenanceSetupScreenState();
}

class _MaintenanceSetupScreenState
    extends ConsumerState<MaintenanceSetupScreen> {
  final _form = GlobalKey<FormState>();
  final Map<String, TextEditingController> _text = {};
  late final String _id;
  late Map<String, dynamic> _values;
  MaintenanceWrite? _pending;
  bool _busy = false, _dirty = false;
  bool _reviewedReadings = false;
  Object? _error;
  @override
  void initState() {
    super.initState();
    _id = widget.initial['id'] as String? ?? const Uuid().v4();
    _values = {
      'kind': 'engine',
      'is_active': true,
      ...widget.initial,
      'asset_id': widget.assetId,
    };
    for (final name in [
      'name',
      'make',
      'model',
      'serial_number',
      'location',
      'label',
      'current_hours',
      'interval_label',
      'interval_hours',
      'last_service_hours',
    ]) {
      _text[name] = TextEditingController(
        text:
            widget.initial[name]?.toString() ??
            (['current_hours', 'last_service_hours'].contains(name) ? '0' : ''),
      );
    }
  }

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (widget.reviewedSave != null && !_reviewedReadings) return;
    _pending ??= MaintenanceWrite({
      ..._values,
      for (final e in _text.entries) e.key: e.value.text.trim(),
      if (widget.reviewedSave != null) ...{
        'source_reviewed': true,
        'review_current_hours': maintenanceRows(widget.catalog['components'])
            .where((e) => e['id'] == _values['engine_id'])
            .firstOrNull?['current_hours'],
      },
    });
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.reviewedSave != null) {
        await widget.reviewedSave!(_pending!.id, _pending!.data);
      } else {
        await ref
            .read(maintenanceRepositoryProvider)
            .setup(
              _pending!.id,
              widget.kind,
              _id,
              (widget.initial[widget.kind == 'plan'
                              ? 'revision'
                              : 'maintenance_revision']
                          as num?)
                      ?.toInt() ??
                  0,
              _pending!.data,
            );
      }
      if (mounted) {
        refreshMaintenance(ref, assetsChanged: true);
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          if (maintenanceWriteWasRejected(error)) _pending = null;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final es = isSpanish(context), frozen = _busy || _pending != null;
    final reviewBaseline = num.tryParse(_text['last_service_hours']!.text);
    final reviewInterval = num.tryParse(_text['interval_hours']!.text);
    final reviewCurrent =
        maintenanceRows(widget.catalog['components'])
                .where((e) => e['id'] == _values['engine_id'])
                .firstOrNull?['current_hours']
            as num?;
    final previewDue =
        reviewBaseline != null &&
            reviewBaseline.isFinite &&
            reviewBaseline >= 0 &&
            reviewInterval != null &&
            reviewInterval.isFinite &&
            reviewInterval > 0 &&
            reviewInterval == reviewInterval.roundToDouble() &&
            reviewCurrent != null &&
            reviewBaseline <= reviewCurrent
        ? reviewBaseline + reviewInterval
        : null;
    final workspace = ref.watch(maintenanceWorkspaceProvider);
    final custody = widget.kind == 'asset' && widget.initial['id'] != null
        ? ref.watch(assuranceContextProvider(widget.initial['id'] as String))
        : null;
    final title = switch (widget.kind) {
      'asset' => es ? 'Equipo' : 'Asset',
      'component' => es ? 'Componente' : 'Component',
      _ => es ? 'Plan de mantenimiento' : 'Maintenance plan',
    };
    Widget field(
      String key,
      String en,
      String spanish, {
      bool required = false,
      bool number = false,
      bool readOnly = false,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: _text[key],
        enabled: !frozen && !readOnly,
        keyboardType: number
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        decoration: InputDecoration(labelText: es ? spanish : en),
        onChanged: (_) {
          _dirty = true;
          if (widget.reviewedSave != null) {
            setState(() => _reviewedReadings = false);
          }
        },
        validator: (v) => required && (v?.trim().isEmpty ?? true)
            ? (es ? 'Campo requerido' : 'Required')
            : number &&
                  (double.tryParse(v ?? '')?.isFinite != true ||
                      double.parse(v!) < 0)
            ? (es ? 'Ingresa un número válido' : 'Enter a valid number')
            : null,
      ),
    );
    Widget select(
      String key,
      String en,
      String spanish,
      List<Map<String, dynamic>> rows,
      String label, {
      bool required = true,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: AppDropdownField<String>(
        initialValue: _values[key] as String?,
        isExpanded: true,
        decoration: InputDecoration(labelText: es ? spanish : en),
        items: rows
            .map(
              (r) => DropdownMenuItem(
                value: r['id'] as String,
                child: Text(r[label]?.toString() ?? ''),
              ),
            )
            .toList(),
        onChanged:
            frozen ||
                (key == 'engine_id' &&
                    widget.initial['id'] != null &&
                    widget.initial['engine_id'] != null)
            ? null
            : (v) => setState(() {
                _values[key] = v;
                _reviewedReadings = false;
                if (key == 'engine_id') {
                  final selected = maintenanceRows(widget.catalog['templates'])
                      .where((t) => t['id'] == _values['checklist_template_id'])
                      .firstOrNull;
                  if (selected?['scope_engine_id'] != null &&
                      selected!['scope_engine_id'] != v) {
                    _values['checklist_template_id'] = null;
                  }
                }
                _dirty = true;
              }),
        validator: (v) => required && v == null
            ? (es ? 'Selecciona una opción' : 'Select an option')
            : null,
      ),
    );
    return UnsavedFormGuard(
      isDirty: () => _dirty || _pending != null,
      controllers: _text.values.toList(),
      busy: _busy,
      fallbackRoute: '/maintenance',
      child: Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (widget.reviewContext != null) widget.reviewContext!,
              if (widget.kind == 'asset') ...[
                field(
                  'name',
                  'Asset name',
                  'Nombre del equipo',
                  required: true,
                ),
                if (widget.initial.isEmpty)
                  workspace.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => Text(maintenanceError(e, es)),
                    data: (w) => Column(
                      children: [
                        select(
                          'asset_type_id',
                          'Asset type',
                          'Tipo de equipo',
                          maintenanceRows(w['asset_types']),
                          'name',
                        ),
                        select(
                          'client_id',
                          'Company owner',
                          'Propietario de la empresa',
                          maintenanceRows(w['clients']),
                          'name',
                        ),
                      ],
                    ),
                  ),
                field('make', 'Make', 'Marca'),
                field('model', 'Model', 'Modelo'),
                field('serial_number', 'Serial number', 'Número de serie'),
                field(
                  'location',
                  'Location',
                  'Ubicación',
                  readOnly:
                      custody != null &&
                      (!custody.hasValue ||
                          custody.valueOrNull?['custody'] != null),
                ),
                if (custody?.valueOrNull?['custody'] != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      es
                          ? 'Usa Actualizar ubicación y responsable en Custodia e inspecciones para cambiar la ubicación.'
                          : 'Use Update location & responsibility in Custody & inspections to change the location.',
                    ),
                  ),
              ] else if (widget.kind == 'component') ...[
                field('label', 'Component name', 'Nombre', required: true),
                if (widget.initial.isEmpty) ...[
                  select('kind', 'Component type', 'Tipo de componente', [
                    {'id': 'engine', 'name': es ? 'Motor' : 'Engine'},
                    {'id': 'generator', 'name': es ? 'Generador' : 'Generator'},
                    {'id': 'other', 'name': es ? 'Otro' : 'Other'},
                  ], 'name'),
                  field(
                    'current_hours',
                    'Initial meter hours',
                    'Horas iniciales',
                    number: true,
                  ),
                ],
              ] else ...[
                field(
                  'interval_label',
                  'Plan name',
                  'Nombre del plan',
                  required: true,
                ),
                select(
                  'engine_id',
                  'Component',
                  'Componente',
                  maintenanceRows(widget.catalog['components']),
                  'label',
                ),
                field(
                  'interval_hours',
                  'Service every (hours)',
                  'Servicio cada (horas)',
                  required: true,
                  number: true,
                ),
                field(
                  'last_service_hours',
                  'Last service meter',
                  'Horas del último servicio',
                  number: true,
                  readOnly:
                      widget.initial['id'] != null &&
                      (widget.initial['last_service_hours']
                              ?.toString()
                              .isNotEmpty ??
                          false),
                ),
                select(
                  'checklist_template_id',
                  'Checklist (optional)',
                  'Lista (opcional)',
                  maintenanceRows(widget.catalog['templates'])
                      .where(
                        (t) =>
                            t['scope_engine_id'] == null ||
                            t['scope_engine_id'] == _values['engine_id'],
                      )
                      .toList(),
                  'name',
                  required: false,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(es ? 'Plan activo' : 'Active plan'),
                  value: _values['is_active'] == true,
                  onChanged: frozen
                      ? null
                      : (v) => setState(() {
                          _values['is_active'] = v;
                          _dirty = true;
                        }),
                ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(maintenanceError(_error!, es)),
                ),
              if (widget.reviewedSave != null) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          es
                              ? 'Vista previa de tus cambios'
                              : 'Preview your changes',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          previewDue == null
                              ? (es
                                    ? 'Confirma la base del último servicio y un intervalo válido para calcular el próximo servicio.'
                                    : 'Confirm the last-service baseline and a valid interval to calculate the next service.')
                              : '${es ? 'Próximo servicio' : 'Next service'}: $previewDue h',
                        ),
                        if (previewDue != null && reviewCurrent != null)
                          Text(
                            '${previewDue - reviewCurrent} h ${es ? 'respecto al medidor actual' : 'relative to the current meter'}',
                          ),
                      ],
                    ),
                  ),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _reviewedReadings,
                  onChanged: frozen
                      ? null
                      : (v) => setState(() => _reviewedReadings = v ?? false),
                  title: Text(
                    es
                        ? 'Verifiqué el manual, las horas actuales y el historial de este servicio.'
                        : 'I verified the manual, current hours and this task’s service history.',
                  ),
                ),
              ],
              FilledButton(
                onPressed:
                    _busy || (widget.reviewedSave != null && !_reviewedReadings)
                    ? null
                    : _save,
                child: Text(
                  _busy
                      ? (es ? 'Guardando…' : 'Saving…')
                      : _pending != null
                      ? (es ? 'Reintentar guardado' : 'Retry save')
                      : (es ? 'Guardar' : 'Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
