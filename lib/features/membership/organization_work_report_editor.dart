import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:uuid/uuid.dart';
import 'package:vortice_app/core/account_storage.dart';
import 'package:vortice_app/core/meter_units.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/checklists/checklist_answer_fields.dart';
import 'package:vortice_app/features/maintenance/maintenance_models.dart';
import 'package:vortice_app/features/maintenance/maintenance_progress.dart';
import 'package:vortice_app/features/service_reports/service_report_form_sections.dart';
import 'package:vortice_app/features/service_reports/service_report_media_section.dart';
import 'package:vortice_app/sync/online_action_gate.dart';
import 'organization_work_execution.dart';
import 'organization_work_provider.dart';

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
    _write = _write.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, raw);
    });
  }

  @override
  void dispose() {
    _saveLocal();
    for (final controller in [_diagnosis, _repair, _notes, _meter]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _meterError(bool es) {
    if (_order['engine_id'] == null && _meter.text.trim().isEmpty) return null;
    final value = double.tryParse(_meter.text.trim());
    final start = (_order['hours_at_start'] as num?)?.toDouble() ?? 0;
    if (value == null ||
        !value.isFinite ||
        value < start ||
        value >= 1000000000) {
      return es
          ? 'Introduce una lectura válida, igual o mayor que la inicial.'
          : 'Enter a valid reading at least as high as the starting meter.';
    }
    return null;
  }

  Future<void> _save(String action) async {
    if (_busy || !_ready) return;
    if (action == 'submit' && _pending == null) {
      setState(() => _requirements = true);
      if (_diagnosis.text.trim().length < 3 ||
          _repair.text.trim().length < 3 ||
          _meterError(false) != null ||
          maintenanceRows(_data['checklist_snapshot']).any(
            (item) =>
                maintenanceItemRequirement(item, _answers, _evidence, false) !=
                null,
          )) {
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
    _saveLocal();
    await _write;
    try {
      final pending = _pending!;
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
          if (error is PostgrestException) _pending = null;
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
    if (_frozen ||
        _evidence.length >= 24 ||
        !await requireOnlineAction(context, ref) ||
        !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      final bytes = camera
          ? await takeServiceReportCameraPhoto(_picker)
          : await pickServiceReportGalleryPhoto(_picker);
      if (bytes == null) return;
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
        items = maintenanceRows(_data['checklist_snapshot']);
    final completed = maintenanceCompletedItems(items, _answers, _evidence);
    return PopScope(
      canPop: !_busy,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) _saveLocal();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(es ? 'Informe de servicio' : 'Service report'),
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
              es
                  ? 'El borrador permanece en este dispositivo. El cliente recibe el informe aprobado.'
                  : 'Your draft stays on this device. The customer receives the approved report.',
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
                      es
                          ? 'El tiempo sigue visible mientras completas el informe. Enviar a revisión detiene tu tiempo activo.'
                          : 'Your timer stays visible while completing the report. Submitting for review stops your running timer.',
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
                    '${es ? 'Cambios solicitados' : 'Requested changes'}: ${_data['review_note']}',
                  ),
                ),
              ),
            if (_pending != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    es
                        ? 'La última solicitud no se ha confirmado. Reintenta la misma solicitud.'
                        : 'The last request is unconfirmed. Retry the same request.',
                  ),
                ),
              ),
            if (_error != null) ...[
              Text(
                friendlyError(context, _error!),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              if (_pending == null)
                TextButton(
                  onPressed: _busy ? null : _refresh,
                  child: Text(
                    es
                        ? 'Actualizar trabajo y conservar borrador'
                        : 'Refresh work and keep draft',
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
                    title: es ? 'Diagnóstico' : 'Diagnosis',
                  ),
                  ServiceReportTextField(
                    controller: _diagnosis,
                    hintText: es
                        ? 'Describe el problema encontrado'
                        : 'Describe the problem found',
                  ),
                  if (_requirements && _diagnosis.text.trim().length < 3)
                    Text(
                      es
                          ? 'Describe el diagnóstico.'
                          : 'Describe the diagnosis.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ServiceReportSectionHeader(
                    title: es
                        ? 'Reparación y verificación'
                        : 'Repair and verification',
                  ),
                  ServiceReportTextField(
                    controller: _repair,
                    hintText: es
                        ? 'Describe el trabajo y su comprobación'
                        : 'Describe the work performed and how it was checked',
                  ),
                  if (_requirements && _repair.text.trim().length < 3)
                    Text(
                      es
                          ? 'Describe el trabajo realizado.'
                          : 'Describe the work performed.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ServiceReportSectionHeader(
                    title: es
                        ? 'Notas para el cliente'
                        : 'Customer-visible notes',
                  ),
                  ServiceReportTextField(
                    controller: _notes,
                    hintText: es ? 'Notas adicionales' : 'Additional notes',
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
                            '${es ? 'Lectura al finalizar' : 'Completion reading'} (${meterSymbol(_order['meter_unit'] as String?)})',
                        helperText:
                            '${es ? 'Inicial' : 'Starting'}: ${formatMeter(_order['hours_at_start'] as num?, _order['meter_unit'] as String?)}',
                        errorText: _requirements ? _meterError(es) : null,
                      ),
                    ),
                  ],
                  if ((_data['procedure_notes']?.toString() ?? '')
                      .isNotEmpty) ...[
                    ServiceReportSectionHeader(
                      title: es
                          ? 'Procedimiento de esta orden'
                          : 'Procedure for this work',
                    ),
                    Text(_data['procedure_notes'].toString()),
                  ],
                  if (items.isNotEmpty) ...[
                    ServiceReportSectionHeader(
                      title:
                          '${es ? 'Lista adjunta' : 'Attached checklist'} · $completed / ${items.length}',
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
                                    labelText: es
                                        ? 'Problema encontrado'
                                        : 'Issue found',
                                  ),
                                  onChanged: (value) => _answer(
                                    item['id'] as String,
                                    'issue_note',
                                    value,
                                  ),
                                ),
                              if (item['requires_photo'] == true) ...[
                                const SizedBox(height: 16),
                                DropdownButtonFormField<String>(
                                  isExpanded: true,
                                  key: ValueKey(
                                    'photo-${item['id']}-${_itemPhoto(item)}',
                                  ),
                                  initialValue: _itemPhoto(item),
                                  decoration: InputDecoration(
                                    labelText: es
                                        ? 'Foto requerida'
                                        : 'Required photo',
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
                                          '${es ? 'Foto' : 'Photo'} ${index + 1}',
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
                                    es
                                        ? 'Fotografiar este paso'
                                        : 'Photograph this step',
                                  ),
                                ),
                              ],
                              if (_requirements &&
                                  maintenanceItemRequirement(
                                        item,
                                        _answers,
                                        _evidence,
                                        es,
                                      ) !=
                                      null)
                                Text(
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
                            ],
                          ),
                        ),
                      ),
                  ],
                  ServiceReportSectionHeader(
                    title: es ? 'Fotos del informe' : 'Report photos',
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
                          es ? 'Añadir de galería' : 'Add from gallery',
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _frozen ? null : () => _photo(true),
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: Text(es ? 'Tomar foto' : 'Take photo'),
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
                        '${es ? 'Quitar foto' : 'Remove photo'} ${index + 1}',
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
                child: Text(es ? 'Reintentar solicitud' : 'Retry request'),
              )
            else ...[
              FilledButton(
                onPressed: _busy || !_ready ? null : () => _save('submit'),
                child: Text(es ? 'Enviar a revisión' : 'Submit for review'),
              ),
              TextButton(
                onPressed: _busy || !_ready ? null : () => _save('save_report'),
                child: Text(es ? 'Guardar borrador' : 'Save draft'),
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
