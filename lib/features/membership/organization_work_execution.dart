import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:vortice_app/core/app_dropdown_field.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/meter_units.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/checklists/checklist_answer_fields.dart';
import 'package:vortice_app/features/checklists/checklist_procedure_source.dart';
import 'package:vortice_app/features/maintenance/maintenance_models.dart';
import 'package:vortice_app/features/maintenance/maintenance_progress.dart';
import 'organization_work_provider.dart';

class OrganizationWorkExecution extends ConsumerStatefulWidget {
  const OrganizationWorkExecution({
    super.key,
    required this.data,
    required this.busy,
    required this.onAction,
    required this.onReport,
    required this.onPrepare,
  });
  final Map<String, dynamic> data;
  final bool busy;
  final void Function(String) onAction;
  final VoidCallback onReport, onPrepare;
  @override
  ConsumerState<OrganizationWorkExecution> createState() =>
      _OrganizationWorkExecutionState();
}

class _OrganizationWorkExecutionState
    extends ConsumerState<OrganizationWorkExecution> {
  @override
  Widget build(BuildContext context) {
    final es = isSpanish(context), data = widget.data;
    final order = Map<String, dynamic>.from(data['work_order'] as Map);
    final status = order['status'];
    final active = const ['in_progress', 'on_hold'].contains(status);
    final work = data['can_work'] == true;
    final actor = ref.watch(sessionProvider)?.user.id;
    final labour = maintenanceRows(data['labour']);
    final ownRunning = labour.any(
      (row) => row['actor_id'] == actor && row['stopped_at'] == null,
    );
    final items = maintenanceRows(data['checklist_snapshot']);
    final answers = Map<String, dynamic>.from(data['answers'] as Map? ?? {});
    final evidence = (data['evidence_paths'] as List? ?? []).cast<String>();
    final completed = maintenanceCompletedItems(items, answers, evidence);
    final canPrepare =
        data['can_manage'] == true &&
        order['started_at'] == null &&
        const ['draft', 'assigned'].contains(status);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              es ? 'Trabajo y progreso' : 'Work and progress',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (items.isNotEmpty) ...[
              Text(
                '${data['checklist_name'] ?? (es ? 'Lista adjunta' : 'Attached checklist')} · $completed / ${items.length}',
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: completed / items.length),
            ],
            if ((data['procedure_notes']?.toString() ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(data['procedure_notes'].toString()),
              ),
            if (order['scheduled_date'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  '${es ? 'Visita programada' : 'Service booking'}: ${maintenanceDate(order['scheduled_date'].toString(), es)}',
                ),
              ),
            if (order['hours_at_start'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${es ? 'Medidor al iniciar' : 'Starting meter'}: ${formatMeter(order['hours_at_start'] as num?, order['meter_unit'] as String?)}',
                ),
              ),
            if ((order['on_hold_reason']?.toString() ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  '${es ? 'Bloqueado' : 'Blocked'}: ${order['on_hold_reason']}',
                ),
              ),
            if (canPrepare)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: OutlinedButton.icon(
                  onPressed: widget.busy ? null : widget.onPrepare,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: Text(
                    es
                        ? 'Preparar trabajo y procedimiento'
                        : 'Prepare work and procedure',
                  ),
                ),
              ),
            if (work && (status == 'assigned' || active)) ...[
              const SizedBox(height: 16),
              if (!active)
                FilledButton.icon(
                  onPressed: widget.busy
                      ? null
                      : () => widget.onAction('start'),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(es ? 'Iniciar trabajo' : 'Start work'),
                ),
              if (active) ...[
                OutlinedButton.icon(
                  onPressed: widget.busy
                      ? null
                      : () => widget.onAction(ownRunning ? 'pause' : 'resume'),
                  icon: Icon(ownRunning ? Icons.pause : Icons.play_arrow),
                  label: Text(
                    ownRunning
                        ? (es ? 'Pausar mi tiempo' : 'Pause my labour')
                        : (es ? 'Iniciar mi tiempo' : 'Start my labour'),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: widget.busy ? null : widget.onReport,
                  icon: const Icon(Icons.edit_note),
                  label: Text(
                    es
                        ? 'Continuar informe de servicio'
                        : 'Continue service report',
                  ),
                ),
                TextButton.icon(
                  onPressed: widget.busy
                      ? null
                      : () => widget.onAction('block'),
                  icon: const Icon(Icons.pause_circle_outline),
                  label: Text(es ? 'Registrar bloqueo' : 'Record a blocker'),
                ),
              ],
            ],
            const SizedBox(height: 12),
            OrganizationWorkLabour(data: data),
            if (items.isNotEmpty && !active) ...[
              const SizedBox(height: 12),
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (es ? item['description_es'] : null)?.toString() ??
                            item['description_en']?.toString() ??
                            '',
                      ),
                      Text(
                        '${(answers[item['id']] as Map?)?['result'] ?? (es ? 'Pendiente' : 'Pending')} ${checklistRecordedValue(Map<String, dynamic>.from(item['definition'] as Map? ?? {}), (answers[item['id']] as Map?)?['note']?.toString())}',
                      ),
                      ChecklistProcedureLink(item: item),
                    ],
                  ),
                ),
            ],
            if (evidence.isNotEmpty && !active)
              OrganizationWorkEvidence(paths: evidence),
          ],
        ),
      ),
    );
  }
}

