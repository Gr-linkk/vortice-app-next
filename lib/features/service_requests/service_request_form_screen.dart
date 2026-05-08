import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  ServiceRequestUrgency _urgency = ServiceRequestUrgency.normal;
  String? _assetId;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final success =
        await ref.read(serviceRequestControllerProvider.notifier).submitRequest(
              title: _titleCtrl.text,
              description: _descriptionCtrl.text,
              urgency: _urgency,
              assetId: _assetId,
            );

    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Request sent to Vórtice.'),
          backgroundColor: AppColors.success,
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
    final assetsAsync = ref.watch(assetsProvider);
    final isLoading = ref.watch(serviceRequestControllerProvider).isLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('Request Service')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Tell us what needs attention. A Vórtice team member will review it and follow up.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 24),
                assetsAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (assets) => _AssetField(
                    assets: assets,
                    value: _assetId,
                    onChanged: (value) => setState(() => _assetId = value),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _titleCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Request title',
                    prefixIcon: Icon(Icons.build_outlined),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a title';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descriptionCtrl,
                  minLines: 4,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: 'What is happening?',
                    alignLabelWithHint: true,
                    prefixIcon: Padding(
                      padding: EdgeInsets.only(bottom: 72),
                      child: Icon(Icons.notes_outlined),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please describe the request';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                SegmentedButton<ServiceRequestUrgency>(
                  segments: const [
                    ButtonSegment(
                      value: ServiceRequestUrgency.normal,
                      label: Text('Normal'),
                      icon: Icon(Icons.schedule_outlined),
                    ),
                    ButtonSegment(
                      value: ServiceRequestUrgency.urgent,
                      label: Text('Urgent'),
                      icon: Icon(Icons.priority_high),
                    ),
                  ],
                  selected: {_urgency},
                  onSelectionChanged: (selection) {
                    setState(() => _urgency = selection.single);
                  },
                ),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: isLoading ? null : _submit,
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
              ],
            ),
          ),
        ),
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
    if (assets.isEmpty) return const SizedBox.shrink();

    return DropdownButtonFormField<String?>(
      initialValue: value,
      decoration: const InputDecoration(
        labelText: 'Vessel (optional)',
        prefixIcon: Icon(Icons.directions_boat_outlined),
      ),
      dropdownColor: AppColors.surfaceVariant,
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('General request'),
        ),
        ...assets.map(
          (asset) => DropdownMenuItem<String?>(
            value: asset.id,
            child: Text(asset.name),
          ),
        ),
      ],
      onChanged: onChanged,
    );
  }
}
