import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vortice_app/core/app_dropdown_field.dart';
import 'package:vortice_app/core/unsaved_form_guard.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/core/localized_text.dart';
import 'package:vortice_app/models/work_order.dart';
import 'maintenance_models.dart';
import 'maintenance_repository.dart';
import 'maintenance_refresh.dart';

class InternalWorkOrderEditScreen extends ConsumerStatefulWidget {
  const InternalWorkOrderEditScreen({super.key, required this.job});
  final MaintenanceJob job;
  @override
  ConsumerState<InternalWorkOrderEditScreen> createState() =>
      _InternalWorkOrderEditScreenState();
}

class _InternalWorkOrderEditScreenState
    extends ConsumerState<InternalWorkOrderEditScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title, _instructions, _materials;
  final _reason = TextEditingController();
  late WorkOrderJobType _type;
  late String _priority;
  bool _busy = false, _dirty = false, _stale = false;
  MaintenanceWrite? _pending;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.job.title);
    _instructions = TextEditingController(
      text: widget.job.data['description'] as String? ?? '',
    );
    _materials = TextEditingController(text: widget.job.expectedMaterials);
    _type = widget.job.workType;
    _priority = widget.job.priority;
  }

  @override
  void dispose() {
    for (final field in [_title, _instructions, _materials, _reason]) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate() || _stale) return;
    _pending ??= MaintenanceWrite({
      'title': _title.text.trim(),
      'description': _instructions.text.trim(),
      'job_type': _type.dbValue,
      'priority': _priority,
      'expected_materials': _materials.text.trim(),
      'note': _reason.text.trim(),
    });
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(maintenanceRepositoryProvider)
          .change(
            widget.job.id,
            widget.job.revision,
            _pending!.id,
            'edit_details',
            _pending!.data,
          );
      if (mounted) {
        refreshMaintenance(ref, jobId: widget.job.id);
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          if (maintenanceWriteWasRejected(error)) _pending = null;
          _stale = error is PostgrestException && error.code == '40001';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final es = isSpanish(context), fr = isFrench(context);
    final frozen = _busy || _pending != null || _stale;
    if (!widget.job.canPrepare) {
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
        ),
        body: Center(
          child: Text(
            es
                ? 'Esta orden no se puede editar.'
                : fr
                ? 'Ce bon de travail ne peut pas être modifié.'
                : 'This work order cannot be edited.',
          ),
        ),
      );
    }
    return UnsavedFormGuard(
      isDirty: () => _dirty,
      controllers: [_title, _instructions, _materials, _reason],
      fallbackRoute: '/maintenance/jobs/${widget.job.id}',
      busy: _busy,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            localizedText(
              context,
              'Edit work order',
              'Editar orden de trabajo',
              'Modifier le bon de travail',
            ),
          ),
        ),
        body: Form(
          key: _form,
          onChanged: () => _dirty = true,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                widget.job.assetName,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                fr
                    ? 'Préparez la portée avant de commencer le travail. Gérez les affectations et les dates dans le bon de travail et sa planification.'
                    : es
                    ? 'Prepara el alcance antes de iniciar el trabajo. La asignación y las fechas se gestionan en la orden y su planificación.'
                    : 'Prepare the scope before work starts. Manage assignment and dates from the work order and its schedule.',
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _title,
                enabled: !frozen,
                maxLength: 200,
                decoration: InputDecoration(
                  labelText: localizedText(
                    context,
                    'Work order title',
                    'Título de la orden',
                    'Titre du bon de travail',
                  ),
                ),
                validator: (value) => (value?.trim().length ?? 0) < 3
                    ? localizedText(
                        context,
                        'Describe the work',
                        'Describe el trabajo',
                        'Décrivez le travail',
                      )
                    : null,
              ),
              const SizedBox(height: 16),
              AppDropdownField<WorkOrderJobType>(
                initialValue: _type,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: localizedText(
                    context,
                    'Work type',
                    'Tipo de trabajo',
                    'Type de travail',
                  ),
                ),
                items: [
                  for (final type in WorkOrderJobType.values)
                    DropdownMenuItem(
                      value: type,
                      child: Text(type.label(es, fr: fr)),
                    ),
                ],
                onChanged: frozen || widget.job.isService
                    ? null
                    : (value) => setState(() => _type = value!),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _instructions,
                enabled: !frozen,
                minLines: 3,
                maxLines: 6,
                maxLength: 8000,
                decoration: InputDecoration(
                  labelText: localizedText(
                    context,
                    'Instructions',
                    'Instrucciones',
                    'Instructions',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _materials,
                enabled: !frozen,
                minLines: 2,
                maxLines: 4,
                maxLength: 4000,
                decoration: InputDecoration(
                  labelText: fr
                      ? 'Pièces et matériaux prévus'
                      : es
                      ? 'Repuestos y materiales previstos'
                      : 'Expected parts / materials',
                ),
              ),
              const SizedBox(height: 16),
              AppDropdownField<String>(
                initialValue: _priority,
                decoration: InputDecoration(
                  labelText: localizedText(
                    context,
                    'Priority',
                    'Prioridad',
                    'Priorité',
                  ),
                ),
                items: [
                  for (final value in ['low', 'normal', 'high', 'urgent'])
                    DropdownMenuItem(
                      value: value,
                      child: Text(maintenancePriority(value, es, french: fr)),
                    ),
                ],
                onChanged: frozen
                    ? null
                    : (value) => setState(() => _priority = value!),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _reason,
                enabled: !frozen,
                minLines: 2,
                maxLines: 4,
                maxLength: 1000,
                decoration: InputDecoration(
                  labelText: localizedText(
                    context,
                    'Reason for change',
                    'Motivo del cambio',
                    'Motif du changement',
                  ),
                ),
                validator: (value) => (value?.trim().length ?? 0) < 3
                    ? localizedText(
                        context,
                        'Explain the change',
                        'Explica el cambio',
                        'Expliquez le changement',
                      )
                    : null,
              ),
              if (_error != null) Text(maintenanceError(_error!, es)),
              if (_stale)
                TextButton(
                  onPressed: () {
                    refreshMaintenance(ref, jobId: widget.job.id);
                    Navigator.pop(context);
                  },
                  child: Text(
                    fr
                        ? 'Abandonner les modifications et recharger'
                        : es
                        ? 'Descartar cambios y volver a cargar'
                        : 'Discard edits and reload',
                  ),
                ),
              const SizedBox(height: 16),
              SafeArea(
                top: false,
                child: FilledButton(
                  onPressed: _busy || _stale ? null : _save,
                  child: Text(
                    _busy
                        ? localizedText(
                            context,
                            'Saving…',
                            'Guardando…',
                            'Enregistrement…',
                          )
                        : _pending != null
                        ? (fr
                              ? 'Réessayer le même enregistrement'
                              : es
                              ? 'Reintentar el mismo guardado'
                              : 'Retry same save')
                        : localizedText(
                            context,
                            'Save work order',
                            'Guardar orden de trabajo',
                            'Enregistrer le bon de travail',
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