class OrganizationWorkLabour extends StatefulWidget {
  const OrganizationWorkLabour({super.key, required this.data});
  final Map<String, dynamic> data;
  @override
  State<OrganizationWorkLabour> createState() => _OrganizationWorkLabourState();
}

class _OrganizationWorkLabourState extends State<OrganizationWorkLabour> {
  Timer? _ticker;
  @override
  void initState() {
    super.initState();
    _tick();
  }

  @override
  void didUpdateWidget(covariant OrganizationWorkLabour oldWidget) {
    super.didUpdateWidget(oldWidget);
    _tick();
  }

  void _tick() {
    _ticker?.cancel();
    if (maintenanceRows(
      widget.data['labour'],
    ).any((row) => row['stopped_at'] == null)) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final es = isSpanish(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${es ? 'Tiempo registrado' : 'Recorded labour'}: ${(widget.data['labour_hours'] as num? ?? 0).toStringAsFixed(2)} h',
        ),
        for (final row in maintenanceRows(widget.data['labour']))
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _sessionLabel(row, es),
              key: ValueKey('labour-${row['id']}'),
            ),
          ),
      ],
    );
  }

  String _sessionLabel(Map<String, dynamic> row, bool es) {
    final start = DateTime.tryParse(row['started_at']?.toString() ?? '');
    final stopped = DateTime.tryParse(row['stopped_at']?.toString() ?? '');
    final seconds = start == null
        ? 0
        : (stopped ?? DateTime.now())
              .difference(start)
              .inSeconds
              .clamp(0, 99999999);
    final duration =
        '${seconds ~/ 3600}:${((seconds % 3600) ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
    return '${row['actor_name'] ?? (es ? 'Persona' : 'Teammate')} · $duration · ${stopped == null ? (es ? 'En curso' : 'Running') : (es ? 'Registrado' : 'Recorded')}';
  }
}

class OrganizationWorkEvidence extends ConsumerWidget {
  const OrganizationWorkEvidence({super.key, required this.paths});
  final List<String> paths;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (var i = 0; i < paths.length; i++)
        OutlinedButton.icon(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => _EvidenceDialog(
              path: paths[i],
              repository: ref.read(organizationWorkRepositoryProvider),
            ),
          ),
          icon: const Icon(Icons.photo_outlined),
          label: Text('${isSpanish(context) ? 'Foto' : 'Photo'} ${i + 1}'),
        ),
    ],
  );
}

class _EvidenceDialog extends StatefulWidget {
  const _EvidenceDialog({required this.path, required this.repository});
  final String path;
  final OrganizationWorkRepository repository;
  @override
  State<_EvidenceDialog> createState() => _EvidenceDialogState();
}

class _EvidenceDialogState extends State<_EvidenceDialog> {
  late final Future<Uint8List> _image = widget.repository.evidence(widget.path);
  @override
  Widget build(BuildContext context) => Dialog(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: FutureBuilder<Uint8List>(
              future: _image,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text(friendlyError(context, snapshot.error!));
                }
                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  );
                }
                return InteractiveViewer(
                  child: Image.memory(snapshot.data!, fit: BoxFit.contain),
                );
              },
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(isSpanish(context) ? 'Cerrar' : 'Close'),
          ),
        ],
      ),
    ),
  );
}

