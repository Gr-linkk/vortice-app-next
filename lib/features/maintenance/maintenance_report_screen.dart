import 'maintenance_recurrence.dart';
import 'maintenance_progress.dart';
import 'package:vortice_app/features/parts/work_parts_progress.dart';
import 'package:vortice_app/core/meter_units.dart';
import 'package:vortice_app/features/checklists/checklist_answer_fields.dart';
import 'package:vortice_app/core/app_dropdown_field.dart';
import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vortice_app/core/account_storage.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/core/localized_text.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'maintenance_models.dart';
import 'maintenance_repository.dart';
import 'maintenance_refresh.dart';

class MaintenanceReportScreen extends ConsumerStatefulWidget {
  const MaintenanceReportScreen({super.key, required this.job});
  final MaintenanceJob job;
  @override
  ConsumerState<MaintenanceReportScreen> createState() =>
      _MaintenanceReportScreenState();
}

class _MaintenanceReportScreenState
    extends ConsumerState<MaintenanceReportScreen> {
  late final TextEditingController _diagnosis, _repair, _notes, _hours;
  late final Map<String, dynamic> _answers;
  late final List<String> _evidence;
  final Map<String, TextEditingController> _inspectionFields = {};
  String? _certificate;
  bool get _isInspection => widget.job.data['inspection_id'] != null;
  bool get _inspectionApproved =>
      widget.job.data['inspection_applied_at'] != null;
  Map<String, dynamic> get _inspection => {
    for (final entry in _inspectionFields.entries)
      entry.key: entry.value.text.trim(),
    'evidence_path': _certificate,
  };
  MaintenanceWrite? _pending;
  String? _action;
  bool _saving = false, _uploading = false, _dirty = false;
  Object? _error;
  late final String _account;
  bool _draftReady = false, _draftCleared = false;
  bool _leaving = false, _showRequirements = false;
  Future<void> _draftWrite = Future.value();
  String get _draftKey =>
      accountStorageKey(_account, 'maintenance_report:${widget.job.id}');
  Future<void> _restoreLocal() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final raw = prefs.getString(_draftKey);
    if (raw != null) {
      try {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        _diagnosis.text = data['diagnosis'] as String? ?? '';
        _repair.text = data['repair'] as String? ?? '';
        _notes.text = data['notes'] as String? ?? '';
        _hours.text = data['hours'] as String? ?? '';
        _answers
          ..clear()
          ..addAll(Map<String, dynamic>.from(data['answers'] as Map? ?? {}));
        _evidence
          ..clear()
          ..addAll((data['evidence'] as List? ?? []).cast<String>());
        for (final field in _inspectionFields.entries) {
          if ((data['inspection'] as Map?)?[field.key] is String) {
            field.value.text = (data['inspection'] as Map)[field.key] as String;
          }
        }
        _certificate =
            (data['inspection'] as Map?)?['evidence_path'] as String? ??
            _certificate;
        _dirty = true;
      } catch (_) {
        /* Preserve malformed draft for recovery. */
      }
    }
    setState(() => _draftReady = true);
  }

  void _saveLocal() {
    if (!_draftReady || _draftCleared) return;
    final raw = jsonEncode({
      'diagnosis': _diagnosis.text,
      'repair': _repair.text,
      'notes': _notes.text,
      'hours': _hours.text,
      'answers': _answers,
      'evidence': _evidence,
      if (_isInspection) 'inspection': _inspection,
    });
    _draftWrite = _draftWrite.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_draftKey, raw);
    });
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _saveLocal();
  }

  ({String path, Uint8List bytes, String type})? _photo;
  @override
  void initState() {
    super.initState();
    _account = ref.read(sessionProvider)?.user.id ?? 'signed_out';
    _diagnosis = TextEditingController(
      text: widget.job.report['diagnosis'] as String? ?? '',
    );
    _repair = TextEditingController(
      text: widget.job.report['repair'] as String? ?? '',
    );
    _notes = TextEditingController(
      text: widget.job.report['notes'] as String? ?? '',
    );
    _hours = TextEditingController(
      text: widget.job.data['hours_at_end']?.toString() ?? '',
    );
    _answers =
        jsonDecode(jsonEncode(widget.job.answers)) as Map<String, dynamic>;
    _evidence = [...widget.job.evidence];
    if (_isInspection) {
      final previous = widget.job.data['inspection_result'] as Map? ?? {};
      final source = widget.job.data['inspection_snapshot'] as Map? ?? {};
      final today = DateTime.now();
      final defaults = <String, String>{
        'inspected_on': MaintenanceRecurrence.dateText(today),
        'expires_on': MaintenanceRecurrence.dateText(
          MaintenanceRecurrence.addMonths(
            today,
            (source['interval_months'] as num?)?.toInt() ?? 12,
          ),
        ),
        'procedure_notes': source['procedure_notes'] as String? ?? '',
        'result_notes': '',
      };
      for (final key in defaults.keys) {
        _inspectionFields[key] = TextEditingController(
          text: previous[key] as String? ?? defaults[key],
        );
      }
      _certificate = previous['evidence_path'] as String?;
    }
    for (final c in [
      _diagnosis,
      _repair,
      _notes,
      _hours,
      ..._inspectionFields.values,
    ]) {
      c.addListener(_saveLocal);
    }
    unawaited(_restoreLocal());
  }

  @override
  void dispose() {
    for (final c in [
      _diagnosis,
      _repair,
      _notes,
      _hours,
      ..._inspectionFields.values,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save(String action) async {
    if (action == 'submit' && _pending == null) {
      setState(() => _showRequirements = true);
      if (!_progress.complete ||
          (_isInspection &&
              !_inspectionApproved &&
              (_inspectionFields.keys.any(
                    (key) => _inspectionError(key, false) != null,
                  ) ||
                  !_evidence.contains(_certificate)))) {
        return;
      }
    }
    _action ??= action;
    _pending ??= MaintenanceWrite({
      'diagnosis': _diagnosis.text.trim(),
      'repair': _repair.text.trim(),
      'notes': _notes.text.trim(),
      'meter_unit': widget.job.data['meter_unit'] ?? 'hours',
      if (_isInspection) 'inspection': _inspection,
      'completion_hours': _hours.text.trim().isEmpty
          ? null
          : _hours.text.trim(),
      'answers': _answers,
      'evidence_paths': _evidence,
    });
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      _saveLocal();
      await _draftWrite;
      if (!mounted ||
          (ref.read(sessionProvider)?.user.id ?? 'signed_out') != _account) {
        throw const AccountChangedException();
      }
      await ref
          .read(maintenanceRepositoryProvider)
          .change(
            widget.job.id,
            widget.job.revision,
            _pending!.id,
            _action!,
            _pending!.data,
          );
      _draftCleared = true;
      await _draftWrite;
      await (await SharedPreferences.getInstance()).remove(_draftKey);
      if (mounted) {
        refreshMaintenance(ref, jobId: widget.job.id);
        if (Navigator.of(context).canPop()) {
          Navigator.pop(context, true);
        } else {
          context.go('/maintenance/jobs/${widget.job.id}');
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          if (maintenanceWriteWasRejected(error)) {
            _pending = null;
            _action = null;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  WorkReportProgress get _progress => WorkReportProgress(
    diagnosis: _diagnosis.text,
    repair: _repair.text,
    items: widget.job.checklist,
    answers: _answers,
    evidence: _evidence,
    meter: _hours.text,
    meterRequired: widget.job.isService && widget.job.data['engine_id'] != null,
    startingMeter: widget.job.data['hours_at_start'] as num? ?? 0,
  );

  String? _inspectionError(String key, bool es, {bool french = false}) {
    final value = _inspectionFields[key]?.text.trim() ?? '';
    if (key == 'inspected_on' || key == 'expires_on') {
      final date = MaintenanceRecurrence.parseDate(value);
      final inspected = MaintenanceRecurrence.parseDate(
        _inspectionFields['inspected_on']?.text.trim() ?? '',
      );
      final today = DateTime.now();
      if (date == null ||
          date.year < 1900 ||
          date.year > 2200 ||
          (key == 'inspected_on' &&
              date.isAfter(DateTime(today.year, today.month, today.day))) ||
          (key == 'expires_on' &&
              (inspected == null || !date.isAfter(inspected)))) {
        return french
            ? 'Vérifiez la date (AAAA-MM-JJ).'
            : es
            ? 'Revisa la fecha (YYYY-MM-DD)'
            : 'Check the date (YYYY-MM-DD)';
      }
    } else if (value.length < 3) {
      return french
          ? 'Décrivez la procédure et le résultat.'
          : es
          ? 'Describe el procedimiento y el resultado'
          : 'Describe the procedure and result';
    }
    return null;
  }

  Future<void> _upload() async {
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      if (_photo == null) {
        final source = await showModalBottomSheet<ImageSource>(
          context: context,
          builder: (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.camera_alt),
                  title: Text(
                    localizedText(context, 'Camera', 'Cámara', 'Caméra'),
                  ),
                  onTap: () => Navigator.pop(context, ImageSource.camera),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: Text(
                    localizedText(context, 'Gallery', 'Galería', 'Photothèque'),
                  ),
                  onTap: () => Navigator.pop(context, ImageSource.gallery),
                ),
              ],
            ),
          ),
        );
        if (source == null) return;
        final file = await ImagePicker().pickImage(
          source: source,
          maxWidth: 2000,
          imageQuality: 85,
        );
        if (file == null || !mounted) return;
        final user = ref.read(profileProvider).valueOrNull?.id;
        if (user == null) return;
        final ext = file.name.toLowerCase().endsWith('.png')
            ? 'png'
            : file.name.toLowerCase().endsWith('.webp')
            ? 'webp'
            : 'jpg';
        _photo = (
          path: '${widget.job.id}/$user/${const Uuid().v4()}.$ext',
          bytes: await file.readAsBytes(),
          type: ext == 'jpg' ? 'image/jpeg' : 'image/$ext',
        );
      }
      await ref
          .read(maintenanceRepositoryProvider)
          .uploadEvidence(_photo!.path, _photo!.bytes, _photo!.type);
      if (mounted) {
        setState(() {
          _evidence.add(_photo!.path);
          _photo = null;
          _dirty = true;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final es = isSpanish(context),
        fr = isFrench(context),
        frozen = !_draftReady || _saving || _uploading || _pending != null;
    Widget textField(
      TextEditingController controller,
      String en,
      String spanish, {
      String? french,
      bool numeric = false,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        enabled: !frozen,
        onChanged: (_) => _dirty = true,
        minLines: numeric ? 1 : 2,
        maxLines: numeric ? 1 : 6,
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.multiline,
        decoration: InputDecoration(
          labelText: fr
              ? french ?? en
              : es
              ? spanish
              : en,
          errorText: !_showRequirements
              ? null
              : (controller == _diagnosis || controller == _repair) &&
                    controller.text.trim().length < 3
              ? (fr
                    ? 'Décrivez les constatations et le travail effectué'
                    : es
                    ? 'Describe los hallazgos y el trabajo realizado'
                    : 'Describe the findings and work performed')
              : controller == _hours
              ? _progress.meterError(es)
              : null,
        ),
      ),
    );
    return PopScope(
      canPop: _leaving,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || _saving || _uploading || !_draftReady) return;
        try {
          _saveLocal();
          await _draftWrite;
          if (!mounted) return;
          setState(() => _leaving = true);
          await WidgetsBinding.instance.endOfFrame;
          if (!context.mounted) return;
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop(result);
          } else {
            context.go('/maintenance/jobs/${widget.job.id}');
          }
        } catch (error) {
          if (mounted) setState(() => _error = error);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            localizedText(
              context,
              'Service report',
              'Informe de servicio',
              'Rapport d’intervention',
            ),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              widget.job.title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(widget.job.assetName),
            if ((widget.job.data['review_note'] as String? ?? '').isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        localizedText(
                          context,
                          'Changes requested',
                          'Cambios solicitados',
                          'Modifications demandées',
                        ),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(widget.job.data['review_note'] as String),
                    ],
                  ),
                ),
              ),
            if (widget.job.checklist.isNotEmpty)
              Text(
                '${localizedText(context, 'Checklist', 'Lista', 'Liste de contrôle')} : ${maintenanceCompletedItems(widget.job.checklist, _answers, _evidence)} / ${widget.job.checklist.length}',
              ),
            WorkPartsProgress(jobId: widget.job.id),
            if (widget.job.hasRunningLabour)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.timer_outlined),
                  title: Text(
                    localizedText(
                      context,
                      'Labour timer running',
                      'Tiempo de trabajo en curso',
                      'Minuterie de travail en cours',
                    ),
                  ),
                  subtitle: Text(
                    fr
                        ? 'Mettez le temps en pause avant de soumettre le rapport pour révision.'
                        : es
                        ? 'Pausa el tiempo antes de enviar a revisión.'
                        : 'Pause labour before submitting for review.',
                  ),
                  onTap: () => Navigator.maybePop(context),
                ),
              ),
            if (_dirty && _draftReady)
              Text(
                fr
                    ? 'Le brouillon est conservé sur cet appareil.'
                    : es
                    ? 'El borrador se conserva en este dispositivo.'
                    : 'Your draft stays on this device.',
              ),
            const SizedBox(height: 20),
            textField(
              _diagnosis,
              'Findings',
              'Hallazgos',
              french: 'Constatations',
            ),
            textField(
              _repair,
              'Work performed and results',
              'Trabajo realizado y resultados',
              french: 'Travail effectué et résultats',
            ),
            textField(
              _notes,
              'Additional notes',
              'Notas adicionales',
              french: 'Notes supplémentaires',
            ),
            if (widget.job.data['engine_id'] != null)
              textField(
                _hours,
                'Completion meter (${meterSymbol(widget.job.data['meter_unit'] as String?)})',
                'Medidor al finalizar (${meterSymbol(widget.job.data['meter_unit'] as String?)})',
                french:
                    'Relevé à la fin (${meterSymbol(widget.job.data['meter_unit'] as String?)})',
                numeric: true,
              ),
            if (_isInspection) ...[
              Text(
                localizedText(
                  context,
                  'Inspection certificate',
                  'Certificado de inspección',
                  'Certificat d’inspection',
                ),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                fr
                    ? 'Le certificat actuel reste valide jusqu’à l’approbation de ce travail.'
                    : es
                    ? 'El certificado actual sigue vigente hasta que se apruebe esta orden.'
                    : 'The current certificate stays current until this work is approved.',
              ),
              for (final entry in _inspectionFields.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: TextField(
                    controller: entry.value,
                    enabled: !frozen && !_inspectionApproved,
                    minLines: entry.key.endsWith('_on') ? 1 : 2,
                    maxLines: entry.key.endsWith('_on') ? 1 : 5,
                    decoration: InputDecoration(
                      labelText: switch (entry.key) {
                        'inspected_on' => localizedText(
                          context,
                          'Inspection date',
                          'Fecha de inspección',
                          'Date d’inspection',
                        ),
                        'expires_on' =>
                          fr
                              ? 'Prochaine date d’échéance'
                              : es
                              ? 'Próxima fecha de vencimiento'
                              : 'Next expiry date',
                        'procedure_notes' => localizedText(
                          context,
                          'Procedure performed',
                          'Procedimiento aplicado',
                          'Procédure effectuée',
                        ),
                        _ =>
                          fr
                              ? 'Résultat et certification'
                              : es
                              ? 'Resultado y certificación'
                              : 'Result and certification',
                      },
                      hintText: entry.key.endsWith('_on') ? 'YYYY-MM-DD' : null,
                      errorText: _showRequirements
                          ? _inspectionError(entry.key, es, french: fr)
                          : null,
                    ),
                    onChanged: (_) => setState(() => _dirty = true),
                  ),
                ),
              AppDropdownField<String>(
                key: ValueKey('certificate:$_certificate'),
                initialValue: _certificate,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: localizedText(
                    context,
                    'Certificate photo',
                    'Foto del certificado',
                    'Photo du certificat',
                  ),
                  errorText:
                      _showRequirements && !_evidence.contains(_certificate)
                      ? (fr
                            ? 'Ajoutez et sélectionnez une preuve'
                            : es
                            ? 'Añade y selecciona la evidencia'
                            : 'Add and select the evidence')
                      : null,
                ),
                items: [
                  for (var i = 0; i < _evidence.length; i++)
                    DropdownMenuItem(
                      value: _evidence[i],
                      child: Text(
                        '${localizedText(context, 'Photo', 'Foto', 'Photo')} ${i + 1}',
                      ),
                    ),
                ],
                onChanged: frozen || _inspectionApproved
                    ? null
                    : (value) => setState(() {
                        _certificate = value;
                        _dirty = true;
                      }),
              ),
              const SizedBox(height: 20),
            ],
            if (widget.job.checklist.isNotEmpty)
              Text(
                localizedText(
                  context,
                  'Work order checklist',
                  'Lista de revisión de la orden',
                  'Liste de contrôle du bon de travail',
                ),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            for (final item in widget.job.checklist)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if ((item['definition'] as Map? ?? {}).isNotEmpty)
                        ChecklistAnswerFields(
                          item: item,
                          result:
                              (_answers[item['id']] as Map?)?['result']
                                  as String?,
                          value:
                              (_answers[item['id']] as Map?)?['note']
                                  as String? ??
                              '',
                          enabled: !frozen,
                          failure: 'fail',
                          na: 'na',
                          onResult: (value) => setState(() {
                            _answers[item['id'] as String] = {
                              ...?_answers[item['id']] as Map<String, dynamic>?,
                              'result': value,
                            };
                            _dirty = true;
                          }),
                          onValue: (value) => setState(() {
                            _answers[item['id'] as String] = {
                              ...?_answers[item['id']] as Map<String, dynamic>?,
                              'note': value,
                            };
                            _dirty = true;
                          }),
                        )
                      else ...[
                        Text(
                          (es
                                  ? item['description_es'] ??
                                        item['description_en']
                                  : item['description_en'])
                              as String,
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final choice in [
                              ('pass', es ? 'Correcto' : 'Pass'),
                              ('fail', es ? 'Falla' : 'Fail'),
                              ('na', es ? 'No aplica' : 'Not applicable'),
                            ])
                              ChoiceChip(
                                label: Text(choice.$2),
                                selected:
                                    (_answers[item['id']] as Map?)?['result'] ==
                                    choice.$1,
                                onSelected: frozen
                                    ? null
                                    : (_) => setState(() {
                                        _answers[item['id'] as String] = {
                                          ...?_answers[item['id']]
                                              as Map<String, dynamic>?,
                                          'result': choice.$1,
                                        };
                                        _dirty = true;
                                      }),
                              ),
                          ],
                        ),
                      ],
                      if (_showRequirements &&
                          maintenanceItemRequirement(
                                item,
                                _answers,
                                _evidence,
                                es,
                              ) !=
                              null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            maintenanceItemRequirement(
                              item,
                              _answers,
                              _evidence,
                              es,
                            )!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      if ((_answers[item['id']] as Map?)?['result'] ==
                          'fail') ...[
                        TextFormField(
                          initialValue:
                              (_answers[item['id']] as Map?)?['issue_note']
                                  as String? ??
                              '',
                          enabled: !frozen,
                          minLines: 2,
                          maxLines: 4,
                          decoration: InputDecoration(
                            labelText: es
                                ? 'Describe el problema para el seguimiento'
                                : 'Describe the issue for follow-up',
                          ),
                          onChanged: (value) => setState(() {
                            _answers[item['id'] as String] = {
                              ...?_answers[item['id']] as Map<String, dynamic>?,
                              'issue_note': value,
                            };
                            _dirty = true;
                          }),
                        ),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            es
                                ? 'Crear una falla vinculada al guardar'
                                : 'Create a linked fault when saved',
                          ),
                          value:
                              (_answers[item['id']]
                                  as Map?)?['fault_requested'] ==
                              true,
                          onChanged: frozen
                              ? null
                              : (value) => setState(() {
                                  _answers[item['id'] as String] = {
                                    ...?_answers[item['id']]
                                        as Map<String, dynamic>?,
                                    'fault_requested': value == true,
                                  };
                                  _dirty = true;
                                }),
                        ),
                      ],
                      if (item['requires_photo'] == true) ...[
                        const SizedBox(height: 12),
                        AppDropdownField<String>(
                          key: ValueKey(
                            '${item['id']}:${(_answers[item['id']] as Map?)?['photo_path']}',
                          ),
                          initialValue:
                              (_answers[item['id']] as Map?)?['photo_path']
                                  as String?,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: es ? 'Foto requerida' : 'Required photo',
                          ),
                          items: [
                            for (var i = 0; i < _evidence.length; i++)
                              DropdownMenuItem(
                                value: _evidence[i],
                                child: Text(
                                  '${es ? 'Foto' : 'Photo'} ${i + 1}',
                                ),
                              ),
                          ],
                          onChanged: frozen
                              ? null
                              : (v) => setState(() {
                                  _answers[item['id'] as String] = {
                                    ...?_answers[item['id']]
                                        as Map<String, dynamic>?,
                                    'photo_path': v,
                                  };
                                  _dirty = true;
                                }),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Text(
              es ? 'Evidencia privada' : 'Private evidence',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (var i = 0; i < _evidence.length; i++)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.photo_outlined),
                title: Text('${es ? 'Foto' : 'Photo'} ${i + 1}'),
                trailing: IconButton(
                  tooltip: es ? 'Quitar del informe' : 'Remove from report',
                  onPressed:
                      frozen ||
                          (_inspectionApproved && _evidence[i] == _certificate)
                      ? null
                      : () => setState(() {
                          final path = _evidence.removeAt(i);
                          if (_certificate == path) _certificate = null;
                          for (final answer in _answers.values) {
                            if (answer is Map && answer['photo_path'] == path) {
                              answer.remove('photo_path');
                            }
                          }
                          _dirty = true;
                        }),
                  icon: const Icon(Icons.close),
                ),
              ),
            OutlinedButton.icon(
              onPressed: frozen ? null : _upload,
              icon: const Icon(Icons.add_photo_alternate),
              label: Text(
                _photo != null
                    ? (es ? 'Reintentar foto' : 'Retry photo upload')
                    : (es ? 'Añadir foto' : 'Add photo'),
              ),
            ),
            if (_uploading) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(maintenanceError(_error!, es)),
              ),
            const SizedBox(height: 16),
            if (widget.job.hasRunningLabour) ...[
              Text(
                es
                    ? 'Pausa el tiempo de trabajo antes de enviar a revisión. Tu borrador se conserva.'
                    : 'Pause labour before submitting for review. Your draft is kept.',
              ),
              TextButton.icon(
                onPressed: frozen
                    ? null
                    : () {
                        if (Navigator.of(context).canPop()) {
                          Navigator.pop(context);
                        } else {
                          context.go('/maintenance/jobs/${widget.job.id}');
                        }
                      },
                icon: const Icon(Icons.timer_outlined),
                label: Text(
                  localizedText(
                    context,
                    'Open labour timer',
                    'Abrir tiempo de trabajo',
                    'Ouvrir la minuterie de travail',
                  ),
                ),
              ),
            ],
            if (_pending != null)
              FilledButton(
                onPressed: _saving || _uploading ? null : () => _save(_action!),
                child: Text(
                  localizedText(
                    context,
                    'Retry the same save',
                    'Reintentar el mismo guardado',
                    'Réessayer le même enregistrement',
                  ),
                ),
              )
            else ...[
              OutlinedButton(
                onPressed: frozen || _photo != null
                    ? null
                    : () => _save('save_report'),
                child: Text(
                  localizedText(
                    context,
                    'Save draft',
                    'Guardar borrador',
                    'Enregistrer le brouillon',
                  ),
                ),
              ),
              FilledButton(
                onPressed:
                    frozen || _photo != null || widget.job.hasRunningLabour
                    ? null
                    : () => _save('submit'),
                child: Text(
                  localizedText(
                    context,
                    'Submit for review',
                    'Enviar a revisión',
                    'Soumettre pour révision',
                  ),
                ),
              ),
            ],
            Text(
              fr
                  ? 'Les bons de travail ne sont terminés qu’après leur approbation.'
                  : es
                  ? 'Las órdenes solo se completan después de la aprobación.'
                  : 'Work orders are only completed after approval.',
            ),
          ],
        ),
      ),
    );
  }
}
