import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vortice_app/core/app_dropdown_field.dart';
import 'package:vortice_app/core/unsaved_form_guard.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/fleet/fleet_widgets.dart';
import 'package:vortice_app/features/maintenance/maintenance_repository.dart';
import 'coordination_repository.dart';
import 'coordination_labels.dart';

final discussionPhotoPickerProvider =
    Provider<Future<XFile?> Function(ImageSource)>(
      (ref) =>
          (source) => ImagePicker().pickImage(
            source: source,
            maxWidth: 2000,
            imageQuality: 85,
          ),
    );

class DiscussionWriteScreen extends ConsumerStatefulWidget {
  const DiscussionWriteScreen({
    super.key,
    required this.subject,
    required this.title,
    required this.providerTeam,
  });
  final Subject subject;
  final String title;
  final bool providerTeam;
  @override
  ConsumerState<DiscussionWriteScreen> createState() =>
      _DiscussionWriteScreenState();
}

class _DiscussionWriteScreenState extends ConsumerState<DiscussionWriteScreen> {
  final _form = GlobalKey<FormState>();
  final _body = TextEditingController(), _next = TextEditingController();
  final _operation = const Uuid().v4();
  final _mentions = <String>{};
  final _uploaded = <String>{};
  final _photos =
      <({String path, String name, String type, Uint8List bytes})>[];
  String _kind = 'comment', _visibility = 'team', _isolation = 'unknown';
  bool _busy = false, _picking = false, _sent = false;
  MaintenanceWrite? _pending;
  Object? _error;
  @override
  void dispose() {
    _body.dispose();
    _next.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final file = await ref.read(discussionPhotoPickerProvider)(source);
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      if (bytes.length > 8 * 1024 * 1024) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              fleetText(
                context,
                'Choose a photo smaller than 8 MB.',
                'Elige una foto de menos de 8 MB.',
              ),
            ),
          ),
        );
        return;
      }
      final user = ref.read(profileProvider).valueOrNull?.id;
      if (user == null) return;
      final extension = file.name.toLowerCase().endsWith('.png')
          ? 'png'
          : file.name.toLowerCase().endsWith('.webp')
          ? 'webp'
          : 'jpg';
      final name = file.name.isEmpty ? 'Photo.$extension' : file.name;
      setState(
        () => _photos.add((
          path:
              '${widget.subject.kind}/${widget.subject.id}/$user/$_operation/${const Uuid().v4()}.$extension',
          name: name.length > 120 ? name.substring(0, 120) : name,
          type: extension == 'jpg' ? 'image/jpeg' : 'image/$extension',
          bytes: bytes,
        )),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _send() async {
    if (_pending == null && !_form.currentState!.validate()) return;
    _pending ??= MaintenanceWrite({
      'kind': _kind,
      'visibility': _visibility,
      'body': _body.text.trim(),
      if (_kind == 'handover') 'isolation': _isolation,
      if (_kind == 'handover') 'next_steps': _next.text.trim(),
      'mentions': _mentions.toList(),
      'attachments': [
        for (final photo in _photos) {'name': photo.name, 'path': photo.path},
      ],
    }, operationId: _operation);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repository = ref.read(coordinationRepositoryProvider);
      for (final photo in _photos) {
        if (!_uploaded.contains(photo.path)) {
          await repository.upload(photo.path, photo.bytes, photo.type);
          _uploaded.add(photo.path);
        }
      }
      await repository.post(widget.subject, _pending!.id, _pending!.data);
      if (mounted) {
        setState(() {
          _sent = true;
          _pending = null;
          _busy = false;
        });
        await WidgetsBinding.instance.endOfFrame;
        if (mounted) Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          if (maintenanceWriteWasRejected(error) ||
              (error is StorageException &&
                  [
                    '400',
                    '403',
                    '404',
                    '413',
                    '415',
                    '422',
                  ].contains(error.statusCode))) {
            _pending = null;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final es = fleetSpanish(context),
        frozen = _busy || _picking || _pending != null;
    final peopleQuery = (subject: widget.subject, visibility: _visibility);
    return UnsavedFormGuard(
      isDirty: () =>
          !_sent &&
          (_body.text.isNotEmpty ||
              _next.text.isNotEmpty ||
              _photos.isNotEmpty ||
              _mentions.isNotEmpty),
      controllers: [_body, _next],
      busy: _busy || _picking,
      fallbackRoute: '/discussion/${widget.subject.kind}/${widget.subject.id}',
      child: Scaffold(
        appBar: AppBar(title: Text(es ? 'Nueva nota' : 'New note')),
        body: SafeArea(
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  widget.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                AppDropdownField<String>(
                  initialValue: _kind,
                  decoration: InputDecoration(
                    labelText: es ? 'Tipo de nota' : 'Note type',
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'comment',
                      child: Text(es ? 'Comentario' : 'Comment'),
                    ),
                    DropdownMenuItem(
                      value: 'handover',
                      child: Text(es ? 'Relevo de turno' : 'Shift handover'),
                    ),
                  ],
                  onChanged: frozen
                      ? null
                      : (value) => setState(() => _kind = value!),
                ),
                const SizedBox(height: 16),
                AppDropdownField<String>(
                  initialValue: _visibility,
                  decoration: InputDecoration(
                    labelText: es ? 'Quién puede verla' : 'Who can see this',
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'team',
                      child: Text(es ? 'Solo mi equipo' : 'My team only'),
                    ),
                    DropdownMenuItem(
                      value: 'shared',
                      child: Text(
                        es ? 'Compartir entre equipos' : 'Share across teams',
                      ),
                    ),
                  ],
                  onChanged: frozen
                      ? null
                      : (value) => setState(() {
                          _visibility = value!;
                          _mentions.clear();
                        }),
                ),
                const SizedBox(height: 12),
                Text(
                  _visibility == 'shared'
                      ? (es
                            ? 'Visible para los participantes autorizados de la empresa y el proveedor.'
                            : 'Visible to authorized company and provider participants.')
                      : widget.providerTeam
                      ? (es
                            ? 'Privada para el personal autorizado del proveedor.'
                            : 'Private to authorized provider staff.')
                      : (es
                            ? 'Privada para los participantes autorizados de tu empresa.'
                            : 'Private to authorized participants in your company.'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _body,
                  enabled: !frozen,
                  minLines: 3,
                  maxLines: 8,
                  maxLength: 4000,
                  decoration: InputDecoration(
                    labelText: es
                        ? 'Qué ocurrió / situación actual'
                        : 'What happened / current situation',
                  ),
                  validator: (value) => (value?.trim().length ?? 0) < 3
                      ? (es
                            ? 'Escribe al menos 3 caracteres.'
                            : 'Enter at least 3 characters.')
                      : null,
                ),
                const SizedBox(height: 16),
                if (_kind == 'handover') ...[
                  AppDropdownField<String>(
                    initialValue: _isolation,
                    decoration: InputDecoration(
                      labelText: es
                          ? 'Estado de aislamiento'
                          : 'Isolation status',
                    ),
                    items: [
                      for (final key in isolationStates.keys)
                        DropdownMenuItem(
                          value: key,
                          child: Text(
                            coordinationLabel(isolationStates, key, es),
                          ),
                        ),
                    ],
                    onChanged: frozen
                        ? null
                        : (value) => setState(() => _isolation = value!),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _next,
                    enabled: !frozen,
                    minLines: 3,
                    maxLines: 8,
                    maxLength: 3000,
                    decoration: InputDecoration(
                      labelText: es
                          ? 'Próximo turno / trabajo pendiente'
                          : 'Next shift / outstanding work',
                    ),
                    validator: (value) => (value?.trim().length ?? 0) < 3
                        ? (es
                              ? 'Indica qué queda pendiente.'
                              : 'Describe what remains to be done.')
                        : null,
                  ),
                  const SizedBox(height: 16),
                ],
                Text(
                  es ? 'Mencionar personas' : 'Mention people',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  es
                      ? 'Las menciones aparecen en su bandeja de entrada. No otorgan acceso nuevo.'
                      : 'Mentions appear in their inbox. They do not grant new access.',
                ),
                ref
                    .watch(coordinationPeopleProvider(peopleQuery))
                    .when(
                      loading: () => const LinearProgressIndicator(),
                      error: (error, _) => FleetError(
                        error: error,
                        onRetry: () => ref.invalidate(
                          coordinationPeopleProvider(peopleQuery),
                        ),
                      ),
                      data: (people) => people.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                es
                                    ? 'No hay otros participantes disponibles.'
                                    : 'No other participants are available.',
                              ),
                            )
                          : Column(
                              children: [
                                for (final person in people)
                                  CheckboxListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(
                                      person['name'] as String? ?? '',
                                    ),
                                    value: _mentions.contains(person['id']),
                                    onChanged:
                                        frozen ||
                                            (!_mentions.contains(
                                                  person['id'],
                                                ) &&
                                                _mentions.length >= 10)
                                        ? null
                                        : (checked) => setState(() {
                                            if (checked == true) {
                                              _mentions.add(
                                                person['id'] as String,
                                              );
                                            } else {
                                              _mentions.remove(person['id']);
                                            }
                                          }),
                                  ),
                              ],
                            ),
                    ),
                const SizedBox(height: 16),
                Text(
                  '${es ? 'Fotos privadas' : 'Private photos'} (${_photos.length}/6)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                for (final photo in _photos)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(
                            photo.bytes,
                            width: 64,
                            height: 64,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const SizedBox(
                              width: 64,
                              height: 64,
                              child: Icon(Icons.broken_image_outlined),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Text(photo.name)),
                        IconButton(
                          tooltip: es ? 'Quitar foto' : 'Remove photo',
                          onPressed: frozen
                              ? null
                              : () => setState(() => _photos.remove(photo)),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    OutlinedButton.icon(
                      onPressed: frozen || _photos.length >= 6
                          ? null
                          : () => _pick(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: Text(es ? 'Galería' : 'Gallery'),
                    ),
                    OutlinedButton.icon(
                      onPressed: frozen || _photos.length >= 6
                          ? null
                          : () => _pick(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: Text(es ? 'Cámara' : 'Camera'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      maintenanceError(_error!, es),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (_pending != null && !_busy)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      es
                          ? 'No se confirmó la respuesta. Reintentar enviará exactamente la misma nota una sola vez.'
                          : 'The response was not confirmed. Retry will send exactly the same note with one effect.',
                    ),
                  ),
                FilledButton.icon(
                  key: const Key('post-coordination'),
                  onPressed: _busy || _picking ? null : _send,
                  icon: const Icon(Icons.send_outlined),
                  label: Text(
                    _busy
                        ? (es ? 'Enviando…' : 'Sending…')
                        : _pending != null
                        ? (es ? 'Reintentar envío' : 'Retry sending')
                        : (es ? 'Publicar nota' : 'Post note'),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  es
                      ? 'Se requiere conexión. Las correcciones se publican como una nueva nota.'
                      : 'Connection required. Post corrections as a new note.',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
