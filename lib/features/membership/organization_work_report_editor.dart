import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:vortice_app/core/app_dropdown_field.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:uuid/uuid.dart';
import 'package:vortice_app/core/account_storage.dart';
import 'package:vortice_app/core/meter_units.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/core/localized_text.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/checklists/checklist_answer_fields.dart';
import 'package:vortice_app/features/maintenance/maintenance_models.dart';
import 'package:vortice_app/features/maintenance/maintenance_progress.dart';
import 'package:vortice_app/features/service_reports/service_report_form_sections.dart';
import 'package:vortice_app/features/service_reports/service_report_media_section.dart';
import 'package:vortice_app/sync/online_action_gate.dart';
import 'package:vortice_app/sync/field_evidence.dart';
import 'package:vortice_app/sync/field_work_provider.dart';
import 'organization_work_execution.dart';
import 'organization_work_provider.dart';

String _workReportText(
  BuildContext context,
  String english,
  String spanish,
  String french,
) => localizedText(context, english, spanish, french);

class OrganizationWorkReportEditor extends ConsumerStatefulWidget {
  const OrganizationWorkReportEditor({super.key, required this.data});
  final Map<String, dynamic> data;
  @override
  ConsumerState<OrganizationWorkReportEditor> createState() =>
      _OrganizationWorkReportEditorState();
}

