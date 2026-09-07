import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:vortice_app/core/app_dropdown_field.dart';
import 'package:vortice_app/core/unsaved_form_guard.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/features/checklists/checklist_provider.dart';
import 'package:vortice_app/features/maintenance/maintenance_repository.dart';
import 'checklist_builder_repository.dart';
import 'checklist_preview_screen.dart';
import 'checklist_step_screen.dart';

class ChecklistEditorScreen extends ConsumerStatefulWidget {
  const ChecklistEditorScreen({
    super.key,
    required this.catalog,
    this.procedure,
    this.initial = const {},
  });
  final Map<String, dynamic> catalog, initial;
  final Map<String, dynamic>? procedure;
  @override
  ConsumerState<ChecklistEditorScreen> createState() =>
      _ChecklistEditorScreenState();
}

class _ChecklistEditorScreenState extends ConsumerState<ChecklistEditorScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(), _description = TextEditingController();
  late final String _id;
  late Map<String, dynamic> _data;
  late List<Map<String, dynamic>> _steps;
  late String _kind;
  String? _assetType, _asset, _engine;
  int _revision = 0;
  int _publishedRevision = 0;
  bool _dirty = false, _busy = false, _stale = false, _published = false;
  MaintenanceWrite? _pending;
  String? _pendingAction, _message;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _id = widget.procedure?['id'] as String? ?? const Uuid().v4();
    _load(widget.procedure ?? {'draft': widget.initial});
  }

  void _load(Map<String, dynamic> procedure) {
    _data = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(procedure['draft'] ?? {})) as Map,
    );
    _name.text = _data['name'] as String? ?? '';
    _description.text = _data['description'] as String? ?? '';
    _steps = checklistRows(_data['items']);
    _kind =
        _data['checklist_type'] as String? ??
        (widget.catalog['can_pm'] == true ? 'pm' : 'operator_daily');
    _assetType = _data['asset_type_id'] as String?;
    _asset = _data['scope_asset_id'] as String?;
    _engine = _data['scope_engine_id'] as String?;
    _revision = (procedure['revision'] as num?)?.toInt() ?? 0;
    _published = procedure['published_template_id'] != null;
    _publishedRevision =
        (procedure['published_revision'] as num?)?.toInt() ?? 0;
    _dirty = _revision == 0;
  }

  Map<String, dynamic> _draft() => {
    ..._data,
    'name': _name.text.trim(),
    'description': _description.text.trim(),
    'checklist_type': _kind,
    'asset_type_id': _assetType,
    'scope_asset_id': _asset,
    'scope_engine_id': _engine,
    'items': _steps,
  };
  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _write(String action) async {
    if (action == 'draft' && !_form.currentState!.validate()) return;
    _pending ??= MaintenanceWrite(action == 'draft' ? _draft() : {});
    _pendingAction ??= action;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await ref
          .read(checklistBuilderRepositoryProvider)
          .save(_pending!.id, _id, _revision, _pendingAction!, _pending!.data);
      if (!mounted) return;
      _revision++;
      _dirty = false;
      if (_pendingAction == 'publish') {
        _published = true;
        _publishedRevision = _revision;
      }
      _message = _pendingAction == 'publish' ? 'published' : 'saved';
      _pending = null;
      _pendingAction = null;
      ref.invalidate(checklistLibraryProvider);
      ref.invalidate(checklistTemplatesProvider);
    } catch (error) {
      if (mounted) {
        _error = error;
        _stale = error is PostgrestException && error.code == '40001';
        if (maintenanceWriteWasRejected(error)) {
          _pending = null;
          _pendingAction = null;
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reload() async {
    setState(() => _busy = true);
    try {
      final library = await ref
          .read(checklistBuilderRepositoryProvider)
          .library();
      final row = checklistRows(
        library['procedures'],
      ).where((p) => p['id'] == _id).firstOrNull;
      if (!mounted) return;
      if (row == null || row['archived'] == true) {
        Navigator.pop(context);
        return;
      }
      setState(() {
        _load(row);
        _stale = false;
        _pending = null;
        _pendingAction = null;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _step([int? index]) async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => ChecklistStepScreen(
          initial: index == null ? const {} : _steps[index],
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (index == null) {
        _steps.add(result);
      } else {
        _steps[index] = result;
      }
      _dirty = true;
      _message = null;
    });
  }

  void _move(int index, int delta) => setState(() {
    final step = _steps.removeAt(index);
    _steps.insert(index + delta, step);
    _dirty = true;
  });
  @override
  Widget build(BuildContext context) {
    final es = isSpanish(context), frozen = _busy || _pending != null || _stale;
    final assets = checklistRows(widget.catalog['assets'])
        .where((a) => _assetType == null || a['asset_type_id'] == _assetType)
        .toList();
    final selectedAsset = assets.where((a) => a['id'] == _asset).firstOrNull;
    final components = checklistRows(selectedAsset?['components']);
    Widget select(
      String key,
      String label,
      String? value,
      List<Map<String, dynamic>> rows,
      ValueChanged<String?> onChanged,
    ) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: AppDropdownField<String>(
        key: ValueKey('$key:$value'),
        initialValue: value ?? '',
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          DropdownMenuItem(
            value: '',
            child: Text(
              es ? 'Todos los compatibles' : 'All matching equipment',
            ),
          ),
          for (final row in rows)
            DropdownMenuItem(
              value: row['id'] as String,
              child: Text(row['name'] as String),
            ),
        ],
        onChanged: frozen
            ? null
            : (v) => setState(() {
                onChanged(v == '' ? null : v);
                _dirty = true;
              }),
      ),
    );
    return UnsavedFormGuard(
      isDirty: () => _dirty,
      controllers: [_name, _description],
      busy: _busy,
      fallbackRoute: '/checklist-library',
      child: Scaffold(
        appBar: AppBar(title: Text(es ? 'Crear lista' : 'Checklist builder')),
        body: Form(
          key: _form,
          onChanged: () {
            if (!_dirty) setState(() => _dirty = true);
          },
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                widget.catalog['client_id'] == null
                    ? (es
                          ? 'Biblioteca del propietario · plantillas compartidas'
                          : 'Owner library · shared starter templates')
                    : (es
                          ? 'Biblioteca privada de tu empresa'
                          : 'Your company’s private library'),
              ),
              if (_published)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    es
                        ? 'Los cambios crean una nueva versión para trabajos futuros.'
                        : 'Changes create a new version for future work.',
                  ),
                ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                enabled: !frozen,
                maxLength: 160,
                decoration: InputDecoration(
                  labelText: es ? 'Nombre de la lista' : 'Checklist name',
                ),
                validator: (v) => (v?.trim().length ?? 0) < 3
                    ? (es
                          ? 'Pon un nombre descriptivo'
                          : 'Enter a descriptive name')
                    : null,
              ),
              const SizedBox(height: 16),
              AppDropdownField<String>(
                initialValue: _kind,
                isExpanded: true,
                decoration: InputDecoration(labelText: es ? 'Uso' : 'Purpose'),
                items: [
                  if (widget.catalog['can_pm'] == true || _kind == 'pm')
                    DropdownMenuItem(
                      value: 'pm',
                      child: Text(
                        es
                            ? 'Mantenimiento preventivo'
                            : 'Preventive maintenance',
                      ),
                    ),
                  if (widget.catalog['can_preop'] == true ||
                      _kind == 'operator_daily')
                    DropdownMenuItem(
                      value: 'operator_daily',
                      child: Text(
                        es ? 'Revisión antes de operar' : 'Pre-operation check',
                      ),
                    ),
                ],
                onChanged: frozen || _published
                    ? null
                    : (v) => setState(() {
                        _kind = v!;
                        _engine = null;
                        _dirty = true;
                      }),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _description,
                enabled: !frozen,
                minLines: 2,
                maxLines: 5,
                maxLength: 4000,
                decoration: InputDecoration(
                  labelText: es
                      ? 'Instrucciones generales'
                      : 'General instructions',
                ),
              ),
              const SizedBox(height: 16),
              select(
                'type',
                es ? 'Tipo de equipo' : 'Equipment type',
                _assetType,
                checklistRows(widget.catalog['asset_types']),
                (v) {
                  _assetType = v;
                  _asset = null;
                  _engine = null;
                },
              ),
              select(
                'asset',
                es
                    ? 'Equipo específico (opcional)'
                    : 'Specific equipment (optional)',
                _asset,
                assets,
                (v) {
                  _asset = v;
                  _engine = null;
                },
              ),
              if (_kind == 'pm' && _asset != null)
                select(
                  'engine',
                  es ? 'Componente (opcional)' : 'Component (optional)',
                  _engine,
                  components,
                  (v) => _engine = v,
                ),
              Text(
                '${es ? 'Pasos' : 'Steps'} (${_steps.length}/100)',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (_steps.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    es
                        ? 'Añade los pasos que debe completar tu equipo.'
                        : 'Add the steps your team needs to complete.',
                  ),
                ),
              for (var i = 0; i < _steps.length; i++)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${i + 1}. ${_steps[i]['description_en']}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if ((_steps[i]['category'] as String? ?? '').isNotEmpty)
                          Text(_steps[i]['category'] as String),
                        Wrap(
                          spacing: 4,
                          children: [
                            TextButton.icon(
                              onPressed: frozen ? null : () => _step(i),
                              icon: const Icon(Icons.edit_outlined),
                              label: Text(es ? 'Editar' : 'Edit'),
                            ),
                            IconButton(
                              tooltip: es ? 'Subir paso' : 'Move step up',
                              onPressed: frozen || i == 0
                                  ? null
                                  : () => _move(i, -1),
                              icon: const Icon(Icons.arrow_upward),
                            ),
                            IconButton(
                              tooltip: es ? 'Bajar paso' : 'Move step down',
                              onPressed: frozen || i == _steps.length - 1
                                  ? null
                                  : () => _move(i, 1),
                              icon: const Icon(Icons.arrow_downward),
                            ),
                            IconButton(
                              tooltip: es ? 'Quitar paso' : 'Remove step',
                              onPressed: frozen
                                  ? null
                                  : () => setState(() {
                                      _steps.removeAt(i);
                                      _dirty = true;
                                    }),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: frozen || _steps.length >= 100
                    ? null
                    : () => _step(),
                icon: const Icon(Icons.add),
                label: Text(es ? 'Añadir paso' : 'Add step'),
              ),
              OutlinedButton.icon(
                onPressed: _steps.isEmpty || frozen
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              ChecklistPreviewScreen(draft: _draft()),
                        ),
                      ),
                icon: const Icon(Icons.visibility_outlined),
                label: Text(es ? 'Vista previa' : 'Preview checklist'),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(maintenanceError(_error!, es)),
                ),
              if (_stale)
                TextButton(
                  onPressed: _busy ? null : _reload,
                  child: Text(
                    es
                        ? 'Descartar cambios y volver a cargar'
                        : 'Discard edits and reload',
                  ),
                ),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    _message == 'published'
                        ? (es
                              ? 'Publicada. Ya puede usarse en trabajos nuevos.'
                              : 'Published. Available for new work.')
                        : (es ? 'Borrador guardado.' : 'Draft saved.'),
                  ),
                ),
              FilledButton(
                onPressed: _busy || _stale
                    ? null
                    : () => _write(_pendingAction ?? 'draft'),
                child: Text(
                  _busy
                      ? (es ? 'Guardando…' : 'Saving…')
                      : _pending != null
                      ? (es
                            ? 'Reintentar el mismo guardado'
                            : 'Retry same save')
                      : (es ? 'Guardar borrador' : 'Save draft'),
                ),
              ),
              if (_revision > 0 && _pending == null)
                OutlinedButton(
                  onPressed:
                      frozen ||
                          _dirty ||
                          _steps.isEmpty ||
                          _publishedRevision == _revision
                      ? null
                      : () => _write('publish'),
                  child: Text(es ? 'Publicar versión' : 'Publish version'),
                ),
              if (_dirty && _revision > 0)
                Text(
                  es
                      ? 'Guarda el borrador antes de publicar.'
                      : 'Save the draft before publishing.',
                ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
