import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:vortice_app/core/app_dropdown_field.dart';
import 'package:vortice_app/core/unsaved_form_guard.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/features/maintenance/maintenance_create_screen.dart';
import 'package:vortice_app/features/maintenance/maintenance_setup_screen.dart';
import 'package:vortice_app/features/maintenance/maintenance_repository.dart';
import 'package:vortice_app/features/checklists/checklist_assignment_provider.dart';
import 'package:vortice_app/features/checklists/asset_checklist_template_filter.dart';
import 'package:vortice_app/features/service_intervals/maintenance_work_order_draft.dart';
import 'package:vortice_app/models/checklist_template.dart';
import 'package:vortice_app/models/work_order.dart';
import 'checklist_builder_repository.dart';

class ChecklistUseScreen extends ConsumerStatefulWidget {
  const ChecklistUseScreen({
    super.key,
    required this.template,
    required this.catalog,
  });
  final Map<String, dynamic> template, catalog;
  @override
  ConsumerState<ChecklistUseScreen> createState() => _ChecklistUseScreenState();
}

class _ChecklistUseScreenState extends ConsumerState<ChecklistUseScreen> {
  final _notes = TextEditingController();
  final _assignment = const Uuid().v4();
  String? _asset, _engine, _person;
  DateTime? _due;
  Future<Map<String, dynamic>>? _context;
  MaintenanceWrite? _pending;
  bool _busy = false, _dirty = false;
  Object? _error;
  bool get _pm => widget.template['checklist_type'] == 'pm';
  @override
  void initState() {
    super.initState();
    _asset = widget.template['scope_asset_id'] as String?;
    _engine = widget.template['scope_engine_id'] as String?;
    if (_asset != null) _load();
  }

