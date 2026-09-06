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
  MaintenanceWrite? _pending;
  String? _action;
  bool _saving = false, _uploading = false, _dirty = false;
  Object? _error;
  late final String _account;
  bool _draftReady = false, _draftCleared = false;
  bool _leaving = false;
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
    for (final c in [_diagnosis, _repair, _notes, _hours]) {
      c.addListener(_saveLocal);
    }
    unawaited(_restoreLocal());
  }

  @override
  void dispose() {
    for (final c in [_diagnosis, _repair, _notes, _hours]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save(String action) async {
    _action ??= action;
    _pending ??= MaintenanceWrite({
      'diagnosis': _diagnosis.text.trim(),
      'repair': _repair.text.trim(),
      'notes': _notes.text.trim(),
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
                  title: Text(isSpanish(context) ? 'Cámara' : 'Camera'),
                  onTap: () => Navigator.pop(context, ImageSource.camera),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: Text(isSpanish(context) ? 'Galería' : 'Gallery'),
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
        frozen = !_draftReady || _saving || _uploading || _pending != null;
    Widget textField(
      TextEditingController controller,
      String en,
      String spanish, {
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
        decoration: InputDecoration(labelText: es ? spanish : en),
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
        appBar: AppBar(title: Text(es ? 'Informe del trabajo' : 'Job report')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              widget.job.title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(widget.job.assetName),
            if (_dirty && _draftReady)
              Text(
                es
                    ? 'El borrador se conserva en este dispositivo.'
                    : 'Your draft stays on this device.',
              ),
            const SizedBox(height: 20),
            textField(_diagnosis, 'Diagnosis', 'Diagnóstico'),
            textField(
              _repair,
              'Repair and test results',
              'Reparación y pruebas',
            ),
            textField(_notes, 'Additional notes', 'Notas adicionales'),
            if (widget.job.isService)
              textField(
                _hours,
                'Component meter at completion',
                'Horas al finalizar',
                numeric: true,
              ),
            if (widget.job.checklist.isNotEmpty)
              Text(
                es ? 'Lista de revisión del trabajo' : 'Job checklist',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            for (final item in widget.job.checklist)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                  onPressed: frozen
                      ? null
                      : () => setState(() {
                          final path = _evidence.removeAt(i);
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
            if (_pending != null)
              FilledButton(
                onPressed: _saving || _uploading ? null : () => _save(_action!),
                child: Text(
                  es ? 'Reintentar el mismo guardado' : 'Retry the same save',
                ),
              )
            else ...[
              OutlinedButton(
                onPressed: frozen || _photo != null
                    ? null
                    : () => _save('save_report'),
                child: Text(es ? 'Guardar borrador' : 'Save draft'),
              ),
              FilledButton(
                onPressed: frozen || _photo != null
                    ? null
                    : () => _save('submit'),
                child: Text(es ? 'Enviar a revisión' : 'Submit for review'),
              ),
            ],
            Text(
              es
                  ? 'El servicio solo se completa después de la aprobación.'
                  : 'Service is only completed after approval.',
            ),
          ],
        ),
      ),
    );
  }
}
