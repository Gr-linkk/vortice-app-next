import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vortice_app/core/app_dropdown_field.dart';
import 'package:vortice_app/core/unsaved_form_guard.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/sync/field_work_provider.dart';
import '../maintenance_models.dart';
import '../maintenance_repository.dart';
import '../maintenance_refresh.dart';
import 'planning_models.dart';
import 'planning_repository.dart';
import 'package:vortice_app/sync/online_action_gate.dart';

class ScheduleJobScreen extends ConsumerStatefulWidget {
  const ScheduleJobScreen({
    super.key,
    required this.job,
    required this.jobs,
    this.initialDay,
  });
  final PlanningJob job;
  final List<PlanningJob> jobs;
  final DateTime? initialDay;
  @override
  ConsumerState<ScheduleJobScreen> createState() => _ScheduleJobScreenState();
}

class _ScheduleJobScreenState extends ConsumerState<ScheduleJobScreen> {
  final _form = GlobalKey<FormState>();
  late DateTime? _start, _due;
  late String? _assignee;
  late String _priority;
  late final TextEditingController _duration;
  final _reason = TextEditingController();
  bool _allowOverlap = false, _busy = false, _dirty = false;
  MaintenanceWrite? _pending;
  Object? _error;
  late PlanningJob _job;
  @override
  void initState() {
    super.initState();
    _job = widget.job;
    final day = widget.initialDay;
    _start =
        widget.job.start ??
        (day == null ? null : DateTime(day.year, day.month, day.day, 8));
    _due = DateTime.tryParse(widget.job.dueDate ?? '');
    _assignee = widget.job.assignee;
    _priority = widget.job.priority;
    _duration = TextEditingController(
      text: '${widget.job.minutes == 0 ? 60 : widget.job.minutes}',
    );
  }

