import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vortice_app/core/account_storage.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/core/unsaved_form_guard.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:vortice_app/features/assets/asset_provider.dart';
import 'package:vortice_app/features/service_requests/service_request_form_asset_field.dart';
import 'package:vortice_app/features/service_requests/service_request_form_card.dart';
import 'package:vortice_app/features/service_requests/service_request_form_intro_card.dart';
import 'package:vortice_app/features/service_requests/service_request_form_photo_field.dart';
import 'package:vortice_app/features/service_requests/service_request_form_request_type_field.dart';
import 'package:vortice_app/features/service_requests/service_request_form_submit_bar.dart';
import 'package:vortice_app/features/service_requests/service_request_form_support.dart';
import 'package:vortice_app/features/service_requests/service_request_provider.dart';
import 'package:vortice_app/models/service_request.dart';

class ServiceRequestFormScreen extends ConsumerStatefulWidget {
  const ServiceRequestFormScreen({
    super.key,
    this.draftStorageKey = 'service_request_draft',
  });
  final String draftStorageKey;

  @override
  ConsumerState<ServiceRequestFormScreen> createState() =>
      _ServiceRequestFormScreenState();
}

class _ServiceRequestFormScreenState
    extends ConsumerState<ServiceRequestFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionCtrl = TextEditingController();
  final _otherAssetCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _engineHoursCtrl = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final List<Uint8List> _photos = [];

  ServiceRequestKind _kind = ServiceRequestKind.breakdown;
  String? _assetSelection;

  String _requestId = const Uuid().v4();
  late final String _account;
  String get _draftKey => accountStorageKey(_account, widget.draftStorageKey);
  bool _restoring = true;
  bool _submitting = false;
  Object? _draftError;

  @override
  void initState() {
    super.initState();
    _account = ref.read(sessionProvider)?.user.id ?? 'signed_out';
    _restoreDraft();
  }

  Future<void> _restoreDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_draftKey);
      if (!mounted || ref.read(sessionProvider)?.user.id != _account) return;
      if (raw != null) {
        final data = jsonDecode(raw) as Map;
        _requestId = data['id'] as String? ?? _requestId;
        _assetSelection =
            data['asset_id'] as String? ?? kServiceRequestOtherAssetValue;
        _otherAssetCtrl.text = data['other_asset_name'] as String? ?? '';
        _descriptionCtrl.text = data['description'] as String? ?? '';
        _contactCtrl.text = data['contact_phone_or_whatsapp'] as String? ?? '';
        _engineHoursCtrl.text = data['engine_hours']?.toString() ?? '';
        _kind =
            ServiceRequestKind.values
                .where((k) => k.label == data['title'])
                .firstOrNull ??
            ServiceRequestKind.otherIssue;
        _photos.addAll(
          (data['photos'] as List? ?? const []).cast<String>().map(
            base64Decode,
          ),
        );
      }
    } catch (error) {
      _draftError = error;
      // Retain the unreadable draft; never replace it with a blank submission.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isSpanish(context)
                  ? 'No se pudo leer el borrador guardado. Sigue en este dispositivo.'
                  : 'The saved draft could not be read. It remains on this device.',
            ),
          ),
        );
      }
      if (mounted) setState(() => _restoring = false);
      return;
    }
    if (mounted) setState(() => _restoring = false);
  }

  Future<void> _saveDraft() async {
    if (ref.read(sessionProvider)?.user.id != _account) {
      throw const AccountChangedException();
    }
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setString(
      _draftKey,
      jsonEncode({
        'id': _requestId,
        'asset_id': resolveServiceRequestAssetId(_assetSelection),
        'other_asset_name': _otherAssetCtrl.text,
        'description': _descriptionCtrl.text,
        'contact_phone_or_whatsapp': _contactCtrl.text,
        'engine_hours': _engineHoursCtrl.text,
        'title': _kind.label,
        'photos': _photos.map(base64Encode).toList(),
      }),
    );
    if (!saved) throw StateError('Could not preserve this request for retry');
  }

  @override
  void dispose() {
    _descriptionCtrl.dispose();
    _otherAssetCtrl.dispose();
    _contactCtrl.dispose();
    _engineHoursCtrl.dispose();
    super.dispose();
  }

  bool get _isOtherAsset => isOtherAssetSelection(_assetSelection);

  Future<void> _pickPhotos() async {
    final files = await _picker.pickMultiImage(
      maxWidth: 1920,
      maxHeight: 1080,
      imageQuality: 85,
    );
    if (files.isEmpty) return;

    final bytes = <Uint8List>[];
    for (final file in files) {
      bytes.add(await file.readAsBytes());
    }
    if (!mounted) return;
    setState(() => _photos.addAll(bytes));
  }

  Future<void> _takePhoto() async {
    final file = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1920,
      maxHeight: 1080,
      imageQuality: 85,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() => _photos.add(bytes));
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      await _saveDraft();
      final result = await ref
          .read(serviceRequestControllerProvider.notifier)
          .submitRequest(
            requestId: _requestId,
            requestTypeLabel: _kind.label,
            description: _descriptionCtrl.text,
            contactPhoneOrWhatsapp: _contactCtrl.text,
            assetId: resolveServiceRequestAssetId(_assetSelection),
            otherAssetName: resolveServiceRequestOtherAssetName(
              _assetSelection,
              _otherAssetCtrl.text,
            ),
            engineHours: parseServiceRequestEngineHours(_engineHoursCtrl.text),
            photos: _photos,
          );

      if (!mounted) return;
      if (result.success) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_draftKey);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.warning == null
                  ? (isSpanish(context)
                        ? 'Solicitud enviada.'
                        : 'Request submitted.')
                  : (isSpanish(context)
                        ? 'Guardado en este dispositivo. Revisa Guardado y sincronización.'
                        : 'Saved on this device. Check Saved work and sync.'),
            ),
          ),
        );
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/client/service-requests');
        }
        return;
      }

      final error = ref.read(serviceRequestControllerProvider).error;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyError(context, error))));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(context, error))));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_draftError != null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              isSpanish(context)
                  ? 'No se pudo leer el borrador. Se conserva en este dispositivo; pide ayuda antes de continuar.'
                  : 'The draft could not be read. It remains on this device; ask for help before continuing.',
            ),
          ),
        ),
      );
    }
    final assetsAsync = ref.watch(visibleAssetsProvider);
    final isLoading =
        _restoring ||
        _submitting ||
        ref.watch(serviceRequestControllerProvider).isLoading;

    return UnsavedFormGuard(
      controllers: [
        _descriptionCtrl,
        _otherAssetCtrl,
        _contactCtrl,
        _engineHoursCtrl,
      ],
      isDirty: () =>
          _descriptionCtrl.text.isNotEmpty ||
          _otherAssetCtrl.text.isNotEmpty ||
          _contactCtrl.text.isNotEmpty ||
          _engineHoursCtrl.text.isNotEmpty ||
          _photos.isNotEmpty ||
          _assetSelection != null ||
          _kind != ServiceRequestKind.breakdown,
      busy: isLoading,
      fallbackRoute: '/client/service-requests',
      child: Scaffold(
        appBar: AppBar(
          leading: const FormBackButton(
            fallbackRoute: '/client/service-requests',
          ),
          title: Text(requestText(context, 'Request Service')),
        ),
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      const ServiceRequestFormIntroCard(),
                      const SizedBox(height: 16),
                      assetsAsync.when(
                        loading: () => const LinearProgressIndicator(),
                        error: (error, _) => AppErrorState(
                          error: error,
                          onRetry: () => ref.invalidate(visibleAssetsProvider),
                        ),
                        data: (assets) => ServiceRequestFormCard(
                          title: requestText(context, 'Machine'),
                          subtitle: requestText(
                            context,
                            'Pick the asset this request is for.',
                          ),
                          child: ServiceRequestFormAssetField(
                            assets: assets,
                            value: _assetSelection,
                            onChanged: (value) =>
                                setState(() => _assetSelection = value),
                          ),
                        ),
                      ),
                      if (_isOtherAsset) ...[
                        const SizedBox(height: 12),
                        ServiceRequestFormCard(
                          title: requestText(context, 'Other asset'),
                          child: TextFormField(
                            controller: _otherAssetCtrl,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              hintText: requestText(
                                context,
                                'Machine name, unit number, or description',
                              ),
                              prefixIcon: const Icon(
                                Icons.directions_boat_outlined,
                              ),
                            ),
                            validator: (value) =>
                                validateServiceRequestOtherAssetName(
                                  value,
                                  isOtherAsset: _isOtherAsset,
                                ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      ServiceRequestFormCard(
                        title: requestText(context, 'Request type'),
                        subtitle: requestText(
                          context,
                          'Choose the closest match.',
                        ),
                        child: ServiceRequestFormRequestTypeField(
                          value: _kind,
                          onChanged: (value) => setState(() => _kind = value),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ServiceRequestFormCard(
                        title: requestText(context, 'Engine hours'),
                        subtitle: requestText(
                          context,
                          'Optional, but this will prefill the work order if you know it.',
                        ),
                        child: TextFormField(
                          controller: _engineHoursCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            hintText: requestText(context, 'e.g. 1250.5'),
                            prefixIcon: const Icon(Icons.timer_outlined),
                          ),
                          validator: (value) {
                            final error = validateServiceRequestEngineHours(
                              value,
                            );
                            return error == null
                                ? null
                                : requestText(context, error);
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      ServiceRequestFormCard(
                        title: requestText(context, 'Details'),
                        subtitle: requestText(
                          context,
                          'Add symptoms, warning signs, leaks or damage, unusual noises, when it started, and anything else that helps the technician prepare.',
                        ),
                        child: TextFormField(
                          controller: _descriptionCtrl,
                          minLines: 5,
                          maxLines: 8,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            hintText: requestText(
                              context,
                              'Describe the issue or service needed...',
                            ),
                            alignLabelWithHint: true,
                          ),
                          validator: (value) {
                            final error = validateServiceRequestDescription(
                              value,
                            );
                            return error == null
                                ? null
                                : requestText(context, error);
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      ServiceRequestFormCard(
                        title: requestText(context, 'Contact'),
                        subtitle: requestText(
                          context,
                          'Best number for a call or WhatsApp message.',
                        ),
                        child: TextFormField(
                          controller: _contactCtrl,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.done,
                          decoration: InputDecoration(
                            hintText: requestText(
                              context,
                              'Phone number or WhatsApp',
                            ),
                            prefixIcon: const Icon(Icons.phone_outlined),
                          ),
                          validator: (value) {
                            final error = validateServiceRequestContact(value);
                            return error == null
                                ? null
                                : requestText(context, error);
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      ServiceRequestFormCard(
                        title: requestText(context, 'Photos'),
                        subtitle: requestText(
                          context,
                          'Optional, but helpful for leaks, damage, alarms, or access.',
                        ),
                        child: ServiceRequestFormPhotoField(
                          photos: _photos,
                          onAddPhotos: _pickPhotos,
                          onTakePhoto: _takePhoto,
                          onRemovePhoto: (index) =>
                              setState(() => _photos.removeAt(index)),
                        ),
                      ),
                    ],
                  ),
                ),
                ServiceRequestFormSubmitBar(
                  isLoading: isLoading,
                  onSubmit: _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
