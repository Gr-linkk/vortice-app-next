import 'maintenance_progress.dart';
import 'package:vortice_app/core/meter_units.dart';
import 'package:vortice_app/features/parts/work_parts_progress.dart';
import 'package:vortice_app/core/app_dropdown_field.dart';
import 'dart:convert';
import 'package:vortice_app/sync/field_work_provider.dart';
import 'package:vortice_app/features/coordination/coordination_entry.dart';
import 'package:vortice_app/features/coordination/coordination_labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/core/localized_text.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/checklists/checklist_answer_fields.dart';
import 'package:vortice_app/features/fleet/work_order_fault_card.dart';
import 'maintenance_models.dart';
import 'maintenance_report_screen.dart';
import 'maintenance_repository.dart';
import 'maintenance_refresh.dart';
import 'internal_work_order_edit_screen.dart';
import 'package:vortice_app/sync/online_action_gate.dart';

String _maintenanceJobText(
  BuildContext context,
  String english,
  String spanish,
  String french,
) => localizedText(context, english, spanish, french);

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
    if (['assign', 'approve', 'return', 'release'].contains(action) &&
        (!await requireOnlineAction(context, ref) || !mounted)) {
      return;
    }
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

  Future<void> _start(MaintenanceJob job) async {
    if (job.data['engine_id'] == null || job.data['started_at'] != null) {
      await _act(job, 'start');
      return;
    }
    var meter =
        job.data['current_meter']?.toString() ??
        job.data['hours_at_start']?.toString() ??
        '';
    final form = GlobalKey<FormState>();
    final unit = job.data['meter_unit'] as String? ?? 'hours';
    final reading = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          _maintenanceJobText(
            context,
            'Starting meter',
            'Medidor al iniciar',
            'Relevé initial',
          ),
        ),
        content: Form(
          key: form,
          child: TextFormField(
            initialValue: meter,
            onChanged: (value) => meter = value,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText:
                  '${_maintenanceJobText(context, 'Current reading', 'Lectura actual', 'Relevé actuel')} (${meterSymbol(unit)})',
            ),
            validator: (value) {
              final n = double.tryParse(value ?? '');
              return n == null || !n.isFinite || n < 0
                  ? _maintenanceJobText(
                      context,
                      'Enter a valid reading',
                      'Ingresa una lectura válida',
                      'Saisissez un relevé valide',
                    )
                  : null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              _maintenanceJobText(context, 'Cancel', 'Cancelar', 'Annuler'),
            ),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(context, double.parse(meter));
              }
            },
            child: Text(
              _maintenanceJobText(
                context,
                'Start work',
                'Iniciar trabajo',
                'Commencer le travail',
              ),
            ),
          ),
        ],
      ),
    );
    if (reading != null && mounted) {
      await _act(job, 'start', {'start_meter': reading, 'meter_unit': unit});
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
        costCurrency: job.costCurrency,
        assignees: maintenanceRows(catalog?['assignees']),
        approvalDescription: maintenanceApprovalDescription(
          job,
          isSpanish(context),
          french: isFrench(context),
        ),
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
        title: Text(
          localizedText(
            context,
            'Work order',
            'Orden de trabajo',
            'Bon de travail',
          ),
        ),
        actions: [
          IconButton(
            tooltip: _maintenanceJobText(
              context,
              'Refresh',
              'Actualizar',
              'Actualiser',
            ),
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
                Text(maintenanceError(e, es, french: isFrench(context))),
                TextButton(
                  onPressed: _refresh,
                  child: Text(
                    _maintenanceJobText(
                      context,
                      'Try again',
                      'Reintentar',
                      'Réessayer',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        data: (job) {
          if (job == null) {
            return Center(
              child: Text(
                _maintenanceJobText(
                  context,
                  'This work order is unavailable to your account.',
                  'Orden no disponible para tu cuenta.',
                  'Ce bon de travail n’est pas accessible avec votre compte.',
                ),
              ),
            );
          }
          final disabled =
              _busy || _pending != null || job.data['local_conflict'] == true;
          final userId = ref.watch(profileProvider).valueOrNull?.id;
          Widget info(String label, String? value) =>
              value == null || value.isEmpty
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text('$label: $value'),
                );
          final report = <Widget>[
            Text(
              job.status == 'pending_review'
                  ? (_maintenanceJobText(
                      context,
                      'Review service report',
                      'Revisar informe de servicio',
                      'Examiner le rapport d’entretien',
                    ))
                  : (_maintenanceJobText(
                      context,
                      'Saved report',
                      'Informe guardado',
                      'Rapport enregistré',
                    )),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            info(
              _maintenanceJobText(
                context,
                'Findings',
                'Hallazgos',
                'Constatations',
              ),
              job.report['diagnosis'] as String?,
            ),
            info(
              _maintenanceJobText(
                context,
                'Work performed',
                'Trabajo realizado',
                'Travaux effectués',
              ),
              job.report['repair'] as String?,
            ),
            info(
              _maintenanceJobText(context, 'Notes', 'Notas', 'Notes'),
              job.report['notes'] as String?,
            ),
            if (job.data['inspection_id'] != null) ...[
              Text(
                _maintenanceJobText(
                  context,
                  'Inspection certificate',
                  'Certificado de inspección',
                  'Certificat d’inspection',
                ),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              info(
                _maintenanceJobText(
                  context,
                  'Inspection date',
                  'Fecha de inspección',
                  'Date d’inspection',
                ),
                (job.data['inspection_result'] as Map?)?['inspected_on']
                    as String?,
              ),
              info(
                _maintenanceJobText(
                  context,
                  'Next expiry',
                  'Próximo vencimiento',
                  'Prochaine échéance',
                ),
                (job.data['inspection_result'] as Map?)?['expires_on']
                    as String?,
              ),
              info(
                _maintenanceJobText(
                  context,
                  'Procedure performed',
                  'Procedimiento aplicado',
                  'Procédure appliquée',
                ),
                (job.data['inspection_result'] as Map?)?['procedure_notes']
                    as String?,
              ),
              info(
                _maintenanceJobText(
                  context,
                  'Inspection result',
                  'Resultado de inspección',
                  'Résultat de l’inspection',
                ),
                (job.data['inspection_result'] as Map?)?['result_notes']
                    as String?,
              ),
            ],
            info(
              _maintenanceJobText(
                context,
                'Completion meter',
                'Horas al finalizar',
                'Relevé final',
              ),
              job.data['hours_at_end'] == null
                  ? null
                  : formatMeter(
                      job.data['hours_at_end'] as num?,
                      job.data['meter_unit'] as String?,
                    ),
            ),
            if (job.data['checklist_template_version'] != null)
              info(
                _maintenanceJobText(
                  context,
                  'Checklist',
                  'Lista de revisión',
                  'Liste de contrôle',
                ),
                '${job.data['checklist_template_name']} · v${job.data['checklist_template_version']}',
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
                subtitle: Text(
                  [
                    switch ((job.answers[item['id']] as Map?)?['result']) {
                      'pass' => _maintenanceJobText(
                        context,
                        'Pass',
                        'Correcto',
                        'Conforme',
                      ),
                      'fail' => _maintenanceJobText(
                        context,
                        'Fail',
                        'Falla',
                        'Échec',
                      ),
                      'na' => _maintenanceJobText(
                        context,
                        'Not applicable',
                        'No aplica',
                        'Sans objet',
                      ),
                      _ => _maintenanceJobText(
                        context,
                        'Unanswered',
                        'Sin responder',
                        'Sans réponse',
                      ),
                    },
                    checklistRecordedValue(
                      Map<String, dynamic>.from(
                        item['definition'] as Map? ?? {},
                      ),
                      (job.answers[item['id']] as Map?)?['note'] as String?,
                    ),
                  ].where((s) => s.isNotEmpty).join('\n'),
                ),
              ),
            for (final path in job.evidence) MaintenanceEvidence(path: path),
            if (job.canManage &&
                job.canWork &&
                job.status == 'pending_review') ...[
              const OnlineOnlyNotice(),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: disabled
                    ? null
                    : () => _formAction(
                        job,
                        'approve',
                        _maintenanceJobText(
                          context,
                          'Approve & complete',
                          'Aprobar y completar',
                          'Approuver et terminer',
                        ),
                      ),
                child: Text(
                  _maintenanceJobText(
                    context,
                    'Approve & complete',
                    'Aprobar y completar',
                    'Approuver et terminer',
                  ),
                ),
              ),
              TextButton(
                onPressed: disabled
                    ? null
                    : () => _formAction(
                        job,
                        'return',
                        _maintenanceJobText(
                          context,
                          'Return for changes',
                          'Devolver para cambios',
                          'Retourner pour corrections',
                        ),
                      ),
                child: Text(
                  _maintenanceJobText(
                    context,
                    'Return for changes',
                    'Devolver para cambios',
                    'Retourner pour corrections',
                  ),
                ),
              ),
            ],
          ];
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (job.data['local_pending'] == true)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _maintenanceJobText(
                      context,
                      'Saved on this device. Check upload status above.',
                      'Guardado en este dispositivo. Revisa el estado de sincronización arriba.',
                      'Enregistré sur cet appareil. Vérifiez l’état de synchronisation ci-dessus.',
                    ),
                  ),
                ),
              Text(job.title, style: Theme.of(context).textTheme.headlineSmall),
              Text(
                localizedText(
                  context,
                  'Work order',
                  'Orden de trabajo',
                  'Bon de travail',
                ),
              ),
              TextButton.icon(
                onPressed: () =>
                    context.push('/maintenance/assets/${job.assetId}'),
                icon: const Icon(Icons.precision_manufacturing_outlined),
                label: Text(job.assetName),
              ),
              WorkOrderFaultCard(workOrderId: job.id, assetId: job.assetId),
              WorkPartsProgress(jobId: job.id),
              if (job.data['generation_kind'] == 'recurring')
                Text(
                  _maintenanceJobText(
                    context,
                    'Created automatically by the maintenance schedule.',
                    'Creada automáticamente por el programa de mantenimiento.',
                    'Créé automatiquement par le programme d’entretien.',
                  ),
                ),
              if ((job.data['cycle'] as Map?)?['due_meter'] != null)
                info(
                  _maintenanceJobText(
                    context,
                    'Due meter',
                    'Objetivo del medidor',
                    'Relevé prévu',
                  ),
                  formatMeter(
                    (job.data['cycle'] as Map)['due_meter'] as num?,
                    job.data['meter_unit'] as String?,
                  ),
                ),
              for (final source in maintenanceRows(job.data['sources']))
                if (source['source_kind'] == 'fault')
                  TextButton.icon(
                    onPressed: () =>
                        context.push('/fleet/faults/${source['source_id']}'),
                    icon: const Icon(Icons.link),
                    label: Text(
                      _maintenanceJobText(
                        context,
                        'Open source fault',
                        'Abrir falla de origen',
                        'Ouvrir la défaillance source',
                      ),
                    ),
                  ),
              for (final fault in maintenanceRows(job.data['checklist_faults']))
                TextButton.icon(
                  onPressed: () =>
                      context.push('/fleet/faults/${fault['fault_id']}'),
                  icon: const Icon(Icons.flag_outlined),
                  label: Text(
                    _maintenanceJobText(
                      context,
                      'Open checklist-step fault',
                      'Abrir falla del paso de la lista',
                      'Ouvrir la défaillance liée à l’étape.',
                    ),
                  ),
                ),
              if (job.checklist.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '${_maintenanceJobText(context, 'Checklist', 'Lista', 'Liste de contrôle')}: ${maintenanceCompletedItems(job.checklist, job.answers, job.evidence)} / ${job.checklist.length} ${_maintenanceJobText(context, 'steps complete', 'pasos completos', 'étapes terminées')}',
                  ),
                ),
              if (job.data['hours_at_start'] != null)
                info(
                  _maintenanceJobText(
                    context,
                    'Starting meter',
                    'Medidor al iniciar',
                    'Relevé initial',
                  ),
                  formatMeter(
                    job.data['hours_at_start'] as num?,
                    job.data['meter_unit'] as String?,
                  ),
                ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    label: Text(
                      job.lifecycleLabel(es, french: isFrench(context)),
                    ),
                  ),
                  Chip(
                    label: Text(
                      maintenancePriority(
                        job.priority,
                        es,
                        french: isFrench(context),
                      ),
                    ),
                  ),
                  Chip(
                    label: Text(job.workType.label(es, fr: isFrench(context))),
                  ),
                  if (job.isService)
                    Chip(
                      label: Text(
                        _maintenanceJobText(
                          context,
                          'Scheduled service',
                          'Servicio programado',
                          'Entretien planifié',
                        ),
                      ),
                    ),
                ],
              ),
              info(
                _maintenanceJobText(
                  context,
                  'Assigned to',
                  'Responsable',
                  'Assigné à',
                ),
                job.data['assignee_name'] as String? ??
                    (_maintenanceJobText(
                      context,
                      'Unassigned',
                      'Sin asignar',
                      'Non assigné',
                    )),
              ),
              if (job.data['planned_start'] != null)
                info(
                  _maintenanceJobText(
                    context,
                    'Booked start',
                    'Inicio programado',
                    'Début planifié',
                  ),
                  maintenanceDate(
                    job.data['planned_start'] as String,
                    es,
                    french: isFrench(context),
                  ),
                ),
              if (job.data['estimated_minutes'] != null)
                info(
                  _maintenanceJobText(
                    context,
                    'Estimated duration',
                    'Duración estimada',
                    'Durée estimée',
                  ),
                  '${job.data['estimated_minutes']} min',
                ),
              if (job.data['can_schedule'] == true &&
                  !['closed', 'pending_review'].contains(job.status))
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: disabled
                        ? null
                        : () => context.push(
                            '/maintenance/planning?jobId=${job.id}',
                          ),
                    icon: const Icon(Icons.edit_calendar_outlined),
                    label: Text(
                      _maintenanceJobText(
                        context,
                        'Review schedule',
                        'Revisar planificación',
                        'Vérifier la planification',
                      ),
                    ),
                  ),
                ),
              if (job.dueDate != null)
                info(
                  _maintenanceJobText(
                    context,
                    'Due date',
                    'Fecha límite',
                    'Date d’échéance',
                  ),
                  maintenanceDate(job.dueDate, es, french: isFrench(context)),
                ),
              info(
                _maintenanceJobText(
                  context,
                  'Component',
                  'Componente',
                  'Composant',
                ),
                job.data['component_name'] as String?,
              ),
              info(
                _maintenanceJobText(
                  context,
                  'Instructions',
                  'Instrucciones',
                  'Instructions',
                ),
                job.data['description'] as String?,
              ),
              info(
                _maintenanceJobText(
                  context,
                  'Expected parts / materials',
                  'Repuestos y materiales previstos',
                  'Pièces et matériaux prévus',
                ),
                job.expectedMaterials,
              ),
              if (job.canPrepare)
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: disabled
                        ? null
                        : () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    InternalWorkOrderEditScreen(job: job),
                              ),
                            );
                            if (mounted) _refresh();
                          },
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(
                      localizedText(
                        context,
                        'Edit work order',
                        'Editar orden de trabajo',
                        'Modifier le bon de travail',
                      ),
                    ),
                  ),
                ),
              info(
                _maintenanceJobText(
                  context,
                  'Blocked reason',
                  'Motivo del bloqueo',
                  'Motif du blocage',
                ),
                job.data['on_hold_reason'] as String?,
              ),
              info(
                _maintenanceJobText(
                  context,
                  'Review note',
                  'Revisión',
                  'Note de révision',
                ),
                job.data['review_note'] as String?,
              ),
              if (job.data['parent_job_id'] != null)
                TextButton(
                  onPressed: () => context.push(
                    '/maintenance/jobs/${job.data['parent_job_id']}',
                  ),
                  child: Text(
                    _maintenanceJobText(
                      context,
                      'View preceding job',
                      'Ver trabajo anterior',
                      'Voir le bon de travail précédent',
                    ),
                  ),
                ),
              if (!job.canWork)
                Text(
                  _maintenanceJobText(
                    context,
                    'History is available; execution is disabled.',
                    'Historial disponible; la ejecución está deshabilitada.',
                    'L’historique est disponible; l’exécution est désactivée.',
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    maintenanceError(_error!, es, french: isFrench(context)),
                  ),
                ),
              if (_pending != null)
                FilledButton(
                  onPressed: _busy ? null : () => _act(job, _action!),
                  child: Text(
                    _maintenanceJobText(
                      context,
                      'Retry the same action',
                      'Reintentar la misma acción',
                      'Réessayer la même action',
                    ),
                  ),
                ),
              if (_busy) const LinearProgressIndicator(),
              if (job.canManage && job.canWork && job.status == 'draft')
                FilledButton.icon(
                  onPressed: disabled
                      ? null
                      : () => _formAction(
                          job,
                          'assign',
                          localizedText(
                            context,
                            'Assign work order',
                            'Asignar orden de trabajo',
                            'Attribuer le bon de travail',
                          ),
                        ),
                  icon: const Icon(Icons.person_add_alt),
                  label: Text(
                    localizedText(
                      context,
                      'Assign work order',
                      'Asignar orden de trabajo',
                      'Attribuer le bon de travail',
                    ),
                  ),
                ),
              if (job.canWork && job.status == 'assigned') ...[
                Text(
                  _maintenanceJobText(
                    context,
                    'Start your labour timer, then complete the service report.',
                    'Inicia el tiempo de trabajo; después completa el informe de servicio.',
                    'Démarrez votre temps de travail, puis remplissez le rapport d’entretien.',
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: disabled ? null : () => _start(job),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(
                    _maintenanceJobText(
                      context,
                      'Start work',
                      'Iniciar trabajo',
                      'Commencer le travail',
                    ),
                  ),
                ),
              ],
              if (job.canEdit)
                FilledButton.icon(
                  onPressed: disabled
                      ? null
                      : () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute<bool>(
                              builder: (_) => MaintenanceReportScreen(job: job),
                            ),
                          );
                          if (mounted) _refresh();
                        },
                  icon: const Icon(Icons.edit_note),
                  label: Text(
                    job.report.isEmpty
                        ? _maintenanceJobText(
                            context,
                            'Create service report',
                            'Crear informe de servicio',
                            'Créer un rapport d’entretien',
                          )
                        : _maintenanceJobText(
                            context,
                            'Continue service report',
                            'Continuar informe de servicio',
                            'Continuer le rapport d’entretien',
                          ),
                  ),
                ),
              if (job.status == 'pending_review') ...report,
              if (job.canWork &&
                  (job.canManage ||
                      ['assigned', 'in_progress'].contains(job.status)))
                Align(
                  alignment: Alignment.centerLeft,
                  child: PopupMenuButton<String>(
                    enabled: !disabled,
                    tooltip: _maintenanceJobText(
                      context,
                      'More actions',
                      'Más acciones',
                      'Plus d’actions',
                    ),
                    onSelected: (action) {
                      if (action == 'follow_up') {
                        context.push(
                          '/maintenance/new?assetId=${job.assetId}&parentJobId=${job.id}',
                        );
                      } else {
                        _formAction(job, action, switch (action) {
                          'assign' => _maintenanceJobText(
                            context,
                            'Assign job',
                            'Asignar trabajo',
                            'Attribuer le travail',
                          ),
                          'block' => _maintenanceJobText(
                            context,
                            'Block work',
                            'Bloquear trabajo',
                            'Bloquer le travail',
                          ),
                          _ => _maintenanceJobText(
                            context,
                            'Reopen job',
                            'Reabrir trabajo',
                            'Rouvrir le travail',
                          ),
                        });
                      }
                    },
                    itemBuilder: (_) => [
                      if (job.canManage &&
                          ![
                            'draft',
                            'closed',
                            'pending_review',
                          ].contains(job.status))
                        PopupMenuItem(
                          value: 'assign',
                          child: Text(
                            _maintenanceJobText(
                              context,
                              'Assign job',
                              'Asignar trabajo',
                              'Attribuer le travail',
                            ),
                          ),
                        ),
                      if (['assigned', 'in_progress'].contains(job.status))
                        PopupMenuItem(
                          value: 'block',
                          child: Text(
                            _maintenanceJobText(
                              context,
                              'Block work',
                              'Bloquear trabajo',
                              'Bloquer le travail',
                            ),
                          ),
                        ),
                      if (job.canManage && job.status == 'closed')
                        PopupMenuItem(
                          value: 'reopen',
                          child: Text(
                            _maintenanceJobText(
                              context,
                              'Reopen job',
                              'Reabrir trabajo',
                              'Rouvrir le travail',
                            ),
                          ),
                        ),
                      if (job.canManage)
                        PopupMenuItem(
                          value: 'follow_up',
                          child: Text(
                            _maintenanceJobText(
                              context,
                              'Create follow-up job',
                              'Crear seguimiento',
                              'Créer un bon de travail de suivi',
                            ),
                          ),
                        ),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.more_horiz),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              _maintenanceJobText(
                                context,
                                'More actions',
                                'Más acciones',
                                'Plus d’actions',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              CoordinationEntry(
                compact: true,
                assetId: job.assetId,
                kind: 'job',
                subjectId: job.id,
              ),
              Text(
                _maintenanceJobText(
                  context,
                  'Labour',
                  'Mano de obra',
                  'Main-d’œuvre',
                ),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (job.canWork &&
                  ['in_progress', 'on_hold'].contains(job.status) &&
                  !job.labour.any(
                    (s) => s['actor_id'] == userId && s['stopped_at'] == null,
                  ))
                OutlinedButton.icon(
                  onPressed: disabled ? null : () => _start(job),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(
                    _maintenanceJobText(
                      context,
                      'Start labour',
                      'Iniciar tiempo',
                      'Démarrer le temps de travail',
                    ),
                  ),
                ),
              for (final session in job.labour)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    maintenanceDate(
                      session['started_at'] as String?,
                      es,
                      french: isFrench(context),
                    ),
                  ),
                  subtitle: Text(
                    session['stopped_at'] == null
                        ? (_maintenanceJobText(
                            context,
                            'Running',
                            'En curso',
                            'En cours',
                          ))
                        : maintenanceDate(
                            session['stopped_at'] as String?,
                            es,
                            french: isFrench(context),
                          ),
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
                          child: Text(
                            _maintenanceJobText(
                              context,
                              'Pause',
                              'Pausar',
                              'Mettre en pause',
                            ),
                          ),
                        )
                      : null,
                ),
              Text(
                '${job.completedLabourHours.toStringAsFixed(2)} ${_maintenanceJobText(context, 'recorded hours', 'horas registradas', 'heures enregistrées')}',
              ),
              const SizedBox(height: 20),
              Text(
                _maintenanceJobText(
                  context,
                  'Parts used',
                  'Repuestos utilizados',
                  'Pièces utilisées',
                ),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (job.canEdit)
                OutlinedButton(
                  onPressed: disabled
                      ? null
                      : () => _formAction(
                          job,
                          'add_part',
                          _maintenanceJobText(
                            context,
                            'Add part',
                            'Añadir repuesto',
                            'Ajouter une pièce',
                          ),
                        ),
                  child: Text(
                    _maintenanceJobText(
                      context,
                      'Add part',
                      'Añadir repuesto',
                      'Ajouter une pièce',
                    ),
                  ),
                ),
              for (final part in job.parts)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(part['description'] as String),
                  subtitle: Text(
                    '${part['quantity']} × ${part['unit_cost']} ${job.costCurrency}',
                  ),
                  trailing: job.canEdit && part['stock_requirement_id'] == null
                      ? IconButton(
                          tooltip: _maintenanceJobText(
                            context,
                            'Remove part',
                            'Quitar repuesto',
                            'Retirer la pièce',
                          ),
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
                '${_maintenanceJobText(context, 'Internal cost', 'Costo interno', 'Coût interne')}: ${(job.labourCost + job.partsCost).toStringAsFixed(2)} ${job.costCurrency}',
              ),
              Text(
                _maintenanceJobText(
                  context,
                  'Labour and parts; no customer billing.',
                  'Mano de obra y repuestos; sin facturación al cliente.',
                  'Main-d’œuvre et pièces; aucune facturation au client.',
                ),
              ),
              const SizedBox(height: 24),
              if (job.status != 'pending_review') ...report,
              if (job.data['service_applied_at'] != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    _maintenanceJobText(
                      context,
                      'The next service was updated. Reopening this job will not advance it again.',
                      'El próximo servicio ya se actualizó. Reabrir este trabajo no lo avanza de nuevo.',
                      'Le prochain entretien a déjà été mis à jour. La réouverture de ce bon de travail ne le fera pas avancer une deuxième fois.',
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              Text(
                _maintenanceJobText(
                  context,
                  'History',
                  'Historial',
                  'Historique',
                ),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              for (final event in maintenanceRows(job.data['events']))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${maintenanceEvent(event['kind'] as String, es, french: isFrench(context))} · ${event['actor_name'] ?? ''}',
                  ),
                  subtitle: Text(
                    '${maintenanceDate(event['created_at'] as String?, es, french: isFrench(context))}${event['note'] == null ? '' : '\n${event['note']}'}',
                  ),
                ),
              const SizedBox(height: 24),
              Text(
                _maintenanceJobText(
                  context,
                  'Asset availability and fault resolution are reviewed separately.',
                  'La disponibilidad del equipo y el cierre de fallas se revisan por separado.',
                  'La disponibilité de l’équipement et la résolution des défaillances sont vérifiées séparément.',
                ),
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
  Future<String>? _url;

  @override
  Widget build(BuildContext context) {
    final operations = ref.watch(fieldOperationsProvider);
    // Restore the local outbox before deciding that a photo needs the network.
    if (operations.isLoading && !operations.hasValue) {
      return const LinearProgressIndicator();
    }
    final local = (operations.valueOrNull ?? [])
        .where(
          (r) =>
              r.kind == 'upload' &&
              r.payload['bucket'] == 'maintenance-evidence' &&
              r.payload['path'] == widget.path,
        )
        .firstOrNull;
    if (local != null) {
      return Image.memory(
        base64Decode(local.payload['bytes'] as String),
        height: 220,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Text(
          _maintenanceJobText(
            context,
            'Photo unavailable',
            'Foto no disponible',
            'Photo indisponible',
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: FutureBuilder<String>(
        // Pending/local evidence needs no signed URL. Start this request only
        // when a FutureBuilder will observe it, including its offline errors.
        future: _url ??= ref
            .read(maintenanceRepositoryProvider)
            .evidenceUrl(widget.path),
        builder: (context, result) {
          if (result.hasError) {
            return TextButton(
              onPressed: () => setState(
                () => _url = ref
                    .read(maintenanceRepositoryProvider)
                    .evidenceUrl(widget.path),
              ),
              child: Text(
                _maintenanceJobText(
                  context,
                  'Retry photo',
                  'Reintentar foto',
                  'Réessayer la photo',
                ),
              ),
            );
          }
          if (!result.hasData) return const LinearProgressIndicator();
          return Image.network(
            result.data!,
            height: 220,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Text(
              _maintenanceJobText(
                context,
                'Photo unavailable',
                'Foto no disponible',
                'Photo indisponible',
              ),
            ),
          );
        },
      ),
    );
  }
}

class _JobActionDialog extends StatefulWidget {
  const _JobActionDialog({
    required this.action,
    required this.title,
    required this.assignees,
    required this.approvalDescription,
    required this.costCurrency,
  });
  final String action, title;
  final String approvalDescription;
  final String costCurrency;
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
                    labelText: _maintenanceJobText(
                      context,
                      'Waiting for',
                      'Esperando',
                      'En attente de',
                    ),
                  ),
                  items: [
                    for (final key in blockedCategories.keys)
                      DropdownMenuItem(
                        value: key,
                        child: Text(
                          coordinationLabel(
                            blockedCategories,
                            key,
                            es,
                            french: isFrench(context),
                          ),
                        ),
                      ),
                  ],
                  onChanged: (value) => _blockedCategory = value!,
                ),
              if (widget.action == 'assign')
                AppDropdownField<String>(
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: _maintenanceJobText(
                      context,
                      'Assigned to',
                      'Responsable',
                      'Assigné à',
                    ),
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
                      ? (_maintenanceJobText(
                          context,
                          'Select an assignee',
                          'Selecciona un responsable',
                          'Sélectionnez une personne responsable.',
                        ))
                      : null,
                )
              else if (widget.action == 'add_part') ...[
                TextFormField(
                  controller: _description,
                  decoration: InputDecoration(
                    labelText: _maintenanceJobText(
                      context,
                      'Description',
                      'Descripción',
                      'Description',
                    ),
                  ),
                  validator: (v) => (v?.trim().length ?? 0) < 2
                      ? (_maintenanceJobText(
                          context,
                          'Required',
                          'Requerido',
                          'Obligatoire',
                        ))
                      : null,
                ),
                TextFormField(
                  controller: _partNumber,
                  decoration: InputDecoration(
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                    labelText: _maintenanceJobText(
                      context,
                      'Part number',
                      'Número de repuesto',
                      'Numéro de pièce',
                    ),
                  ),
                ),
                TextFormField(
                  controller: _quantity,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: _maintenanceJobText(
                      context,
                      'Quantity',
                      'Cantidad',
                      'Quantité',
                    ),
                  ),
                  validator: (v) =>
                      double.tryParse(v ?? '')?.isFinite != true ||
                          double.parse(v!) <= 0
                      ? (_maintenanceJobText(
                          context,
                          'Enter a positive quantity',
                          'Ingresa una cantidad positiva',
                          'Saisissez une quantité positive.',
                        ))
                      : null,
                ),
                TextFormField(
                  controller: _cost,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: _maintenanceJobText(
                      context,
                      'Unit cost (${widget.costCurrency})',
                      'Costo unitario (${widget.costCurrency})',
                      'Coût unitaire (${widget.costCurrency})',
                    ),
                  ),
                  validator: (v) =>
                      double.tryParse(v ?? '')?.isFinite != true ||
                          double.parse(v!) < 0
                      ? _maintenanceJobText(
                          context,
                          'Enter a valid cost',
                          'Ingresa un costo válido',
                          'Saisissez un coût valide',
                        )
                      : null,
                ),
              ] else ...[
                if (widget.action == 'approve')
                  Text(widget.approvalDescription),
                TextFormField(
                  controller: _note,
                  minLines: 2,
                  maxLines: 5,
                  decoration: InputDecoration(
                    labelText: _maintenanceJobText(
                      context,
                      'Reason / note',
                      'Motivo / nota',
                      'Motif / note',
                    ),
                  ),
                  validator: (v) =>
                      widget.action != 'approve' && (v?.trim().length ?? 0) < 3
                      ? _maintenanceJobText(
                          context,
                          'Enter a reason',
                          'Ingresa un motivo',
                          'Saisissez un motif',
                        )
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
          child: Text(
            _maintenanceJobText(context, 'Cancel', 'Cancelar', 'Annuler'),
          ),
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
          child: Text(
            _maintenanceJobText(context, 'Confirm', 'Confirmar', 'Confirmer'),
          ),
        ),
      ],
    );
  }
}
