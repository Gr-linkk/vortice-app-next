import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:vortice_app/core/unsaved_form_guard.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/coordination/discussion_write_screen.dart';
import 'package:vortice_app/features/maintenance/maintenance_repository.dart';
import 'announcements_repository.dart';

class AnnouncementWriteScreen extends ConsumerStatefulWidget {
  const AnnouncementWriteScreen({
    super.key,
    required this.organization,
    required this.organizationName,
  });
  final String organization, organizationName;
  @override
  ConsumerState<AnnouncementWriteScreen> createState() =>
      _AnnouncementWriteScreenState();
}

class _AnnouncementWriteScreenState
    extends ConsumerState<AnnouncementWriteScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController(), _body = TextEditingController();
  final _operation = const Uuid().v4();
  final _photos =
      <({String path, String name, String type, Uint8List bytes})>[];
  final _uploaded = <String>{};
  late final String? _account;
  MaintenanceWrite? _pending;
  Object? _error;
  bool _busy = false, _picking = false, _sent = false;
  bool get _sameAccount =>
      mounted && ref.read(sessionProvider)?.user.id == _account;
  @override
  void initState() {
    super.initState();
    _account = ref.read(sessionProvider)?.user.id;
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    if (_photos.length >= 6 || !_sameAccount) return;
    setState(() => _picking = true);
    try {
      final file = await ref.read(discussionPhotoPickerProvider)(source);
      if (file == null || !_sameAccount) return;
      final bytes = await file.readAsBytes();
      if (!_sameAccount) return;
      if (bytes.length > 8 * 1024 * 1024) {
        throw StateError('Choose a photo smaller than 8 MB');
      }
      final ext = file.name.toLowerCase().endsWith('.png')
          ? 'png'
          : file.name.toLowerCase().endsWith('.webp')
          ? 'webp'
          : 'jpg';
      final name = file.name.isEmpty ? 'Photo.$ext' : file.name;
      setState(
        () => _photos.add((
          path:
              '${widget.organization}/$_account/$_operation/${const Uuid().v4()}.$ext',
          name: name.length > 120 ? name.substring(0, 120) : name,
          type: ext == 'jpg' ? 'image/jpeg' : 'image/$ext',
          bytes: bytes,
        )),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _publish() async {
    if (!_sameAccount ||
        (_pending == null && !_form.currentState!.validate())) {
      return;
    }
    _pending ??= MaintenanceWrite({
      'title': _title.text.trim(),
      'body': _body.text.trim(),
      'attachments': [
        for (final photo in _photos) {'name': photo.name, 'path': photo.path},
      ],
    }, operationId: _operation);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repository = ref.read(announcementsRepositoryProvider);
      for (final photo in _photos) {
        if (!_uploaded.contains(photo.path)) {
          await repository.upload(photo.path, photo.bytes, photo.type);
          _uploaded.add(photo.path);
        }
      }
      await repository.publish(
        widget.organization,
        _pending!.id,
        _pending!.data,
      );
      if (!_sameAccount) return;
      setState(() {
        _sent = true;
        _pending = null;
        _busy = false;
      });
      await WidgetsBinding.instance.endOfFrame;
      if (mounted && _sameAccount) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          if (maintenanceWriteWasRejected(error) ||
              error is StorageException &&
                  [
                    '400',
                    '403',
                    '404',
                    '413',
                    '415',
                    '422',
                  ].contains(error.statusCode)) {
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
    final es = isSpanish(context),
        frozen = _busy || _picking || _pending != null;
    if (ref.watch(sessionProvider)?.user.id != _account) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Text(
            es
                ? 'La cuenta cambió. Vuelve a abrir los anuncios.'
                : 'The account changed. Reopen announcements.',
          ),
        ),
      );
    }
    return UnsavedFormGuard(
      isDirty: () =>
          !_sent &&
          (_title.text.isNotEmpty ||
              _body.text.isNotEmpty ||
              _photos.isNotEmpty),
      controllers: [_title, _body],
      busy: _busy || _picking,
      fallbackRoute: '/announcements',
      child: Scaffold(
        appBar: AppBar(title: Text(es ? 'Nuevo anuncio' : 'New announcement')),
        body: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                widget.organizationName,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                es
                    ? 'Todos los miembros activos de esta organización podrán leer el anuncio.'
                    : 'All active members of this organization will be able to read the announcement.',
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _title,
                enabled: !frozen,
                maxLength: 160,
                decoration: InputDecoration(labelText: es ? 'Título' : 'Title'),
                validator: (value) => (value?.trim().length ?? 0) < 3
                    ? (es
                          ? 'Añade un título descriptivo.'
                          : 'Add a descriptive title.')
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _body,
                enabled: !frozen,
                minLines: 5,
                maxLines: 12,
                maxLength: 4000,
                decoration: InputDecoration(
                  labelText: es ? 'Mensaje' : 'Message',
                ),
                validator: (value) => (value?.trim().isEmpty ?? true)
                    ? (es ? 'Añade el mensaje.' : 'Add the message.')
                    : null,
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: frozen || _photos.length >= 6
                        ? null
                        : () => _pick(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: Text(es ? 'Elegir fotos' : 'Choose photos'),
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
              for (final photo in _photos)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    children: [
                      Image.memory(
                        photo.bytes,
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(photo.name)),
                      IconButton(
                        onPressed: frozen
                            ? null
                            : () => setState(() => _photos.remove(photo)),
                        tooltip: es ? 'Quitar foto' : 'Remove photo',
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(maintenanceError(_error!, es)),
                ),
              const SizedBox(height: 24),
              SafeArea(
                top: false,
                child: FilledButton.icon(
                  onPressed: _busy || _picking ? null : _publish,
                  icon: const Icon(Icons.campaign_outlined),
                  label: Text(
                    _busy
                        ? (es ? 'Publicando…' : 'Publishing…')
                        : _pending != null
                        ? (es
                              ? 'Reintentar el mismo anuncio'
                              : 'Retry same announcement')
                        : (es ? 'Publicar anuncio' : 'Publish announcement'),
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
