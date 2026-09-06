import 'package:vortice_app/core/app_dropdown_field.dart';
import 'package:vortice_app/features/coordination/coordination_entry.dart';
import 'package:vortice_app/features/coordination/coordination_labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'maintenance_models.dart';
import 'maintenance_report_screen.dart';
import 'maintenance_repository.dart';
import 'maintenance_refresh.dart';

class MaintenanceJobScreen extends ConsumerStatefulWidget {
  const MaintenanceJobScreen({super.key, required this.jobId});
  final String jobId;
  @override
  ConsumerState<MaintenanceJobScreen> createState() =>
      _MaintenanceJobScreenState();
}

class _MaintenanceJobScreenState extends ConsumerState<MaintenanceJobScreen> {
  MaintenanceWrite? _pending;
  String? _action;
  int? _revision;
  bool _busy = false;
  Object? _error;
  void _refresh() {
    refreshMaintenance(ref, jobId: widget.jobId);
  }

  Future<void> _act(
    MaintenanceJob job,
    String action, [
    Map<String, dynamic> data = const {},
  ]) async {
    _pending ??= MaintenanceWrite(data);
    _action ??= action;
    _revision ??= job.revision;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(maintenanceRepositoryProvider)
          .change(job.id, _revision!, _pending!.id, _action!, _pending!.data);
      if (mounted) {
        setState(() {
          _pending = null;
          _action = null;
          _revision = null;
        });
        _refresh();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          if (maintenanceWriteWasRejected(error)) {
            _pending = null;
            _action = null;
            _revision = null;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _formAction(
    MaintenanceJob job,
    String action,
    String title,
  ) async {
    Map<String, dynamic>? catalog;
    try {
      if (action == 'assign') {
        catalog = await ref.read(maintenanceAssetProvider(job.assetId).future);
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
      return;
    }
    if (!mounted) return;
    final values = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _JobActionDialog(
        action: action,
        title: title,
        assignees: maintenanceRows(catalog?['assignees']),
      ),
    );
    if (values != null && mounted) await _act(job, action, values);
  }

  @override
  Widget build(BuildContext context) {
    final es = isSpanish(context);
    final result = ref.watch(maintenanceJobProvider(widget.jobId));
    return Scaffold(
      appBar: AppBar(
        title: Text(es ? 'Detalle del trabajo' : 'Job details'),
        actions: [
          IconButton(
            tooltip: es ? 'Actualizar' : 'Refresh',
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: result.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(maintenanceError(e, es)),
                TextButton(
                  onPressed: _refresh,
                  child: Text(es ? 'Reintentar' : 'Try again'),
                ),
              ],
            ),
          ),
        ),
        data: (job) {
          if (job == null) {
            return Center(
              child: Text(
                es
                    ? 'Trabajo no disponible para tu cuenta.'
                    : 'This job is unavailable to your account.',
              ),
            );
          }
          final disabled = _busy || _pending != null;
          final userId = ref.watch(profileProvider).valueOrNull?.id;
          Widget info(String label, String? value) =>
              value == null || value.isEmpty
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text('$label: $value'),
                );
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(job.title, style: Theme.of(context).textTheme.headlineSmall),
              CoordinationEntry(
                assetId: job.assetId,
                kind: 'job',
                subjectId: job.id,
              ),
              TextButton.icon(
                onPressed: () =>
                    context.push('/maintenance/assets/${job.assetId}'),
                icon: const Icon(Icons.precision_manufacturing_outlined),
                label: Text(job.assetName),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(label: Text(maintenanceStatus(job.status, es))),
                  Chip(label: Text(maintenancePriority(job.priority, es))),
                  if (job.isService)
                    Chip(
                      label: Text(
                        es ? 'Servicio programado' : 'Scheduled service',
                      ),
                    ),
                ],
              ),
              info(
                es ? 'Responsable' : 'Assigned to',
                job.data['assignee_name'] as String? ??
                    (es ? 'Sin asignar' : 'Unassigned'),
              ),
              if (job.dueDate != null)
                info(
                  es ? 'Fecha límite' : 'Due date',
                  maintenanceDate(job.dueDate, es),
                ),
              info(
                es ? 'Componente' : 'Component',
                job.data['component_name'] as String?,
              ),
              info(
                es ? 'Instrucciones' : 'Instructions',
                job.data['description'] as String?,
              ),
              info(
                es ? 'Motivo del bloqueo' : 'Blocked reason',
                job.data['on_hold_reason'] as String?,
              ),
              info(
                es ? 'Revisión' : 'Review note',
                job.data['review_note'] as String?,
              ),
              if (job.data['parent_job_id'] != null)
                TextButton(
                  onPressed: () => context.push(
                    '/maintenance/jobs/${job.data['parent_job_id']}',
                  ),
                  child: Text(
                    es ? 'Ver trabajo anterior' : 'View preceding job',
                  ),
                ),
              if (!job.canWork)
                Text(
                  es
                      ? 'Historial disponible; la ejecución está deshabilitada.'
                      : 'History is available; execution is disabled.',
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(maintenanceError(_error!, es)),
                ),
              if (_pending != null)
                FilledButton(
                  onPressed: _busy ? null : () => _act(job, _action!),
                  child: Text(
                    es ? 'Reintentar la misma acción' : 'Retry the same action',
                  ),
                ),
              if (_busy) const LinearProgressIndicator(),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (job.canWork &&
                      [
                        'draft',
                        'assigned',
                        'in_progress',
                        'on_hold',
                      ].contains(job.status) &&
                      !job.labour.any(
                        (s) =>
                            s['actor_id'] == userId && s['stopped_at'] == null,
                      ))
                    FilledButton.icon(
                      onPressed: disabled ? null : () => _act(job, 'start'),
                      icon: const Icon(Icons.play_arrow),
                      label: Text(es ? 'Iniciar tiempo' : 'Start labour'),
                    ),
                  if (job.canEdit)
                    OutlinedButton(
                      onPressed: disabled
                          ? null
                          : () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute<bool>(
                                  builder: (_) =>
                                      MaintenanceReportScreen(job: job),
                                ),
                              );
                              if (mounted) _refresh();
                            },
                      child: Text(
                        es ? 'Informe y revisión' : 'Report & submit',
                      ),
                    ),
                  if (job.canEdit)
                    OutlinedButton(
                      onPressed: disabled
                          ? null
                          : () => _formAction(
                              job,
                              'add_part',
                              es ? 'Añadir repuesto' : 'Add part',
                            ),
                      child: Text(es ? 'Añadir repuesto' : 'Add part'),
                    ),
                  if (job.canWork &&
                      ['assigned', 'in_progress'].contains(job.status))
                    OutlinedButton(
                      onPressed: disabled
                          ? null
                          : () => _formAction(
                              job,
                              'block',
                              es ? 'Bloquear trabajo' : 'Block work',
                            ),
                      child: Text(es ? 'Bloquear' : 'Block'),
                    ),
                  if (job.canManage &&
                      job.canWork &&
                      !['closed', 'pending_review'].contains(job.status))
                    OutlinedButton(
                      onPressed: disabled
                          ? null
                          : () => _formAction(
                              job,
                              'assign',
                              es ? 'Asignar trabajo' : 'Assign job',
                            ),
                      child: Text(es ? 'Asignar' : 'Assign'),
                    ),
                  if (job.canManage &&
                      job.canWork &&
                      job.status == 'pending_review') ...[
                    FilledButton(
                      onPressed: disabled
                          ? null
                          : () => _formAction(
                              job,
                              'approve',
                              es ? 'Aprobar y completar' : 'Approve & complete',
                            ),
                      child: Text(
                        es ? 'Aprobar y completar' : 'Approve & complete',
                      ),
                    ),
                    OutlinedButton(
                      onPressed: disabled
                          ? null
                          : () => _formAction(
                              job,
                              'return',
                              es ? 'Devolver trabajo' : 'Return for changes',
                            ),
                      child: Text(es ? 'Devolver' : 'Return'),
                    ),
                  ],
                  if (job.canManage && job.canWork && job.status == 'closed')
                    OutlinedButton(
                      onPressed: disabled
                          ? null
                          : () => _formAction(
                              job,
                              'reopen',
                              es ? 'Reabrir trabajo' : 'Reopen job',
                            ),
                      child: Text(es ? 'Reabrir' : 'Reopen'),
                    ),
                  if (job.canManage && job.canWork)
                    OutlinedButton(
                      onPressed: disabled
                          ? null
                          : () => context.push(
                              '/maintenance/new?assetId=${job.assetId}&parentJobId=${job.id}',
                            ),
                      child: Text(
                        es ? 'Trabajo de seguimiento' : 'Follow-up job',
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                es ? 'Mano de obra' : 'Labour',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              for (final session in job.labour)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    maintenanceDate(session['started_at'] as String?, es),
                  ),
                  subtitle: Text(
                    session['stopped_at'] == null
                        ? (es ? 'En curso' : 'Running')
                        : maintenanceDate(session['stopped_at'] as String?, es),
                  ),
                  trailing:
                      session['stopped_at'] == null &&
                          job.canWork &&
                          (job.canManage || session['actor_id'] == userId)
                      ? TextButton(
                          onPressed: disabled
                              ? null
                              : () => _act(job, 'pause', {
                                  'session_id': session['id'],
                                }),
                          child: Text(es ? 'Pausar' : 'Pause'),
                        )
                      : null,
                ),
              Text(
                '${job.completedLabourHours.toStringAsFixed(2)} ${es ? 'horas registradas' : 'recorded hours'}',
              ),
              const SizedBox(height: 20),
              Text(
                es ? 'Repuestos utilizados' : 'Parts used',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              for (final part in job.parts)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(part['description'] as String),
                  subtitle: Text(
                    '${part['quantity']} × ${part['unit_cost']} USD',
                  ),
                  trailing: job.canEdit
                      ? IconButton(
                          tooltip: es ? 'Quitar repuesto' : 'Remove part',
                          onPressed: disabled
                              ? null
                              : () => _act(job, 'remove_part', {
                                  'part_id': part['id'],
                                }),
                          icon: const Icon(Icons.remove_circle_outline),
                        )
                      : null,
                ),
              const SizedBox(height: 12),
              Text(
                '${es ? 'Costo interno' : 'Internal cost'}: ${(job.labourCost + job.partsCost).toStringAsFixed(2)} USD',
              ),
              Text(
                es
                    ? 'Mano de obra y repuestos; sin facturación al cliente.'
                    : 'Labour and parts; no customer billing.',
              ),
              const SizedBox(height: 24),
              Text(
                es ? 'Informe guardado' : 'Saved report',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              info(
                es ? 'Diagnóstico' : 'Diagnosis',
                job.report['diagnosis'] as String?,
              ),
              info(
                es ? 'Reparación' : 'Repair',
                job.report['repair'] as String?,
              ),
              info(es ? 'Notas' : 'Notes', job.report['notes'] as String?),
              info(
                es ? 'Horas al finalizar' : 'Completion meter',
                job.data['hours_at_end']?.toString(),
              ),
              for (final item in job.checklist)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    (es
                            ? item['description_es'] ?? item['description_en']
                            : item['description_en'])
                        as String,
                  ),
                  subtitle: Text(switch ((job.answers[item['id']]
                      as Map?)?['result']) {
                    'pass' => es ? 'Correcto' : 'Pass',
                    'fail' => es ? 'Falla' : 'Fail',
                    'na' => es ? 'No aplica' : 'Not applicable',
                    _ => es ? 'Sin responder' : 'Unanswered',
                  }),
                ),
              for (final path in job.evidence) MaintenanceEvidence(path: path),
              if (job.data['service_applied_at'] != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    es
                        ? 'El próximo servicio ya se actualizó. Reabrir este trabajo no lo avanza de nuevo.'
                        : 'The next service was updated. Reopening this job will not advance it again.',
                  ),
                ),
              const SizedBox(height: 24),
              Text(
                es ? 'Historial' : 'History',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              for (final event in maintenanceRows(job.data['events']))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${maintenanceEvent(event['kind'] as String, es)} · ${event['actor_name'] ?? ''}',
                  ),
                  subtitle: Text(
                    '${maintenanceDate(event['created_at'] as String?, es)}${event['note'] == null ? '' : '\n${event['note']}'}',
                  ),
                ),
              const SizedBox(height: 24),
              Text(
                es
                    ? 'La disponibilidad del equipo y el cierre de fallas se revisan por separado.'
                    : 'Asset availability and fault resolution are reviewed separately.',
              ),
            ],
          );
        },
      ),
    );
  }
}