class _OrganizationWorkReportEditorState
    extends ConsumerState<OrganizationWorkReportEditor> {
  late Map<String, dynamic> _data;
  late String _account;
  late final _diagnosis = TextEditingController();
  late final _repair = TextEditingController();
  late final _notes = TextEditingController();
  late final _meter = TextEditingController();
  final _picker = ImagePicker();
  Map<String, dynamic> _answers = {};
  List<String> _evidence = [];
  Map<String, dynamic>? _pending;
  bool _ready = false, _busy = false, _requirements = false, _cleared = false;
  Object? _error;
  Future<void> _write = Future.value();
  String get _id => (_data['work_order'] as Map)['id'] as String;
  String get _draftKey => accountStorageKey(
    _account,
    'provider_report:${(_data['work_order'] as Map)['provider_organization_id']}:$_id',
  );
  bool get _frozen => !_ready || _busy || _pending != null;
  Map<String, dynamic> get _order =>
      Map<String, dynamic>.from(_data['work_order'] as Map);
  Map<String, dynamic> _payload() => {
    'diagnosis': _diagnosis.text.trim(),
    'repair': _repair.text.trim(),
    'notes': _notes.text.trim(),
    'meter_value': _meter.text.trim(),
    'meter_unit': _order['meter_unit'] ?? 'hours',
    'answers': _answers,
    'evidence_paths': _evidence,
  };
  @override
  void initState() {
    super.initState();
    _data = Map<String, dynamic>.from(widget.data);
    _account = ref.read(sessionProvider)?.user.id ?? '';
    final report = _data['report'] as Map? ?? {};
    _diagnosis.text = report['diagnosis']?.toString() ?? '';
    _repair.text = report['repair']?.toString() ?? '';
    _notes.text = report['notes']?.toString() ?? '';
    _meter.text = _order['hours_at_end']?.toString() ?? '';
    _answers = Map<String, dynamic>.from(_data['answers'] as Map? ?? {});
    _evidence = (_data['evidence_paths'] as List? ?? []).cast<String>();
    for (final controller in [_diagnosis, _repair, _notes, _meter]) {
      controller.addListener(_saveLocal);
    }
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final raw = prefs.getString(_draftKey);
    if (raw != null) {
      try {
        final saved = jsonDecode(raw) as Map;
        final data = saved['data'] as Map;
        _diagnosis.text = data['diagnosis']?.toString() ?? _diagnosis.text;
        _repair.text = data['repair']?.toString() ?? _repair.text;
        _notes.text = data['notes']?.toString() ?? _notes.text;
        _meter.text = data['meter_value']?.toString() ?? _meter.text;
        _answers = Map<String, dynamic>.from(
          data['answers'] as Map? ?? _answers,
        );
        _evidence = (data['evidence_paths'] as List? ?? _evidence)
            .cast<String>();
        _pending = saved['pending'] is Map
            ? Map<String, dynamic>.from(saved['pending'] as Map)
            : null;
      } catch (_) {
        /* Retain malformed local draft rather than deleting it. */
      }
    }
    if (mounted) setState(() => _ready = true);
  }

  void _saveLocal() {
    if (!_ready || _cleared) return;
    final key = _draftKey;
    final raw = jsonEncode({'data': _payload(), 'pending': _pending});
    _write = _write.catchError((Object _) {}).then((_) async {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(key, raw)) {
        throw StateError('Could not save this draft on the device');
      }
    });
    unawaited(
      _write.catchError((Object error) {
        if (mounted) setState(() => _error = error);
      }),
    );
  }

  @override
  void dispose() {
    _saveLocal();
    for (final controller in [_diagnosis, _repair, _notes, _meter]) {
      controller.dispose();
    }
    super.dispose();
  }

  WorkReportProgress get _progress => WorkReportProgress(
    diagnosis: _diagnosis.text,
    repair: _repair.text,
    items: maintenanceRows(_data['checklist_snapshot']),
    answers: _answers,
    evidence: _evidence,
    meter: _meter.text,
    meterRequired: _order['engine_id'] != null,
    startingMeter: _order['hours_at_start'] as num? ?? 0,
  );

  Future<void> _save(String action) async {
    if (_busy || !_ready) return;
    if (action == 'submit' && _pending == null) {
      setState(() => _requirements = true);
      if (!_progress.complete) {
        return;
      }
    }
    if (!await requireOnlineAction(context, ref) || !mounted) return;
    if (ref.read(sessionProvider)?.user.id != _account) {
      setState(() => _error = const AccountChangedException());
      return;
    }
    _pending ??= {
      'id': const Uuid().v4(),
      'revision': _data['revision'],
      'action': action,
      'data': jsonDecode(jsonEncode(_payload())),
    };
    setState(() {
      _busy = true;
      _error = null;
    });
    var requestStarted = false;
    try {
      _saveLocal();
      await _write;
      final pending = _pending!;
      requestStarted = true;
      await ref
          .read(organizationWorkRepositoryProvider)
          .changeOperation(
            _id,
            (pending['revision'] as num).toInt(),
            pending['id'] as String,
            pending['action'] as String,
            Map<String, dynamic>.from(pending['data'] as Map),
          );
      _cleared = true;
      await _write;
      await (await SharedPreferences.getInstance()).remove(_draftKey);
      if (!mounted) return;
      ref.invalidate(organizationWorkOrderContextProvider(_id));
      Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          // A definite server rejection did not commit this request. Preserve all
          // input, but permit correction or a refreshed revision on the next attempt.
          if (!requestStarted ||
              error is PostgrestException ||
              error is FieldEvidencePendingException) {
            _pending = null;
          }
        });
        _saveLocal();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final latest = await ref
          .read(organizationWorkRepositoryProvider)
          .context(_id);
      if (!mounted) return;
      if (latest['can_work'] != true ||
          !const [
            'in_progress',
            'on_hold',
          ].contains((latest['work_order'] as Map)['status'])) {
        throw StateError(
          'This report is no longer editable. Your local draft is retained.',
        );
      }
      setState(() {
        _data = latest;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _photo(bool camera, {String? item}) async {
    if (_frozen || _evidence.length >= 24 || !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      final bytes = camera
          ? await takeServiceReportCameraPhoto(_picker)
          : await pickServiceReportGalleryPhoto(_picker);
      if (bytes == null) return;
      if (!mounted || ref.read(sessionProvider)?.user.id != _account) {
        throw const AccountChangedException();
      }
      final path = await ref
          .read(organizationWorkRepositoryProvider)
          .uploadEvidence(_id, _account, bytes);
      if (!mounted) return;
      setState(() {
        _evidence = [..._evidence, path];
        if (item != null) {
          _answers[item] = {
            ...Map<String, dynamic>.from(_answers[item] as Map? ?? {}),
            'photo_path': path,
          };
        }
      });
      _saveLocal();
      await _write;
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _answer(String id, String key, String? value) {
    setState(
      () => _answers[id] = {
        ...Map<String, dynamic>.from(_answers[id] as Map? ?? {}),
        key: value,
      },
    );
    _saveLocal();
  }

  String? _itemPhoto(Map<String, dynamic> item) {
    final path = (_answers[item['id']] as Map?)?['photo_path'];
    return path is String && _evidence.contains(path) ? path : null;
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(sessionProvider)?.user.id != _account) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Text(friendlyError(context, const AccountChangedException())),
        ),
      );
    }
    final es = isSpanish(context),
        fr = isFrench(context),
        items = maintenanceRows(_data['checklist_snapshot']);
    final completed = maintenanceCompletedItems(items, _answers, _evidence);
    final repository = ref.watch(organizationWorkRepositoryProvider);
    final pendingPhotos = repository.queue == null
        ? 0
        : (ref.watch(fieldOperationsProvider).valueOrNull ?? [])
              .where(
                (row) =>
                    row.kind == 'upload' &&
                    _evidence.contains(row.payload['path']) &&
                    !row.synced,
              )
              .length;
    return PopScope(
      canPop: !_busy,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) _saveLocal();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _workReportText(
              context,
              'Service report',
              'Informe de servicio',
              'Rapport d’entretien',
            ),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              _order['title']?.toString() ?? '',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              _workReportText(
                context,
                'Your draft stays on this device. The customer receives the approved report.',
                'El borrador permanece en este dispositivo. El cliente recibe el informe aprobado.',
                'Votre brouillon reste sur cet appareil. Le client reçoit le rapport approuvé.',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _workReportText(
                context,
                'Record text and photos offline. Pending photos upload when connected. Submitting for review needs a connection.',
                'Puedes guardar texto y fotos sin conexión. Las fotos pendientes se suben al reconectar. Enviar a revisión requiere conexión.',
                'Vous pouvez enregistrer le texte et les photos hors ligne. Les photos en attente seront téléversées à la reconnexion. L’envoi pour révision nécessite une connexion.',
              ),
            ),
            if (pendingPhotos > 0)
              Text(
                _workReportText(
                  context,
                  '$pendingPhotos photos saved here · waiting to upload',
                  '$pendingPhotos fotos guardadas aquí · pendientes de subir',
                  '$pendingPhotos photos enregistrées ici · en attente de téléversement',
                ),
              ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OrganizationWorkLabour(data: _data),
                    const SizedBox(height: 8),
                    Text(
                      _workReportText(
                        context,
                        'Your timer stays visible while completing the report. Submitting for review stops your running timer.',
                        'El tiempo sigue visible mientras completas el informe. Enviar a revisión detiene tu tiempo activo.',
                        'Le chronomètre reste visible pendant la rédaction du rapport. L’envoi pour révision arrête le chronomètre en cours.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_data['review_note'] != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    '${_workReportText(context, 'Requested changes', 'Cambios solicitados', 'Modifications demandées')}: ${_data['review_note']}',
                  ),
                ),
              ),
            if (_pending != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _workReportText(
                      context,
                      'The last request is unconfirmed. Retry the same request.',
                      'La última solicitud no se ha confirmado. Reintenta la misma solicitud.',
                      'La dernière demande n’a pas été confirmée. Réessayez la même demande.',
                    ),
                  ),
                ),
              ),
            if (_error != null) ...[
              Text(
                _error is FieldEvidencePendingException
                    ? (_error as FieldEvidencePendingException).label(
                        es,
                        french: fr,
                      )
                    : friendlyError(context, _error!),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              if (_pending == null)
                TextButton(
                  onPressed: _busy ? null : _refresh,
                  child: Text(
                    _workReportText(
                      context,
                      'Refresh work and keep draft',
                      'Actualizar trabajo y conservar borrador',
                      'Actualiser le travail et conserver le brouillon',
                    ),
                  ),
                ),
            ],
            if (!_ready) const LinearProgressIndicator(),
            AbsorbPointer(
              absorbing: _frozen,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ServiceReportSectionHeader(
                    title: _workReportText(
                      context,
                      'Diagnosis',
                      'Diagnóstico',
                      'Diagnostic',
                    ),
                  ),
                  ServiceReportTextField(
                    controller: _diagnosis,
                    hintText: _workReportText(
                      context,
                      'Describe the problem found',
                      'Describe el problema encontrado',
                      'Décrivez le problème constaté',
                    ),
                  ),
                  if (_requirements && _progress.diagnosisMissing)
                    Text(
                      _workReportText(
                        context,
                        'Describe the diagnosis.',
                        'Describe el diagnóstico.',
                        'Décrivez le diagnostic.',
                      ),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ServiceReportSectionHeader(
                    title: _workReportText(
                      context,
                      'Repair and verification',
                      'Reparación y verificación',
                      'Réparation et vérification',
                    ),
                  ),
                  ServiceReportTextField(
                    controller: _repair,
                    hintText: _workReportText(
                      context,
                      'Describe the work performed and how it was checked',
                      'Describe el trabajo y su comprobación',
                      'Décrivez les travaux effectués et leur vérification',
                    ),
                  ),
                  if (_requirements && _progress.repairMissing)
                    Text(
                      _workReportText(
                        context,
                        'Describe the work performed.',
                        'Describe el trabajo realizado.',
                        'Décrivez les travaux effectués.',
                      ),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ServiceReportSectionHeader(
                    title: _workReportText(
                      context,
                      'Customer-visible notes',
                      'Notas para el cliente',
                      'Notes visibles par le client',
                    ),
                  ),
                  ServiceReportTextField(
                    controller: _notes,
                    hintText: _workReportText(
                      context,
                      'Additional notes',
                      'Notas adicionales',
                      'Notes supplémentaires',
                    ),
                  ),
                  if (_order['engine_id'] != null) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: _meter,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText:
                            '${_workReportText(context, 'Completion reading', 'Lectura al finalizar', 'Relevé final')} (${meterSymbol(_order['meter_unit'] as String?)})',
                        helperText:
                            '${_workReportText(context, 'Starting', 'Inicial', 'Initial')} : ${formatMeter(_order['hours_at_start'] as num?, _order['meter_unit'] as String?)}',
                        errorText: _requirements
                            ? _progress.meterError(es, french: fr)
                            : null,
                      ),
                    ),
                  ],
                  if ((_data['procedure_notes']?.toString() ?? '')
                      .isNotEmpty) ...[
                    ServiceReportSectionHeader(
                      title: _workReportText(
                        context,
                        'Procedure for this work',
                        'Procedimiento de esta orden',
                        'Procédure pour ce bon de travail',
                      ),
                    ),
                    Text(_data['procedure_notes'].toString()),
                  ],
                  if (items.isNotEmpty) ...[
                    ServiceReportSectionHeader(
                      title:
                          '${_workReportText(context, 'Attached checklist', 'Lista adjunta', 'Liste de contrôle jointe')} · $completed / ${items.length}',
                    ),
                    for (final item in items)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ChecklistAnswerFields(
                                item: item,
                                result:
                                    (_answers[item['id']] as Map?)?['result']
                                        as String?,
                                value:
                                    (_answers[item['id']] as Map?)?['note']
                                        ?.toString() ??
                                    '',
                                onResult: (value) => _answer(
                                  item['id'] as String,
                                  'result',
                                  value,
                                ),
                                onValue: (value) => _answer(
                                  item['id'] as String,
                                  'note',
                                  value,
                                ),
                                failure: 'fail',
                                na: 'na',
                                enabled: !_frozen,
                              ),
                              if ((_answers[item['id']] as Map?)?['result'] ==
                                  'fail')
                                TextFormField(
                                  initialValue:
                                      (_answers[item['id']]
                                              as Map?)?['issue_note']
                                          ?.toString() ??
                                      '',
                                  maxLines: 3,
                                  decoration: InputDecoration(
                                    labelText: _workReportText(
                                      context,
                                      'Issue found',
                                      'Problema encontrado',
                                      'Problème constaté',
                                    ),
                                  ),
                                  onChanged: (value) => _answer(
                                    item['id'] as String,
                                    'issue_note',
                                    value,
                                  ),
                                ),
                              if (item['requires_photo'] == true) ...[
                                const SizedBox(height: 16),
                                AppDropdownField<String>(
                                  isExpanded: true,
                                  key: ValueKey(
                                    'photo-${item['id']}-${_itemPhoto(item)}',
                                  ),
                                  initialValue: _itemPhoto(item),
                                  decoration: InputDecoration(
                                    labelText: _workReportText(
                                      context,
                                      'Required photo',
                                      'Foto requerida',
                                      'Photo requise',
                                    ),
                                  ),
                                  items: [
                                    for (
                                      var index = 0;
                                      index < _evidence.length;
                                      index++
                                    )
                                      DropdownMenuItem(
                                        value: _evidence[index],
                                        child: Text(
                                          '${_workReportText(context, 'Photo', 'Foto', 'Photo')} ${index + 1}',
                                        ),
                                      ),
                                  ],
                                  onChanged: _frozen
                                      ? null
                                      : (value) => _answer(
                                          item['id'] as String,
                                          'photo_path',
                                          value,
                                        ),
                                ),
                                TextButton.icon(
                                  onPressed: _frozen
                                      ? null
                                      : () => _photo(
                                          true,
                                          item: item['id'] as String,
                                        ),
                                  icon: const Icon(Icons.camera_alt_outlined),
                                  label: Text(
                                    _workReportText(
                                      context,
                                      'Photograph this step',
                                      'Fotografiar este paso',
                                      'Photographier cette étape',
                                    ),
                                  ),
                                ),
                              ],
                              if (_requirements &&
                                  maintenanceItemRequirement(
                                        item,
                                        _answers,
                                        _evidence,
                                        es,
                                        french: fr,
                                      ) !=
                                      null)
                                Text(
                                  maintenanceItemRequirement(
                                    item,
                                    _answers,
                                    _evidence,
                                    es,
                                    french: fr,
                                  )!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                  ServiceReportSectionHeader(
                    title: _workReportText(
                      context,
                      'Report photos',
                      'Fotos del informe',
                      'Photos du rapport',
                    ),
                  ),
                  OrganizationWorkEvidence(paths: _evidence),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _frozen ? null : () => _photo(false),
                        icon: const Icon(Icons.photo_library_outlined),
                        label: Text(
                          _workReportText(
                            context,
                            'Add from gallery',
                            'Añadir de galería',
                            'Ajouter depuis la galerie',
                          ),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _frozen ? null : () => _photo(true),
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: Text(
                          _workReportText(
                            context,
                            'Take photo',
                            'Tomar foto',
                            'Prendre une photo',
                          ),
                        ),
                      ),
                    ],
                  ),
                  for (var index = 0; index < _evidence.length; index++)
                    TextButton.icon(
                      onPressed: _frozen
                          ? null
                          : () {
                              final path = _evidence[index];
                              setState(() => _evidence.remove(path));
                              _saveLocal();
                            },
                      icon: const Icon(Icons.remove_circle_outline),
                      label: Text(
                        '${_workReportText(context, 'Remove photo', 'Quitar foto', 'Supprimer la photo')} ${index + 1}',
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (_pending != null)
              FilledButton(
                onPressed: _busy
                    ? null
                    : () => _save(_pending!['action'] as String),
                child: Text(
                  _workReportText(
                    context,
                    'Retry request',
                    'Reintentar solicitud',
                    'Réessayer la demande',
                  ),
                ),
              )
            else ...[
              FilledButton(
                onPressed: _busy || !_ready ? null : () => _save('submit'),
                child: Text(
                  _workReportText(
                    context,
                    'Submit for review',
                    'Enviar a revisión',
                    'Envoyer pour révision',
                  ),
                ),
              ),
              TextButton(
                onPressed: _busy || !_ready ? null : () => _save('save_report'),
                child: Text(
                  _workReportText(
                    context,
                    'Save to server',
                    'Guardar en el servidor',
                    'Enregistrer sur le serveur',
                  ),
                ),
              ),
            ],
            if (_busy) const LinearProgressIndicator(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