  @override
  void dispose() {
    _duration.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _pick(bool booking) async {
    final initial = (booking ? _start : _due) ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    if (!booking) {
      setState(() {
        _due = date;
        _dirty = true;
      });
      return;
    }
    final time = await showTimePicker(
      context: context,
      initialTime: _start == null
          ? const TimeOfDay(hour: 8, minute: 0)
          : TimeOfDay.fromDateTime(_start!),
    );
    if (time == null || !mounted) return;
    setState(() {
      _start = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      _dirty = true;
      _allowOverlap = false;
    });
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (!await requireOnlineAction(context, ref) || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final queue = ref.read(fieldWorkQueueProvider);
      if (queue != null &&
          (await queue.list()).any(
            (o) =>
                o.subject == widget.job.id &&
                !o.synced &&
                o.status != 'cancelled',
          )) {
        throw const PostgrestException(
          message:
              'Sync or resolve pending field changes before scheduling this job.',
          code: 'P0001',
        );
      }
      _pending ??= MaintenanceWrite({
        'planned_start': _start?.toUtc().toIso8601String(),
        'estimated_minutes': _start == null ? null : int.parse(_duration.text),
        'assigned_to': _assignee,
        'priority': _priority,
        'due_date': _due == null
            ? null
            : DateFormat('yyyy-MM-dd').format(_due!),
        'note': _reason.text.trim(),
        'allow_overlap': _allowOverlap,
      });
      await ref
          .read(planningRepositoryProvider)
          .schedule(_job.id, _job.revision, _pending!.id, _pending!.data);
      if (mounted) {
        refreshMaintenance(ref, jobId: widget.job.id);
        ref.invalidate(maintenancePlanningProvider);
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          if (maintenanceWriteWasRejected(error)) {
            _pending = null;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reload() async {
    setState(() => _busy = true);
    try {
      final latest = await ref
          .read(planningRepositoryProvider)
          .load(_job.assetId);
      final job = latest.jobs.where((j) => j.id == _job.id).firstOrNull;
      if (job == null || !job.schedulable) {
        throw const PostgrestException(
          message: 'This job is no longer available for scheduling.',
          code: 'P0001',
        );
      }
      if (mounted) {
        setState(() {
          _job = job;
          _start = job.start;
          _due = DateTime.tryParse(job.dueDate ?? '');
          _assignee = job.assignee;
          _priority = job.priority;
          _allowOverlap = false;
          _duration.text = '${job.minutes == 0 ? 60 : job.minutes}';
          _pending = null;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final es = isSpanish(context), frozen = _busy || _pending != null;
    final catalog = ref.watch(maintenanceAssetProvider(widget.job.assetId));
    final conflicts = bookingConflicts(
      widget.jobs,
      jobId: widget.job.id,
      assetId: widget.job.assetId,
      assignee: _assignee,
      start: _start,
      minutes: int.tryParse(_duration.text) ?? 0,
    );
    return UnsavedFormGuard(
      isDirty: () => _dirty,
      controllers: [_duration, _reason],
      fallbackRoute: '/maintenance/planning',
      busy: _busy,
      child: Scaffold(
        appBar: AppBar(title: Text(es ? 'Programar trabajo' : 'Schedule work')),
        body: catalog.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(maintenanceError(e, es)),
                TextButton(
                  onPressed: () => ref.invalidate(
                    maintenanceAssetProvider(widget.job.assetId),
                  ),
                  child: Text(es ? 'Reintentar' : 'Retry'),
                ),
              ],
            ),
          ),
          data: (data) {
            final people = maintenanceRows(data['assignees']);
            if (_assignee != null && !people.any((p) => p['id'] == _assignee)) {
              people.add({'id': _assignee, 'name': widget.job.assigneeName});
            }
            return Form(
              key: _form,
              onChanged: () => _dirty = true,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                children: [
                  Text(
                    widget.job.title,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text(widget.job.assetName),
                  const OnlineOnlyNotice(),
                  const SizedBox(height: 16),
                  Text(
                    es
                        ? 'Planifica el trabajo futuro. Guardar no inicia el trabajo ni completa el servicio.'
                        : 'Plan the work ahead. Saving does not start work or complete a service.',
                  ),
                  const SizedBox(height: 20),
                  AppDropdownField<String>(
                    key: ValueKey('assignee-${_job.revision}'),
                    initialValue: _assignee ?? '',
                    decoration: InputDecoration(
                      labelText: es ? 'Responsable' : 'Assignee',
                    ),
                    items: [
                      DropdownMenuItem(
                        value: '',
                        child: Text(es ? 'Sin asignar' : 'Unassigned'),
                      ),
                      for (final person in people)
                        DropdownMenuItem(
                          value: person['id'] as String,
                          child: Text(person['name'] as String? ?? ''),
                        ),
                    ],
                    onChanged: frozen
                        ? null
                        : (value) => setState(() {
                            _assignee = value == '' ? null : value;
                            _allowOverlap = false;
                          }),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(es ? 'Inicio programado' : 'Booked start'),
                    subtitle: Text(
                      _start == null
                          ? (es ? 'Sin programar' : 'Unscheduled')
                          : DateFormat.yMMMd(
                              es ? 'es' : 'en',
                            ).add_Hm().format(_start!),
                    ),
                    trailing: const Icon(Icons.edit_calendar_outlined),
                    onTap: frozen ? null : () => _pick(true),
                  ),
                  Text(
                    es
                        ? 'Las horas se muestran en la zona horaria de este dispositivo.'
                        : 'Times use this device’s local time zone.',
                  ),
                  if (_start != null) ...[
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _duration,
                      enabled: !frozen,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: es
                            ? 'Duración estimada (minutos)'
                            : 'Estimated duration (minutes)',
                      ),
                      onChanged: (_) => setState(() => _allowOverlap = false),
                      validator: (value) {
                        final minutes = int.tryParse(value ?? '');
                        return minutes == null ||
                                minutes < 15 ||
                                minutes > 10080
                            ? (es
                                  ? 'Introduce de 15 a 10080 minutos'
                                  : 'Enter 15 to 10080 minutes')
                            : null;
                      },
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: frozen
                            ? null
                            : () => setState(() {
                                _start = null;
                                _dirty = true;
                                _allowOverlap = false;
                              }),
                        child: Text(
                          es
                              ? 'Volver a sin programar'
                              : 'Return to unscheduled',
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(es ? 'Fecha límite' : 'Deadline'),
                    subtitle: Text(
                      _due == null
                          ? (es ? 'Sin fecha límite' : 'No deadline')
                          : DateFormat.yMMMd(es ? 'es' : 'en').format(_due!),
                    ),
                    trailing: const Icon(Icons.calendar_today_outlined),
                    onTap: frozen ? null : () => _pick(false),
                  ),
                  if (_due != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: frozen
                            ? null
                            : () => setState(() {
                                _due = null;
                                _dirty = true;
                              }),
                        child: Text(
                          es ? 'Quitar fecha límite' : 'Clear deadline',
                        ),
                      ),
                    ),
                  if (_start != null &&
                      _due != null &&
                      planningDay(_start!).isAfter(_due!))
                    Text(
                      es
                          ? 'El trabajo está programado después de la fecha límite.'
                          : 'This booking starts after the deadline.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  const SizedBox(height: 16),
                  AppDropdownField<String>(
                    key: ValueKey('priority-${_job.revision}'),
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
                        : (value) => setState(() => _priority = value!),
                  ),
                  const SizedBox(height: 16),
                  if (conflicts.isNotEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              es
                                  ? 'Conflictos de horario'
                                  : 'Scheduling conflicts',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            for (final job in conflicts)
                              Text(
                                '${job.title} · ${job.assetName} · ${job.assigneeName}',
                              ),
                          ],
                        ),
                      ),
                    ),
                  if (_start != null)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _allowOverlap,
                      onChanged: frozen
                          ? null
                          : (value) => setState(() => _allowOverlap = value!),
                      title: Text(
                        es
                            ? 'Permitir superposición por el motivo indicado'
                            : 'Allow overlap for the reason below',
                      ),
                      subtitle: Text(
                        es
                            ? 'El servidor vuelve a comprobar los horarios al guardar.'
                            : 'Schedules are checked again when saving.',
                      ),
                    ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _reason,
                    enabled: !frozen,
                    maxLines: 3,
                    maxLength: 1000,
                    decoration: InputDecoration(
                      labelText: es
                          ? 'Motivo de la planificación'
                          : 'Scheduling reason',
                    ),
                    validator: (value) => (value?.trim().length ?? 0) < 3
                        ? (es ? 'Explica el cambio' : 'Explain the change')
                        : null,
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(maintenanceError(_error!, es)),
                    ),
                  if (_error is PostgrestException &&
                      (_error as PostgrestException).code == '40001')
                    TextButton(
                      onPressed: _busy ? null : _reload,
                      child: Text(
                        es
                            ? 'Reemplazar campos con la planificación actual'
                            : 'Replace fields with the latest schedule',
                      ),
                    ),
                  SafeArea(
                    top: false,
                    child: FilledButton(
                      onPressed: _busy ? null : _save,
                      child: Text(
                        _busy
                            ? (es ? 'Guardando…' : 'Saving…')
                            : _pending != null
                            ? (es
                                  ? 'Reintentar el mismo guardado'
                                  : 'Retry same save')
                            : (es ? 'Guardar planificación' : 'Save schedule'),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
