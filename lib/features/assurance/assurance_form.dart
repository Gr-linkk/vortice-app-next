import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:vortice_app/core/app_dropdown_field.dart';
import 'package:vortice_app/core/unsaved_form_guard.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/maintenance/maintenance_models.dart';
import 'package:vortice_app/features/maintenance/maintenance_repository.dart';
import 'package:vortice_app/features/maintenance/maintenance_refresh.dart';
import 'assurance_repository.dart';

final inspectionPhotoPickerProvider = Provider<Future<XFile?> Function()>(
  (ref) =>
      () => ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 2000,
        imageQuality: 85,
      ),
);

DateTime? inspectionDate(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return null;
  final date = DateTime.tryParse(value);
  return date != null && date.toIso8601String().startsWith(value) ? date : null;
}

class AssuranceForm extends ConsumerStatefulWidget {
  const AssuranceForm({
    super.key,
    required this.action,
    required this.asset,
    this.item = const {},
    this.catalog = const {},
  });
  final String action, asset;
  final Map<String, dynamic> item, catalog;
  @override
  ConsumerState<AssuranceForm> createState() => _AssuranceFormState();
}

class _AssuranceFormState extends ConsumerState<AssuranceForm> {
  final _form = GlobalKey<FormState>();
  String _operation = const Uuid().v4();
  final Map<String, TextEditingController> _fields = {};
  late final AssuranceRepository _repository;
  late final Future<String?> _initialAccount;
  String? _person, _component, _path;
  String _lifecycle = 'active', _type = 'image/jpeg';
  Uint8List? _photo;
  MaintenanceWrite? _pending;
  bool _busy = false, _dirty = false, _saved = false;
  Object? _error;
  @override
  void initState() {
    super.initState();
    _repository = ref.read(assuranceRepositoryProvider);
    _initialAccount = ref.read(profileProvider.future).then((p) => p?.id);
    final custody = widget.catalog['custody'] as Map? ?? {};
    for (final name in [
      'site',
      'reason',
      'title',
      'inspected_on',
      'expires_on',
      'procedure_notes',
      'result_notes',
      'note',
    ]) {
      _fields[name] = TextEditingController(
        text: name == 'site' ? custody['site'] as String? ?? '' : '',
      );
    }
    _person = custody['responsible_id'] as String?;
    _lifecycle = custody['lifecycle'] as String? ?? 'active';
  }

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    if (!_saved && _path != null) {
      unawaited(_repository.discard(_path!).catchError((Object _) {}));
    }
    super.dispose();
  }

  Future<void> _pick() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final image = await ref.read(inspectionPhotoPickerProvider)();
      if (image == null) return;
      final bytes = await image.readAsBytes();
      if (bytes.length > 10 * 1024 * 1024) throw StateError('Photo too large');
      final jpeg = bytes.length > 2 && bytes[0] == 255 && bytes[1] == 216;
      final png =
          bytes.length > 4 &&
          bytes[0] == 137 &&
          bytes[1] == 80 &&
          bytes[2] == 78 &&
          bytes[3] == 71;
      if (!jpeg && !png) throw StateError('Choose a JPEG or PNG photo');
      if (!mounted) return;
      final user = ref.read(profileProvider).valueOrNull?.id;
      if (user == null) return;
      final oldPath = _path;
      if (oldPath != null) {
        unawaited(_repository.discard(oldPath).catchError((Object _) {}));
      }
      setState(() {
        _operation = const Uuid().v4();
        _photo = bytes;
        _type = jpeg ? 'image/jpeg' : 'image/png';
        _path = '${widget.asset}/$user/$_operation.${jpeg ? 'jpg' : 'png'}';
        _dirty = true;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final es = isSpanish(context);
    if (widget.action == 'submit' && _photo == null) {
      setState(
        () => _error = StateError(
          es ? 'Añade una foto de evidencia.' : 'Add an evidence photo.',
        ),
      );
      return;
    }
    _pending ??= MaintenanceWrite({
      for (final e in _fields.entries) e.key: e.value.text.trim(),
      'responsible_id': _person,
      'lifecycle': _lifecycle,
      'component_id': _component,
      'evidence_path': _path,
      'submission_id': (widget.item['pending'] as Map?)?['id'],
    }, operationId: _operation);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final originalUser = await _initialAccount;
      final currentUser = (await ref.read(profileProvider.future))?.id;
      if (originalUser == null || currentUser != originalUser) {
        throw StateError('Account changed. Reopen this form.');
      }
      if (widget.action == 'submit') {
        await _repository.upload(_path!, _photo!, _type);
      }
      if ((await ref.read(profileProvider.future))?.id != originalUser) {
        throw StateError('Account changed. Reopen this form.');
      }
      final custody = widget.catalog['custody'] as Map? ?? {};
      final revision = widget.action == 'transfer'
          ? custody['revision']
          : widget.item['revision'];
      await _repository.write(
        widget.action,
        ['transfer', 'create'].contains(widget.action)
            ? widget.asset
            : widget.item['id'] as String,
        (revision as num?)?.toInt() ?? 0,
        _pending!.id,
        _pending!.data,
      );
      if (!mounted) return;
      _saved = true;
      _dirty = false;
      _pending = null;
      ref.invalidate(assuranceContextProvider);
      ref.invalidate(inspectionRegisterProvider);
      refreshMaintenance(ref, assetsChanged: true);
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          if (maintenanceWriteWasRejected(e)) _pending = null;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final es = isSpanish(context), frozen = _busy || _pending != null;
    final title = switch (widget.action) {
      'transfer' => es ? 'Registrar traslado' : 'Record transfer',
      'create' => es ? 'Añadir inspección' : 'Add inspection',
      'submit' => es ? 'Enviar renovación' : 'Submit renewal',
      'approve' => es ? 'Aprobar renovación' : 'Approve renewal',
      _ => es ? 'Devolver renovación' : 'Return renewal',
    };
    Widget field(
      String key,
      String en,
      String spanish, {
      int min = 3,
      int max = 2000,
      bool date = false,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        key: ValueKey(key),
        controller: _fields[key],
        enabled: !frozen,
        minLines: 1,
        maxLines: date ? 1 : 4,
        maxLength: max,
        decoration: InputDecoration(
          labelText: es ? spanish : en,
          helperText: date ? 'YYYY-MM-DD' : null,
          suffixIcon: date
              ? IconButton(
                  tooltip: es ? 'Elegir fecha' : 'Choose date',
                  icon: const Icon(Icons.calendar_month_outlined),
                  onPressed: frozen
                      ? null
                      : () async {
                          final now = DateTime.now();
                          final last = key == 'inspected_on'
                              ? now
                              : DateTime(2199, 12, 31);
                          final entered = inspectionDate(_fields[key]!.text);
                          final selected = await showDatePicker(
                            context: context,
                            initialDate:
                                entered != null &&
                                    !entered.isAfter(last) &&
                                    entered.year >= 1900
                                ? entered
                                : now,
                            firstDate: DateTime(1900),
                            lastDate: last,
                          );
                          if (selected != null && mounted) {
                            setState(() {
                              _fields[key]!.text = selected
                                  .toIso8601String()
                                  .substring(0, 10);
                              _dirty = true;
                            });
                          }
                        },
                )
              : null,
        ),
        onChanged: (_) => _dirty = true,
        validator: (value) {
          final text = value?.trim() ?? '';
          if (text.length < min) {
            return es ? 'Completa este campo' : 'Complete this field';
          }
          if (date) {
            final d = inspectionDate(text),
                inspected = inspectionDate(
                  _fields['inspected_on']!.text.trim(),
                );
            final now = DateTime.now();
            final today = DateTime(now.year, now.month, now.day);
            if (d == null ||
                d.year < 1900 ||
                d.year > 2199 ||
                (key == 'inspected_on' && d.isAfter(today)) ||
                (key == 'expires_on' &&
                    inspected != null &&
                    d.isBefore(inspected))) {
              return es ? 'Revisa la fecha' : 'Check the date';
            }
          }
          return null;
        },
      ),
    );
    Widget select(
      String label,
      String? value,
      List<Map<String, dynamic>> rows,
      ValueChanged<String?> change, {
      bool required = true,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: AppDropdownField<String>(
        initialValue: rows.any((r) => r['id'] == value) ? value : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: rows
            .map(
              (r) => DropdownMenuItem(
                value: r['id'] as String,
                child: Text(r['name'] as String? ?? ''),
              ),
            )
            .toList(),
        onChanged: frozen
            ? null
            : (v) => setState(() {
                change(v);
                _dirty = true;
              }),
        validator: (v) => required && v == null
            ? (es ? 'Selecciona una opción' : 'Select an option')
            : null,
      ),
    );
    return UnsavedFormGuard(
      isDirty: () => !_saved && (_dirty || _pending != null),
      controllers: _fields.values.toList(),
      busy: _busy,
      fallbackRoute: '/assurance/assets/${widget.asset}',
      child: Scaffold(
        appBar: AppBar(title: Text(title)),
        body: SafeArea(
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (widget.action == 'transfer') ...[
                  field(
                    'site',
                    'Site / location',
                    'Sitio / ubicación',
                    min: 1,
                    max: 200,
                  ),
                  select(
                    es ? 'Persona responsable' : 'Responsible person',
                    _person,
                    maintenanceRows(widget.catalog['people']),
                    (v) => _person = v,
                  ),
                  select(
                    es ? 'Estado del ciclo de vida' : 'Lifecycle',
                    _lifecycle,
                    [
                      for (final s in ['active', 'stored', 'retired'])
                        {'id': s, 'name': assuranceLabel(s, es)},
                    ],
                    (v) => _lifecycle = v!,
                  ),
                  field('reason', 'Reason for transfer', 'Motivo del traslado'),
                ],
                if (widget.action == 'create') ...[
                  field(
                    'title',
                    'Inspection name',
                    'Nombre de la inspección',
                    max: 200,
                  ),
                  select(
                    es ? 'Componente (opcional)' : 'Component (optional)',
                    _component,
                    [
                      {
                        'id': '',
                        'name': es ? 'Equipo completo' : 'Whole asset',
                      },
                      ...maintenanceRows(widget.catalog['components']),
                    ],
                    (v) => _component = v,
                    required: false,
                  ),
                ],
                if (widget.action == 'submit') ...[
                  field(
                    'inspected_on',
                    'Inspection date',
                    'Fecha de inspección',
                    date: true,
                    max: 10,
                  ),
                  field(
                    'expires_on',
                    'Expiry date',
                    'Fecha de vencimiento',
                    date: true,
                    max: 10,
                  ),
                  field(
                    'procedure_notes',
                    'Procedure / reference',
                    'Procedimiento / referencia',
                    max: 4000,
                  ),
                  field(
                    'result_notes',
                    'Results and findings',
                    'Resultados y hallazgos',
                    max: 4000,
                  ),
                  if (_photo != null)
                    Image.memory(_photo!, height: 180, fit: BoxFit.contain),
                  OutlinedButton.icon(
                    onPressed: frozen ? null : _pick,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: Text(
                      _photo == null
                          ? (es
                                ? 'Añadir foto de evidencia'
                                : 'Add evidence photo')
                          : (es ? 'Cambiar foto' : 'Change photo'),
                    ),
                  ),
                  Text(
                    es
                        ? 'La aprobación del responsable activa esta renovación.'
                        : 'Manager approval makes this renewal effective.',
                  ),
                  const SizedBox(height: 16),
                ],
                if (widget.action == 'approve' || widget.action == 'return')
                  field('note', 'Review note', 'Nota de revisión'),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      _error is StateError &&
                              (_error as StateError).message
                                  .toString()
                                  .startsWith('Account changed')
                          ? (es
                                ? 'La cuenta cambió. Vuelve a abrir este formulario.'
                                : 'Account changed. Reopen this form.')
                          : _error is StateError
                          ? (es
                                ? 'Añade una foto JPEG o PNG de hasta 10 MB.'
                                : 'Add a JPEG or PNG evidence photo, up to 10 MB.')
                          : maintenanceError(_error!, es),
                    ),
                  ),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: Text(
                    _busy
                        ? (es ? 'Guardando…' : 'Saving…')
                        : _pending != null
                        ? (es ? 'Reintentar guardado' : 'Retry save')
                        : title,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