class OrganizationWorkSetupSheet extends StatefulWidget {
  const OrganizationWorkSetupSheet({super.key, required this.data});
  final Map<String, dynamic> data;
  @override
  State<OrganizationWorkSetupSheet> createState() =>
      _OrganizationWorkSetupSheetState();
}

class _OrganizationWorkSetupSheetState
    extends State<OrganizationWorkSetupSheet> {
  late final _notes = TextEditingController(
    text: widget.data['procedure_notes']?.toString() ?? '',
  );
  late final _date = TextEditingController(
    text:
        (widget.data['work_order'] as Map)['scheduled_date']?.toString() ?? '',
  );
  late String? _template =
      (widget.data['work_order'] as Map)['checklist_template_id'] as String?;
  String? _error;
  @override
  void dispose() {
    _notes.dispose();
    _date.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final es = isSpanish(context);
    final order = widget.data['work_order'] as Map;
    final frozen = order['parts_kit_captured'] == true;
    final templates = maintenanceRows(widget.data['templates']);
    if (_template != null && !templates.any((row) => row['id'] == _template)) {
      templates.add({
        'id': _template,
        'name':
            widget.data['checklist_name'] ??
            (es ? 'Procedimiento guardado' : 'Saved procedure'),
        'version': order['checklist_template_version'] ?? '',
      });
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              es ? 'Preparar trabajo' : 'Prepare work',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            AppDropdownField<String>(
              isExpanded: true,
              initialValue: _template ?? '',
              decoration: InputDecoration(
                labelText: es ? 'Procedimiento adjunto' : 'Attached procedure',
              ),
              items: [
                DropdownMenuItem(
                  value: '',
                  child: Text(
                    es ? 'Sin lista adjunta' : 'No attached checklist',
                  ),
                ),
                for (final row in templates)
                  DropdownMenuItem(
                    value: row['id'] as String,
                    child: Text('${row['name']} · v${row['version']}'),
                  ),
              ],
              onChanged: frozen
                  ? null
                  : (value) =>
                        setState(() => _template = value == '' ? null : value),
            ),
            if (frozen)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  es
                      ? 'Esta orden ya guardó su kit de piezas. Crea otro trabajo para usar otra lista. La fecha y las instrucciones adicionales se pueden actualizar.'
                      : 'This work already captured its parts kit. Create separate work to use another checklist. The booking and additional instructions can still be updated.',
                ),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _notes,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: es
                    ? 'Instrucciones para este trabajo'
                    : 'Instructions for this work',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _date,
              readOnly: true,
              decoration: InputDecoration(
                labelText: es
                    ? 'Fecha de visita (opcional)'
                    : 'Service booking (optional)',
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _date.clear()),
                  icon: const Icon(Icons.clear),
                  tooltip: es ? 'Quitar fecha' : 'Clear booking',
                ),
              ),
              onTap: () async {
                final now = DateTime.now();
                final date = await showDatePicker(
                  context: context,
                  initialDate: DateTime.tryParse(_date.text) ?? now,
                  firstDate: DateTime(now.year - 2),
                  lastDate: DateTime(now.year + 10),
                );
                if (date != null && mounted) {
                  setState(
                    () => _date.text = date.toIso8601String().substring(0, 10),
                  );
                }
              },
            ),
            const SizedBox(height: 12),
            Text(
              es
                  ? 'La lista se guarda con esta orden. El procedimiento queda fijo al iniciar el trabajo.'
                  : 'The checklist is saved with this order. Its procedure is fixed when work starts.',
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                if (_notes.text.length > 8000) {
                  setState(
                    () => _error = es
                        ? 'Acorta las instrucciones.'
                        : 'Shorten the instructions.',
                  );
                  return;
                }
                Navigator.pop(context, {
                  'checklist_template_id': _template,
                  'procedure_notes': _notes.text.trim(),
                  'service_date': _date.text,
                });
              },
              child: Text(es ? 'Guardar preparación' : 'Save preparation'),
            ),
          ],
        ),
      ),
    );
  }
}