class MaintenanceEvidence extends ConsumerStatefulWidget {
  const MaintenanceEvidence({super.key, required this.path});
  final String path;
  @override
  ConsumerState<MaintenanceEvidence> createState() =>
      _MaintenanceEvidenceState();
}

class _MaintenanceEvidenceState extends ConsumerState<MaintenanceEvidence> {
  late Future<String> _url;
  @override
  void initState() {
    super.initState();
    _url = ref.read(maintenanceRepositoryProvider).evidenceUrl(widget.path);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: FutureBuilder<String>(
      future: _url,
      builder: (context, result) {
        if (result.hasError) {
          return TextButton(
            onPressed: () => setState(
              () => _url = ref
                  .read(maintenanceRepositoryProvider)
                  .evidenceUrl(widget.path),
            ),
            child: Text(isSpanish(context) ? 'Reintentar foto' : 'Retry photo'),
          );
        }
        if (!result.hasData) return const LinearProgressIndicator();
        return Image.network(
          result.data!,
          height: 220,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Text(
            isSpanish(context) ? 'Foto no disponible' : 'Photo unavailable',
          ),
        );
      },
    ),
  );
}

class _JobActionDialog extends StatefulWidget {
  const _JobActionDialog({
    required this.action,
    required this.title,
    required this.assignees,
  });
  final String action, title;
  final List<Map<String, dynamic>> assignees;
  @override
  State<_JobActionDialog> createState() => _JobActionDialogState();
}

