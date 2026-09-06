import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/core/unsaved_form_guard.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:vortice_app/core/theme.dart';
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
  const ServiceRequestFormScreen({super.key});

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
    if (!_formKey.currentState!.validate()) return;

    final result = await ref
        .read(serviceRequestControllerProvider.notifier)
        .submitRequest(
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.warning ?? 'Request sent to Vórtice.'),
          backgroundColor: result.warning == null
              ? AppColors.success
              : AppColors.warning,
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(friendlyError(context, error)),
        backgroundColor: AppColors.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final assetsAsync = ref.watch(visibleAssetsProvider);
    final isLoading = ref.watch(serviceRequestControllerProvider).isLoading;

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
          title: const Text('Request Service'),
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
                          title: 'Machine',
                          subtitle: 'Pick the asset this request is for.',
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
                          title: 'Other asset',
                          child: TextFormField(
                            controller: _otherAssetCtrl,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              hintText:
                                  'Machine name, unit number, or description',
                              prefixIcon: Icon(Icons.directions_boat_outlined),
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
                        title: 'Request type',
                        subtitle: 'Choose the closest match.',
                        child: ServiceRequestFormRequestTypeField(
                          value: _kind,
                          onChanged: (value) => setState(() => _kind = value),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ServiceRequestFormCard(
                        title: 'Engine hours',
                        subtitle:
                            'Optional, but this will prefill the work order if you know it.',
                        child: TextFormField(
                          controller: _engineHoursCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            hintText: 'e.g. 1250.5',
                            prefixIcon: Icon(Icons.timer_outlined),
                          ),
                          validator: validateServiceRequestEngineHours,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ServiceRequestFormCard(
                        title: 'Details',
                        subtitle:
                            'Add symptoms, warning signs, leaks or damage, unusual noises, when it started, and anything else that helps the technician prepare.',
                        child: TextFormField(
                          controller: _descriptionCtrl,
                          minLines: 5,
                          maxLines: 8,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            hintText: 'Describe the issue or service needed...',
                            alignLabelWithHint: true,
                          ),
                          validator: validateServiceRequestDescription,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ServiceRequestFormCard(
                        title: 'Contact',
                        subtitle: 'Best number for a call or WhatsApp message.',
                        child: TextFormField(
                          controller: _contactCtrl,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.done,
                          decoration: const InputDecoration(
                            hintText: 'Phone number or WhatsApp',
                            prefixIcon: Icon(Icons.phone_outlined),
                          ),
                          validator: validateServiceRequestContact,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ServiceRequestFormCard(
                        title: 'Photos',
                        subtitle:
                            'Optional, but helpful for leaks, damage, alarms, or access.',
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