  void _load() {
    _context = _pm
        ? ref.read(maintenanceRepositoryProvider).assetContext(_asset!)
        : ref.read(checklistBuilderRepositoryProvider).assignments(_asset!);
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _assign() async {
    if (_asset == null || _person == null) return;
    _pending ??= MaintenanceWrite({
      'asset_id': _asset,
      'template_id': widget.template['id'],
      'assigned_to': _person,
      'notes': _notes.text.trim(),
      'due_date': _due?.toIso8601String().split('T').first,
    });
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(checklistBuilderRepositoryProvider)
          .assign(_pending!.id, _assignment, _pending!.data);
      ref.invalidate(myChecklistAssignmentsProvider);
      ref.invalidate(orgChecklistAssignmentsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isSpanish(context)
                  ? 'Revisión asignada.'
                  : 'Pre-operation check assigned.',
            ),
          ),
        );
        Navigator.pop(context);
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
    final template = ChecklistTemplate.fromJson(widget.template);
    final assets = checklistRows(widget.catalog['assets'])
        .where(
          (a) => checklistTemplateMatches(
            template,
            kind: template.checklistType,
            assetId: a['id'] as String,
            assetTypeId: a['asset_type_id'] as String?,
            clientId: a['client_id'] as String?,
            engineId: template.scopeEngineId,
          ),
        )
        .toList();
    return UnsavedFormGuard(
      isDirty: () => _dirty,
      controllers: [_notes],
      busy: _busy,
      fallbackRoute: '/checklist-library',
      child: Scaffold(
        appBar: AppBar(title: Text(es ? 'Usar lista' : 'Use checklist')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              '${template.name} · v${template.version}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            if (assets.isEmpty)
              Text(
                es
                    ? 'No hay equipo compatible. Revisa el tipo y alcance de la lista.'
                    : 'No equipment matches. Check the template type and scope.',
              ),
            AppDropdownField<String>(
              initialValue: _asset,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: es ? 'Equipo' : 'Equipment',
              ),
              items: [
                for (final a in assets)
                  DropdownMenuItem(
                    value: a['id'] as String,
                    child: Text(a['name'] as String),
                  ),
              ],
              onChanged: frozen
                  ? null
                  : (value) => setState(() {
                      _asset = value;
                      _engine = template.scopeEngineId;
                      _person = null;
                      _dirty = true;
                      _load();
                    }),
            ),
            const SizedBox(height: 16),
            if (_context != null)
              FutureBuilder<Map<String, dynamic>>(
                future: _context,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Column(
                      children: [
                        Text(friendlyError(context, snapshot.error!)),
                        TextButton(
                          onPressed: () => setState(_load),
                          child: Text(es ? 'Reintentar' : 'Retry'),
                        ),
                      ],
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final data = snapshot.data!;
                  if (_pm) {
                    final components = checklistRows(data['components'])
                        .where(
                          (c) =>
                              template.scopeEngineId == null ||
                              c['id'] == template.scopeEngineId,
                        )
                        .toList();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppDropdownField<String>(
                          key: ValueKey('component:$_asset'),
                          initialValue: _engine ?? '',
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: es ? 'Componente' : 'Component',
                          ),
                          items: [
                            if (template.scopeEngineId == null)
                              DropdownMenuItem(
                                value: '',
                                child: Text(
                                  es ? 'Sin componente' : 'No component',
                                ),
                              ),
                            for (final c in components)
                              DropdownMenuItem(
                                value: c['id'] as String,
                                child: Text(c['label'] as String),
                              ),
                          ],
                          onChanged: (value) => setState(
                            () => _engine = value == '' ? null : value,
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: data['can_execute'] != true
                              ? null
                              : () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => MaintenanceCreateScreen(
                                      assetId: _asset,
                                      componentId: _engine,
                                      checklistTemplateId: template.id,
                                      initialTitle: template.name,
                                      initialInstructions: template.description,
                                    ),
                                  ),
                                ),
                          child: Text(
                            es ? 'Crear orden de trabajo' : 'Create work order',
                          ),
                        ),
                        OutlinedButton(
                          onPressed: _engine == null || data['can_plan'] != true
                              ? null
                              : () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => MaintenanceSetupScreen(
                                      kind: 'plan',
                                      assetId: _asset,
                                      catalog: data,
                                      initial: {
                                        'engine_id': _engine,
                                        'checklist_template_id': template.id,
                                        'interval_label': template.name,
                                        if (template.intervalHours != null)
                                          'interval_hours':
                                              template.intervalHours,
                                      },
                                    ),
                                  ),
                                ),
                          child: Text(
                            es
                                ? 'Añadir al plan de mantenimiento'
                                : 'Add to maintenance plan',
                          ),
                        ),
                        if (_engine == null)
                          Text(
                            es
                                ? 'Selecciona un componente para crear un plan recurrente.'
                                : 'Select a component to create a recurring plan.',
                          ),
                        if (widget.catalog['client_id'] == null)
                          TextButton(
                            onPressed: () => context.push(
                              Uri(
                                path: '/owner/work-orders/create',
                                queryParameters: MaintenanceWorkOrderDraft(
                                  assetId: _asset,
                                  engineId: _engine,
                                  title: template.name,
                                  description: template.description ?? '',
                                  checklistTemplateId: template.id,
                                  jobType: WorkOrderJobType.preventative,
                                ).toQueryParameters(),
                              ).toString(),
                            ),
                            child: Text(
                              es
                                  ? 'Crear orden de servicio del proveedor'
                                  : 'Create provider service order',
                            ),
                          ),
                      ],
                    );
                  }
                  final people = checklistRows(data['people']);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (people.isEmpty)
                        Text(
                          es
                              ? 'Invita un operador a esta empresa antes de asignar la revisión.'
                              : 'Invite an operator to this company before assigning a check.',
                        ),
                      AppDropdownField<String>(
                        key: ValueKey('person:$_asset'),
                        initialValue: _person,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: es ? 'Operador' : 'Operator',
                        ),
                        items: [
                          for (final p in people)
                            DropdownMenuItem(
                              value: p['id'] as String,
                              child: Text(p['name'] as String),
                            ),
                        ],
                        onChanged: frozen
                            ? null
                            : (v) => setState(() {
                                _person = v;
                                _dirty = true;
                              }),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(es ? 'Fecha límite' : 'Due date'),
                        subtitle: Text(
                          _due?.toIso8601String().split('T').first ??
                              (es ? 'Sin fecha' : 'No date'),
                        ),
                        trailing: const Icon(Icons.calendar_month_outlined),
                        onTap: frozen
                            ? null
                            : () async {
                                final date = await showDatePicker(
                                  context: context,
                                  initialDate: _due ?? DateTime.now(),
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2100),
                                );
                                if (date != null && mounted) {
                                  setState(() {
                                    _due = date;
                                    _dirty = true;
                                  });
                                }
                              },
                      ),
                      TextField(
                        controller: _notes,
                        enabled: !frozen,
                        minLines: 2,
                        maxLines: 4,
                        maxLength: 2000,
                        decoration: InputDecoration(
                          labelText: es
                              ? 'Instrucciones para el operador'
                              : 'Instructions for the operator',
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _busy || _person == null ? null : _assign,
                        child: Text(
                          _pending != null
                              ? (es
                                    ? 'Reintentar asignación'
                                    : 'Retry assignment')
                              : (es
                                    ? 'Asignar revisión'
                                    : 'Assign pre-operation check'),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        es
                            ? 'Revisiones asignadas en este equipo'
                            : 'Assigned checks on this equipment',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      for (final a in checklistRows(data['assignments']))
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(a['template_name'] as String? ?? ''),
                          subtitle: Text(
                            '${a['assignee_name']} · ${a['status']}',
                          ),
                          onTap: a['completed_run_id'] == null
                              ? null
                              : () => context.push(
                                  '/client/assets/$_asset/checklist-history',
                                ),
                        ),
                    ],
                  );
                },
              ),
            if (_error != null) Text(maintenanceError(_error!, es)),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
