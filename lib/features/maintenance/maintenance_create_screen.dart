import 'package:vortice_app/core/meter_units.dart';
import 'package:vortice_app/core/app_dropdown_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/unsaved_form_guard.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/fleet/fleet_providers.dart';
import 'package:vortice_app/models/work_order.dart';
import 'maintenance_models.dart';
import 'maintenance_repository.dart';
import 'maintenance_refresh.dart';

class MaintenanceCreateScreen extends ConsumerStatefulWidget {
  const MaintenanceCreateScreen({
    super.key,
    this.assetId,
    this.planId,
    this.parentJobId,
    this.faultId,
    this.planning = false,
    this.selectedDay,
    this.checklistTemplateId,
    this.componentId,
    this.initialTitle,
    this.initialInstructions,
  });
  final String? assetId, planId, parentJobId, faultId;
  final bool planning;
  final DateTime? selectedDay;
  final String? checklistTemplateId,
      componentId,
      initialTitle,
      initialInstructions;
  @override
  ConsumerState<MaintenanceCreateScreen> createState() =>
      _MaintenanceCreateScreenState();
}

class _MaintenanceCreateScreenState
    extends ConsumerState<MaintenanceCreateScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController(),
      _instructions = TextEditingController(),
      _materials = TextEditingController(),
      _cost = TextEditingController(text: '0');
  String? _asset, _assignee, _plan, _component, _checklist;
  WorkOrderJobType _workType = WorkOrderJobType.general;
  String _priority = 'normal';
  DateTime? _due;
  MaintenanceWrite? _pending;
  Object? _error;
  bool _saving = false,
      _faultPrefilled = false,
      _linkExisting = false,
      _planPrefilled = false;
  String? _existingJob;
  int? _pendingRevision;
  @override
  void initState() {
    super.initState();
    _asset = widget.assetId;
    _plan = widget.planId;
    _checklist = widget.checklistTemplateId;
    _component = widget.componentId;
    _title.text = widget.initialTitle ?? '';
    _instructions.text = widget.initialInstructions ?? '';
    _workType = widget.planId != null || widget.checklistTemplateId != null
        ? WorkOrderJobType.preventative
        : widget.faultId != null
        ? WorkOrderJobType.repair
        : WorkOrderJobType.general;
  }

  void _applyPlanContext(Map<String, dynamic> plan) {
    _component = plan['engine_id'] as String?;
    _checklist = plan['checklist_template_id'] as String?;
    _workType = WorkOrderJobType.preventative;
    if (_title.text.isEmpty) {
      final title =
          plan['interval_label'] as String? ??
          '${formatMeter(plan['interval_hours'] as num?, plan['meter_unit'] as String?)} service';
      _title.text = title.length > 200 ? title.substring(0, 200) : title;
    }
    if (_instructions.text.isEmpty) {
      _instructions.text = plan['notes'] as String? ?? '';
    }
    _due ??= DateTime.tryParse(plan['next_due_date']?.toString() ?? '');
  }

  @override
  void dispose() {
    _title.dispose();
    _instructions.dispose();
    _materials.dispose();
    _cost.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate() || _asset == null) return;
    final fault = widget.faultId == null
        ? null
        : ref.read(fleetFaultProvider(widget.faultId!)).valueOrNull;
    if (widget.faultId != null &&
        (fault == null ||
            !fault.canPlanRepair ||
            fault.workOrderId != null ||
            !fault.status.isActive)) {
      return;
    }
    _pendingRevision ??= fault?.revision;
    _pending ??= MaintenanceWrite(
      _linkExisting
          ? {'job_id': _existingJob, 'asset_id': _asset}
          : {
              'asset_id': _asset,
              'title': _title.text.trim(),
              'description': _instructions.text.trim(),
              'job_type': _plan == null ? _workType.dbValue : 'preventative',
              'expected_materials': _materials.text.trim(),
              if (_plan == null) 'checklist_template_id': _checklist,
              'assigned_to': _assignee,
              'priority': _priority,
              'service_interval_id': _plan,
              'engine_id': _component,
              'parent_job_id': widget.parentJobId,
              'hourly_cost': double.tryParse(_cost.text) ?? 0,
              'due_date': _due?.toIso8601String().split('T').first,
            },
    );
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repository = ref.read(maintenanceRepositoryProvider);
      final id = fault == null
          ? await repository.create(_pending!.id, _pending!.data)
          : await repository.planFault(
              fault.id,
              _pendingRevision!,
              _pending!.id,
              _pending!.data,
            );
      if (!mounted) return;
      refreshMaintenance(ref);
      context.go(
        widget.planning
            ? '/maintenance/planning?jobId=$id${widget.selectedDay == null ? '' : '&day=${widget.selectedDay!.toIso8601String().split('T').first}'}'
            : '/maintenance/jobs/$id',
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          if (maintenanceWriteWasRejected(error)) {
            _pending = null;
            _pendingRevision = null;
            if (widget.faultId != null) {
              ref.invalidate(fleetFaultProvider(widget.faultId!));
            }
          }
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final es = isSpanish(context);
    if (!isMaintenanceManager(ref.watch(profileProvider).valueOrNull?.role)) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Text(
            es
                ? 'Acceso de responsable requerido.'
                : 'Manager access required.',
          ),
        ),
      );
    }
    final source = widget.faultId == null
        ? null
        : ref.watch(fleetFaultProvider(widget.faultId!));
    final fault = source?.valueOrNull;
    if (widget.faultId != null) {
      if (source!.isLoading || fault == null || source.hasError) {
        return Scaffold(
          appBar: AppBar(title: Text(es ? 'Orden de trabajo' : 'Work order')),
          body: source.isLoading
              ? const Center(child: CircularProgressIndicator())
              : Center(
                  child: source.hasError
                      ? _retry(
                          source.error!,
                          () => ref.invalidate(
                            fleetFaultProvider(widget.faultId!),
                          ),
                        )
                      : Text(
                          es ? 'Falla no disponible.' : 'Fault unavailable.',
                        ),
                ),
        );
      }
      if (fault.workOrderId != null ||
          !fault.status.isActive ||
          !fault.canPlanRepair) {
        return Scaffold(
          appBar: AppBar(title: Text(es ? 'Orden de trabajo' : 'Work order')),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    es
                        ? 'Revisa el estado actual de la falla para continuar.'
                        : 'Review the current fault status to continue.',
                  ),
                  TextButton(
                    onPressed: () => context.go('/fleet/faults/${fault.id}'),
                    child: Text(es ? 'Volver a la falla' : 'Return to fault'),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      if (!_faultPrefilled) {
        _asset = fault.assetId;
        _title.text = fault.description.length > 200
            ? fault.description.substring(0, 200)
            : fault.description;
        _instructions.text = fault.description;
        _priority = fault.urgent ? 'urgent' : 'normal';
        _faultPrefilled = true;
      }
    }
    final workspace = ref.watch(maintenanceWorkspaceProvider);
    final catalog = _asset == null
        ? null
        : ref.watch(maintenanceAssetProvider(_asset!));
    final data = catalog?.valueOrNull;
    if (!_planPrefilled && widget.planId != null && data != null) {
      final selected = maintenanceRows(
        data['plans'],
      ).where((p) => p['id'] == widget.planId).firstOrNull;
      if (selected != null) {
        _applyPlanContext(selected);
        _planPrefilled = true;
      }
    }
    final frozen = _saving || _pending != null;
    return UnsavedFormGuard(
      isDirty: () =>
          _title.text.isNotEmpty ||
          _instructions.text.isNotEmpty ||
          _materials.text.isNotEmpty ||
          _pending != null,
      controllers: [_title, _instructions, _materials],
      busy: _saving,
      fallbackRoute: '/maintenance',
      child: Scaffold(
        appBar: AppBar(
          leading: const FormBackButton(fallbackRoute: '/maintenance'),
          title: Text(
            widget.faultId != null
                ? (es ? 'Crear orden de trabajo' : 'Create work order')
                : (es ? 'Nueva orden' : 'New work order'),
          ),
        ),
        body: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (fault != null) ...[
                Text(
                  fault.assetName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  es
                      ? 'La orden llevará la asignación, el informe, las horas y los repuestos de esta reparación.'
                      : 'The work order will hold the assignment, report, labour and parts for this repair.',
                ),
                const SizedBox(height: 16),
                AppDropdownField<bool>(
                  initialValue: _linkExisting,
                  decoration: InputDecoration(
                    labelText: es ? 'Cómo continuar' : 'How to continue',
                  ),
                  items: [
                    DropdownMenuItem(
                      value: false,
                      child: Text(
                        es ? 'Crear orden de trabajo' : 'Create work order',
                      ),
                    ),
                    DropdownMenuItem(
                      value: true,
                      child: Text(
                        es
                            ? 'Vincular orden existente'
                            : 'Link existing work order',
                      ),
                    ),
                  ],
                  onChanged: frozen
                      ? null
                      : (value) => setState(() => _linkExisting = value!),
                ),
                const SizedBox(height: 16),
              ],
              if (_linkExisting) ...[
                ref
                    .watch(maintenanceJobsProvider(_asset))
                    .when(
                      loading: () => const LinearProgressIndicator(),
                      error: (error, _) => _retry(
                        error,
                        () => ref.invalidate(maintenanceJobsProvider(_asset)),
                      ),
                      data: (jobs) {
                        final eligible = jobs
                            .where(
                              (job) =>
                                  job.assetId == _asset &&
                                  [
                                    'draft',
                                    'assigned',
                                    'in_progress',
                                    'on_hold',
                                  ].contains(job.status),
                            )
                            .toList();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (eligible.isEmpty)
                              Text(
                                es
                                    ? 'No hay órdenes abiertas para este equipo. Crea una nueva.'
                                    : 'No open work orders for this asset. Create a new one.',
                              ),
                            AppDropdownField<String>(
                              key: ValueKey(
                                eligible.map((j) => j.id).join(','),
                              ),
                              initialValue:
                                  eligible.any((j) => j.id == _existingJob)
                                  ? _existingJob
                                  : null,
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: es
                                    ? 'Orden abierta'
                                    : 'Open work order',
                              ),
                              items: eligible
                                  .map(
                                    (job) => DropdownMenuItem(
                                      value: job.id,
                                      child: Text(
                                        '${job.title} · ${job.lifecycleLabel(es)}',
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: frozen
                                  ? null
                                  : (value) {
                                      setState(() => _existingJob = value);
                                      _form.currentState?.validate();
                                    },
                              validator: (value) =>
                                  !eligible.any((j) => j.id == value)
                                  ? (es
                                        ? 'Selecciona una orden'
                                        : 'Choose a work order')
                                  : null,
                            ),
                            if (_error != null)
                              Text(maintenanceError(_error!, es)),
                            const SizedBox(height: 20),
                            FilledButton(
                              onPressed: _saving || eligible.isEmpty
                                  ? null
                                  : _save,
                              child: Text(
                                _saving
                                    ? (es ? 'Guardando…' : 'Saving…')
                                    : _pending != null
                                    ? (es ? 'Reintentar vínculo' : 'Retry link')
                                    : (es
                                          ? 'Vincular y abrir orden'
                                          : 'Link & open work order'),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
              ] else ...[
                workspace.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => _retry(
                    e,
                    () => ref.invalidate(maintenanceWorkspaceProvider),
                  ),
                  data: (w) => AppDropdownField<String>(
                    initialValue: _asset,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: es ? 'Equipo' : 'Asset',
                    ),
                    items: maintenanceRows(w['assets'])
                        .map(
                          (a) => DropdownMenuItem(
                            value: a['id'] as String,
                            child: Text(a['name'] as String),
                          ),
                        )
                        .toList(),
                    onChanged:
                        frozen ||
                            widget.parentJobId != null ||
                            widget.faultId != null
                        ? null
                        : (v) => setState(() {
                            _asset = v;
                            _plan = null;
                            _assignee = null;
                            _component = null;
                            _checklist = null;
                          }),
                    validator: (v) => v == null
                        ? (es ? 'Selecciona un equipo' : 'Select an asset')
                        : null,
                  ),
                ),
                const SizedBox(height: 16),
                if (catalog?.isLoading == true) const LinearProgressIndicator(),
                if (catalog?.hasError == true)
                  _retry(
                    catalog!.error!,
                    () => ref.invalidate(maintenanceAssetProvider(_asset!)),
                  ),
                if (data != null) ...[
                  if (data['can_execute'] != true)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        es
                            ? 'El mantenimiento interno no está habilitado para esta empresa.'
                            : 'Internal maintenance is not enabled for this company.',
                      ),
                    ),
                  TextFormField(
                    controller: _title,
                    enabled: !frozen,
                    maxLength: 200,
                    decoration: InputDecoration(
                      labelText: es ? 'Título de la orden' : 'Work order title',
                    ),
                    validator: (v) => (v?.trim().length ?? 0) < 3
                        ? (es ? 'Describe el trabajo' : 'Describe the job')
                        : null,
                  ),
                  const SizedBox(height: 16),
                  AppDropdownField<WorkOrderJobType>(
                    key: ValueKey('work-type-$_plan'),
                    initialValue: _plan == null
                        ? _workType
                        : WorkOrderJobType.preventative,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: es ? 'Tipo de trabajo' : 'Work type',
                    ),
                    items: [
                      for (final type in WorkOrderJobType.values)
                        DropdownMenuItem(
                          value: type,
                          child: Text(type.label(es)),
                        ),
                    ],
                    onChanged: frozen || _plan != null || widget.faultId != null
                        ? null
                        : (value) => setState(() => _workType = value!),
                  ),
                  if (_plan != null)
                    Text(
                      es
                          ? 'El plan vinculado define este mantenimiento preventivo.'
                          : 'The linked service plan defines this preventive maintenance.',
                    ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _instructions,
                    enabled: !frozen,
                    minLines: 3,
                    maxLines: 6,
                    maxLength: 8000,
                    decoration: InputDecoration(
                      labelText: es ? 'Instrucciones' : 'Instructions',
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 16),
                  ExpansionTile(
                    key: ValueKey('optional-details-$_asset'),
                    initiallyExpanded:
                        _plan != null ||
                        _checklist != null ||
                        _component != null,
                    maintainState: true,
                    tilePadding: EdgeInsets.zero,
                    title: Text(
                      es ? 'Detalles opcionales' : 'Optional details',
                    ),
                    subtitle: Text(
                      es
                          ? 'Plan de servicio, lista y componente'
                          : 'Service plan, checklist and component',
                    ),
                    children: [
                      AppDropdownField<String>(
                        key: ValueKey('plan-$_asset'),
                        initialValue: _plan ?? '',
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: es
                              ? 'Plan (opcional)'
                              : 'Service plan (optional)',
                        ),
                        items: [
                          DropdownMenuItem<String>(
                            value: '',
                            child: Text(
                              es ? 'Sin plan recurrente' : 'No recurring plan',
                            ),
                          ),
                          ...maintenanceRows(data['plans'])
                              .where(
                                (p) =>
                                    p['engine_id'] != null &&
                                    p['is_active'] == true,
                              )
                              .map(
                                (p) => DropdownMenuItem(
                                  value: p['id'] as String,
                                  child: Text(
                                    '${p['interval_label'] ?? p['interval_hours']} · ${p['component_name']}',
                                  ),
                                ),
                              ),
                        ],
                        onChanged: frozen || data['can_plan'] != true
                            ? null
                            : (v) => setState(() {
                                _plan = v == '' ? null : v;
                                if (_plan != null) {
                                  final selected = maintenanceRows(
                                    data['plans'],
                                  ).where((p) => p['id'] == _plan).firstOrNull;
                                  if (selected != null) {
                                    _applyPlanContext(selected);
                                  }
                                }
                              }),
                      ),
                      const SizedBox(height: 16),
                      if (_plan == null) ...[
                        AppDropdownField<String>(
                          key: ValueKey('checklist-$_asset'),
                          initialValue: _checklist ?? '',
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: es
                                ? 'Lista de revisión (opcional)'
                                : 'Checklist (optional)',
                          ),
                          items: [
                            DropdownMenuItem(
                              value: '',
                              child: Text(
                                es ? 'Sin lista de revisión' : 'No checklist',
                              ),
                            ),
                            for (final template
                                in maintenanceRows(data['templates']).where(
                                  (t) =>
                                      t['scope_engine_id'] == null ||
                                      t['scope_engine_id'] == _component,
                                ))
                              DropdownMenuItem(
                                value: template['id'] as String,
                                child: Text(template['name'] as String),
                              ),
                          ],
                          onChanged: frozen
                              ? null
                              : (value) => setState(
                                  () => _checklist = value == '' ? null : value,
                                ),
                        ),
                        const SizedBox(height: 16),
                        AppDropdownField<String>(
                          key: ValueKey('component-$_asset'),
                          initialValue: _component ?? '',
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: es
                                ? 'Componente'
                                : 'Component (optional)',
                          ),
                          items: [
                            DropdownMenuItem(
                              value: '',
                              child: Text(
                                es ? 'Sin componente' : 'No component',
                              ),
                            ),
                            ...maintenanceRows(data['components']).map(
                              (e) => DropdownMenuItem(
                                value: e['id'] as String,
                                child: Text(e['label'] as String),
                              ),
                            ),
                          ],
                          onChanged: frozen
                              ? null
                              : (v) => setState(() {
                                  _component = v == '' ? null : v;
                                  final selected =
                                      maintenanceRows(data['templates'])
                                          .where((t) => t['id'] == _checklist)
                                          .firstOrNull;
                                  if (selected?['scope_engine_id'] != null &&
                                      selected!['scope_engine_id'] !=
                                          _component) {
                                    _checklist = null;
                                  }
                                }),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  AppDropdownField<String>(
                    key: ValueKey('assignee-$_asset'),
                    initialValue: _assignee ?? '',
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: es ? 'Responsable' : 'Assigned to',
                    ),
                    items: [
                      DropdownMenuItem(
                        value: '',
                        child: Text(es ? 'Sin asignar' : 'Unassigned'),
                      ),
                      ...maintenanceRows(data['assignees']).map(
                        (p) => DropdownMenuItem(
                          value: p['id'] as String,
                          child: Text(p['name'] as String),
                        ),
                      ),
                    ],
                    onChanged: frozen
                        ? null
                        : (v) => setState(() => _assignee = v == '' ? null : v),
                  ),
                  const SizedBox(height: 16),
                  AppDropdownField<String>(
                    initialValue: _priority,
                    decoration: InputDecoration(
                      labelText: es ? 'Prioridad' : 'Priority',
                    ),
                    items: [
                      for (final p in ['low', 'normal', 'high', 'urgent'])
                        DropdownMenuItem(
                          value: p,
                          child: Text(maintenancePriority(p, es)),
                        ),
                    ],
                    onChanged: frozen
                        ? null
                        : (v) => setState(() => _priority = v!),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(es ? 'Fecha límite' : 'Due date'),
                    subtitle: Text(
                      _due?.toIso8601String().split('T').first ??
                          (es ? 'Sin fecha' : 'Not set'),
                    ),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: frozen
                        ? null
                        : () async {
                            final now = DateTime.now();
                            final date = await showDatePicker(
                              context: context,
                              initialDate: _due ?? now,
                              firstDate: DateTime(now.year - 1),
                              lastDate: DateTime(now.year + 10),
                            );
                            if (mounted && date != null) {
                              setState(() => _due = date);
                            }
                          },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _cost,
                    enabled: !frozen,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: es
                          ? 'Costo/hora (USD)'
                          : 'Internal hourly cost (USD)',
                    ),
                    validator: (v) =>
                        double.tryParse(v ?? '')?.isFinite != true ||
                            double.parse(v!) < 0
                        ? (es
                              ? 'Ingresa un costo válido'
                              : 'Enter a valid cost')
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _materials,
                    enabled: !frozen,
                    minLines: 2,
                    maxLines: 4,
                    maxLength: 4000,
                    decoration: InputDecoration(
                      labelText: es
                          ? 'Repuestos y materiales previstos'
                          : 'Expected parts / materials',
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    es
                        ? 'Este trabajo no genera una factura.'
                        : 'This job does not generate an invoice.',
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(maintenanceError(_error!, es)),
                    ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed:
                        _saving ||
                            data['can_execute'] != true ||
                            ((widget.planning || _plan != null) &&
                                data['can_plan'] != true)
                        ? null
                        : _save,
                    child: Text(
                      _saving
                          ? (es ? 'Guardando…' : 'Saving…')
                          : _pending != null
                          ? (es ? 'Reintentar guardado' : 'Retry save')
                          : widget.faultId != null
                          ? (es
                                ? 'Crear y abrir orden'
                                : 'Create & open work order')
                          : (es
                                ? 'Crear orden de trabajo'
                                : 'Create work order'),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _retry(Object error, VoidCallback retry) => Column(
    children: [
      Text(maintenanceError(error, isSpanish(context))),
      TextButton(
        onPressed: retry,
        child: Text(isSpanish(context) ? 'Reintentar' : 'Try again'),
      ),
    ],
  );
}