class _JobActionDialogState extends State<_JobActionDialog> {
  final _form = GlobalKey<FormState>();
  final _note = TextEditingController(),
      _description = TextEditingController(),
      _partNumber = TextEditingController(),
      _quantity = TextEditingController(text: '1'),
      _cost = TextEditingController(text: '0');
  String? _assignee;
  String _blockedCategory = 'other';
  @override
  void dispose() {
    for (final c in [_note, _description, _partNumber, _quantity, _cost]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final es = isSpanish(context);
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 16,
            children: [
              if (widget.action == 'block')
                AppDropdownField<String>(
                  initialValue: _blockedCategory,
                  decoration: InputDecoration(
                    labelText: es ? 'Esperando' : 'Waiting for',
                  ),
                  items: [
                    for (final key in blockedCategories.keys)
                      DropdownMenuItem(
                        value: key,
                        child: Text(
                          coordinationLabel(blockedCategories, key, es),
                        ),
                      ),
                  ],
                  onChanged: (value) => _blockedCategory = value!,
                ),
              if (widget.action == 'assign')
                AppDropdownField<String>(
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: es ? 'Responsable' : 'Assigned to',
                  ),
                  items: widget.assignees
                      .map(
                        (a) => DropdownMenuItem(
                          value: a['id'] as String,
                          child: Text(a['name'] as String),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => _assignee = v,
                  validator: (v) => v == null
                      ? (es
                            ? 'Selecciona un responsable'
                            : 'Select an assignee')
                      : null,
                )
              else if (widget.action == 'add_part') ...[
                TextFormField(
                  controller: _description,
                  decoration: InputDecoration(
                    labelText: es ? 'Descripción' : 'Description',
                  ),
                  validator: (v) => (v?.trim().length ?? 0) < 2
                      ? (es ? 'Requerido' : 'Required')
                      : null,
                ),
                TextFormField(
                  controller: _partNumber,
                  decoration: InputDecoration(
                    labelText: es ? 'Número de repuesto' : 'Part number',
                  ),
                ),
                TextFormField(
                  controller: _quantity,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: es ? 'Cantidad' : 'Quantity',
                  ),
                  validator: (v) =>
                      double.tryParse(v ?? '')?.isFinite != true ||
                          double.parse(v!) <= 0
                      ? (es
                            ? 'Ingresa una cantidad positiva'
                            : 'Enter a positive quantity')
                      : null,
                ),
                TextFormField(
                  controller: _cost,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: es ? 'Costo unitario (USD)' : 'Unit cost (USD)',
                  ),
                  validator: (v) =>
                      double.tryParse(v ?? '')?.isFinite != true ||
                          double.parse(v!) < 0
                      ? (es ? 'Ingresa un costo válido' : 'Enter a valid cost')
                      : null,
                ),
              ] else ...[
                if (widget.action == 'approve')
                  Text(
                    es
                        ? 'Completa el trabajo y actualiza únicamente su plan de servicio vinculado.'
                        : 'Completes this job and updates only its linked service plan.',
                  ),
                TextFormField(
                  controller: _note,
                  minLines: 2,
                  maxLines: 5,
                  decoration: InputDecoration(
                    labelText: es ? 'Motivo / nota' : 'Reason / note',
                  ),
                  validator: (v) =>
                      widget.action != 'approve' && (v?.trim().length ?? 0) < 3
                      ? (es ? 'Ingresa un motivo' : 'Enter a reason')
                      : null,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(es ? 'Cancelar' : 'Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            Navigator.pop(context, <String, dynamic>{
              if (widget.action == 'block')
                'blocked_category': _blockedCategory,
              if (widget.action == 'assign') 'assigned_to': _assignee,
              if (widget.action == 'add_part') ...{
                'description': _description.text,
                'part_number': _partNumber.text,
                'quantity': double.parse(_quantity.text),
                'unit_cost': double.parse(_cost.text),
              } else
                'note': _note.text.trim(),
            });
          },
          child: Text(es ? 'Confirmar' : 'Confirm'),
        ),
      ],
    );
  }
}
