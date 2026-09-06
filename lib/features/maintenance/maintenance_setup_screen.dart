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
  });
  final String kind;
  final String? assetId;
  final Map<String, dynamic> initial, catalog;
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
    _pending ??= MaintenanceWrite({
      ..._values,
      for (final e in _text.entries) e.key: e.value.text.trim(),
    });
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
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
        onChanged: (_) => _dirty = true,
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
                (key == 'engine_id' && widget.initial['engine_id'] != null)
            ? null
            : (v) => setState(() {
                _values[key] = v;
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
                          ? 'Usa Registrar traslado en Custodia e inspecciones para cambiar la ubicación.'
                          : 'Use Record transfer in Custody & inspections to change the location.',
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
                  readOnly: widget.initial['last_service_hours'] != null,
                ),
                select(
                  'checklist_template_id',
                  'Checklist (optional)',
                  'Lista (opcional)',
                  maintenanceRows(widget.catalog['templates']),
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
              FilledButton(
                onPressed: _busy ? null : _save,
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
