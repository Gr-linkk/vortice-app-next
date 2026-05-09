import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/assets/asset_provider.dart';
import 'package:vortice_app/features/service_requests/service_request_provider.dart';
import 'package:vortice_app/models/asset.dart';
import 'package:vortice_app/models/service_request.dart';

class ServiceRequestFormScreen extends ConsumerStatefulWidget {
  const ServiceRequestFormScreen({super.key});

  @override
  ConsumerState<ServiceRequestFormScreen> createState() =>
      _ServiceRequestFormScreenState();
}

class _ServiceRequestFormScreenState
    extends ConsumerState<ServiceRequestFormScreen> {
  static const otherAssetValue = '__other_asset__';

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

  bool get _isOtherAsset => _assetSelection == otherAssetValue;

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
    setState(() => _photos.add(bytes));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final engineHoursText = _engineHoursCtrl.text.trim();
    final engineHours = engineHoursText.isEmpty
        ? null
        : double.tryParse(engineHoursText.replaceAll(',', ''));

    final result = await ref
        .read(serviceRequestControllerProvider.notifier)
        .submitRequest(
          requestTypeLabel: _kind.label,
          description: _descriptionCtrl.text,
          contactPhoneOrWhatsapp: _contactCtrl.text,
          assetId: _isOtherAsset ? null : _assetSelection,
          otherAssetName: _isOtherAsset ? _otherAssetCtrl.text.trim() : null,
          engineHours: engineHours,
          photos: _photos,
        );

    if (!mounted) return;
    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.warning ?? 'Request sent to Vórtice.'),
          backgroundColor:
              result.warning == null ? AppColors.success : AppColors.warning,
        ),
      );
      context.pop();
      return;
    }

    final error = ref.read(serviceRequestControllerProvider).error;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error?.toString() ?? 'Unable to send request.'),
        backgroundColor: AppColors.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final assetsAsync = ref.watch(visibleAssetsProvider);
    final isLoading = ref.watch(serviceRequestControllerProvider).isLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('Request Service')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    const _IntroCard(),
                    const SizedBox(height: 16),
                    assetsAsync.when(
                      loading: () => const LinearProgressIndicator(),
                      error: (_, __) => const SizedBox.shrink(),
                      data: (assets) => _FormCard(
                        title: 'Machine',
                        subtitle: 'Pick the asset this request is for.',
                        child: _AssetField(
                          assets: assets,
                          value: _assetSelection,
                          onChanged: (value) =>
                              setState(() => _assetSelection = value),
                        ),
                      ),
                    ),
                    if (_isOtherAsset) ...[
                      const SizedBox(height: 12),
                      _FormCard(
                        title: 'Other asset',
                        child: TextFormField(
                          controller: _otherAssetCtrl,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            hintText:
                                'Machine name, unit number, or description',
                            prefixIcon: Icon(Icons.directions_boat_outlined),
                          ),
                          validator: (value) {
                            if (_isOtherAsset &&
                                (value == null || value.trim().isEmpty)) {
                              return 'Please describe the asset';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    _FormCard(
                      title: 'Request type',
                      subtitle: 'Choose the closest match.',
                      child: _RequestTypeField(
                        value: _kind,
                        onChanged: (value) => setState(() => _kind = value),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _FormCard(
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
                        validator: (value) {
                          final text = value?.trim() ?? '';
                          if (text.isEmpty) return null;
                          final parsed =
                              double.tryParse(text.replaceAll(',', ''));
                          if (parsed == null || parsed < 0) {
                            return 'Enter valid engine hours';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    _FormCard(
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
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please describe the issue';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    _FormCard(
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
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please provide a phone number or WhatsApp';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    _FormCard(
                      title: 'Photos',
                      subtitle:
                          'Optional, but helpful for leaks, damage, alarms, or access.',
                      child: _PhotoField(
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
              _SubmitBar(
                isLoading: isLoading,
                onSubmit: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.support_agent_outlined, color: AppColors.primary),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Send Vórtice the key details so we can prepare faster and build the work order from clean information.',
              style: TextStyle(color: AppColors.textPrimary, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _FormCard extends StatelessWidget {
  const _FormCard({
    required this.title,
    required this.child,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                height: 1.3,
              ),
            ),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _AssetField extends StatelessWidget {
  const _AssetField({
    required this.assets,
    required this.value,
    required this.onChanged,
  });

  final List<Asset> assets;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: const InputDecoration(
        hintText: 'Select asset',
        prefixIcon: Icon(Icons.directions_boat_outlined),
      ),
      dropdownColor: AppColors.surfaceVariant,
      items: [
        ...assets.map(
          (asset) => DropdownMenuItem<String>(
            value: asset.id,
            child: Text(asset.name),
          ),
        ),
        const DropdownMenuItem<String>(
          value: _ServiceRequestFormScreenState.otherAssetValue,
          child: Text('Other'),
        ),
      ],
      onChanged: onChanged,
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please choose an asset or select Other';
        }
        return null;
      },
    );
  }
}

class _RequestTypeField extends StatelessWidget {
  const _RequestTypeField({
    required this.value,
    required this.onChanged,
  });

  final ServiceRequestKind value;
  final ValueChanged<ServiceRequestKind> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: ServiceRequestKind.values
          .map(
            (kind) => ChoiceChip(
              label: Text(kind.label),
              selected: kind == value,
              showCheckmark: false,
              avatar: Icon(
                kind.icon,
                size: 18,
                color: kind == value ? Colors.white : AppColors.textSecondary,
              ),
              onSelected: (_) => onChanged(kind),
              selectedColor: AppColors.primary,
              backgroundColor: AppColors.surfaceVariant,
              labelStyle: TextStyle(
                color: kind == value ? Colors.white : AppColors.textPrimary,
                fontWeight: kind == value ? FontWeight.w700 : FontWeight.w500,
              ),
              side: BorderSide(
                color: kind == value ? AppColors.primary : AppColors.cardBorder,
              ),
            ),
          )
          .toList(),
    );
  }
}

class _PhotoField extends StatelessWidget {
  const _PhotoField({
    required this.photos,
    required this.onAddPhotos,
    required this.onTakePhoto,
    required this.onRemovePhoto,
  });

  final List<Uint8List> photos;
  final Future<void> Function() onAddPhotos;
  final Future<void> Function() onTakePhoto;
  final ValueChanged<int> onRemovePhoto;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onAddPhotos,
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Gallery'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onTakePhoto,
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Camera'),
              ),
            ),
          ],
        ),
        if (photos.isNotEmpty) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 88,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: photos.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) => Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(
                      photos[index],
                      width: 88,
                      height: 88,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: InkWell(
                      onTap: () => onRemovePhoto(index),
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        padding: const EdgeInsets.all(4),
                        child: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SubmitBar extends StatelessWidget {
  const _SubmitBar({
    required this.isLoading,
    required this.onSubmit,
  });

  final bool isLoading;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: ElevatedButton.icon(
        onPressed: isLoading ? null : onSubmit,
        icon: isLoading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.send_outlined),
        label: const Text('Send Request'),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }
}

extension on ServiceRequestKind {
  IconData get icon => switch (this) {
        ServiceRequestKind.breakdown => Icons.warning_amber_outlined,
        ServiceRequestKind.serviceMaintenance => Icons.build_outlined,
        ServiceRequestKind.safetyConcern => Icons.health_and_safety_outlined,
        ServiceRequestKind.otherIssue => Icons.more_horiz,
      };
}
