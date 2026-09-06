import 'package:vortice_app/core/user_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/assets/asset_provider.dart';
import 'package:vortice_app/features/assets/asset_type_provider.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/clients/client_provider.dart';
import 'package:vortice_app/features/engines/engine_kind_options.dart';
import 'package:vortice_app/features/engines/engine_provider.dart';
import 'package:vortice_app/models/profile.dart';

class AddAssetScreen extends ConsumerStatefulWidget {
  const AddAssetScreen({super.key});

  @override
  ConsumerState<AddAssetScreen> createState() => _AddAssetScreenState();
}

class _AddAssetScreenState extends ConsumerState<AddAssetScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _serialCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _manufacturerCtrl = TextEditingController();
  final _yearCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  // Engine fields
  final _engineMakeCtrl = TextEditingController();
  final _engineModelCtrl = TextEditingController();
  final _engineSerialCtrl = TextEditingController();
  String? _selectedAssetTypeId;
  String? _selectedClientId;
  String _engineKind = 'main';

  @override
  void dispose() {
    _nameCtrl.dispose();
    _serialCtrl.dispose();
    _modelCtrl.dispose();
    _manufacturerCtrl.dispose();
    _yearCtrl.dispose();
    _locationCtrl.dispose();
    _notesCtrl.dispose();
    _engineMakeCtrl.dispose();
    _engineModelCtrl.dispose();
    _engineSerialCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final profile = ref.read(profileProvider).valueOrNull;

    if (profile?.role == UserRole.owner && _selectedClientId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select the client this asset belongs to.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final data = <String, dynamic>{
      'name': _nameCtrl.text.trim(),
      'client_id': _selectedClientId ?? profile?.id,
      'asset_type_id': _selectedAssetTypeId,
      'serial_number':
          _serialCtrl.text.trim().isNotEmpty ? _serialCtrl.text.trim() : null,
      'model':
          _modelCtrl.text.trim().isNotEmpty ? _modelCtrl.text.trim() : null,
      'make': _manufacturerCtrl.text.trim().isNotEmpty
          ? _manufacturerCtrl.text.trim()
          : null,
      'year': _yearCtrl.text.trim().isNotEmpty
          ? int.tryParse(_yearCtrl.text.trim())
          : null,
      'location': _locationCtrl.text.trim().isNotEmpty
          ? _locationCtrl.text.trim()
          : null,
      'notes':
          _notesCtrl.text.trim().isNotEmpty ? _notesCtrl.text.trim() : null,
    };

    final success =
        await ref.read(assetControllerProvider.notifier).createAsset(data);

    final hasEngineDetails = _engineMakeCtrl.text.trim().isNotEmpty ||
        _engineModelCtrl.text.trim().isNotEmpty ||
        _engineSerialCtrl.text.trim().isNotEmpty;

    // If asset created and engine details were provided, also create the engine
    if (success && hasEngineDetails) {
      // Fetch the newly created asset to get its ID
      final assets = await ref.refresh(assetsProvider.future);
      final newAsset = assets.firstWhere(
        (a) => a.name == _nameCtrl.text.trim(),
        orElse: () => assets.first,
      );
      await ref.read(engineControllerProvider.notifier).addEngine({
        'asset_id': newAsset.id,
        'label': suggestedEngineLabel(_engineKind),
        'kind': _engineKind,
        'make': _engineMakeCtrl.text.trim().isNotEmpty
            ? _engineMakeCtrl.text.trim()
            : null,
        'model': _engineModelCtrl.text.trim().isNotEmpty
            ? _engineModelCtrl.text.trim()
            : null,
        'serial_number': _engineSerialCtrl.text.trim().isNotEmpty
            ? _engineSerialCtrl.text.trim()
            : null,
      });
    }

    if (success && mounted) context.pop();
    if (!success && mounted) {
      final err = ref.read(assetControllerProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyError(context, err)),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isLoading = ref.watch(assetControllerProvider).isLoading;
    final assetTypesAsync = ref.watch(assetTypesProvider);
    final profile = ref.watch(profileProvider).valueOrNull;
    final isOwner = profile?.role == UserRole.owner;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.addAsset)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Asset Type dropdown ──────────────────────────────
              assetTypesAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (_, __) => const SizedBox.shrink(),
                data: (types) => DropdownButtonFormField<String>(
                  initialValue: _selectedAssetTypeId,
                  decoration: InputDecoration(
                    labelText: l10n.assetType,
                    prefixIcon: const Icon(Icons.category_outlined),
                  ),
                  dropdownColor: AppColors.surfaceVariant,
                  items: types
                      .map((t) => DropdownMenuItem(
                            value: t.id,
                            child: Text(t.name),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedAssetTypeId = v),
                  validator: (v) => v == null ? l10n.fieldRequired : null,
                ),
              ),
              if (isOwner) ...[
                const SizedBox(height: 16),
                _ClientDropdown(
                  selectedClientId: _selectedClientId,
                  onChanged: (id) => setState(() => _selectedClientId = id),
                ),
              ],
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: l10n.assetName,
                  prefixIcon: const Icon(Icons.directions_boat_outlined),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? l10n.fieldRequired : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _serialCtrl,
                decoration: InputDecoration(
                  labelText: l10n.serialNumber,
                  prefixIcon: const Icon(Icons.qr_code),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _manufacturerCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(labelText: l10n.manufacturer),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _modelCtrl,
                      decoration: InputDecoration(labelText: l10n.model),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _yearCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: l10n.year),
                      validator: (v) {
                        if (v == null || v.isEmpty) return null;
                        final y = int.tryParse(v);
                        if (y == null || y < 1900 || y > 2100) {
                          return l10n.invalidYear;
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _locationCtrl,
                      decoration: InputDecoration(
                        labelText: l10n.location,
                        prefixIcon: const Icon(Icons.location_on_outlined),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _notesCtrl,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: l10n.notes,
                  alignLabelWithHint: true,
                ),
              ),
              // ── Engine details (optional) ──────────────────────
              const SizedBox(height: 24),
              Text(
                l10n.enginesTitle.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.primary,
                      letterSpacing: 1.2,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.addEngineHint,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _engineKind,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  prefixIcon: Icon(Icons.engineering),
                ),
                dropdownColor: AppColors.surfaceVariant,
                items: kEngineKindOptions
                    .map((option) => DropdownMenuItem(
                          value: option.value,
                          child: Text(option.suggestedLabel),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _engineKind = value);
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _engineMakeCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(labelText: l10n.manufacturer),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _engineModelCtrl,
                      decoration: InputDecoration(labelText: l10n.model),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _engineSerialCtrl,
                      decoration: InputDecoration(labelText: l10n.serialNumber),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Hours will come from the latest work order.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: isLoading ? null : _submit,
                child: isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(l10n.saveAsset),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Client dropdown (owner only) ──────────────────────────────────────────────

class _ClientDropdown extends ConsumerWidget {
  final String? selectedClientId;
  final ValueChanged<String?> onChanged;

  const _ClientDropdown({
    required this.selectedClientId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clientsAsync = ref.watch(clientsProvider);

    return clientsAsync.when(
      loading: () => const LinearProgressIndicator(),
      error: (_, __) => const SizedBox.shrink(),
      data: (clients) => DropdownButtonFormField<String>(
        initialValue: selectedClientId,
        decoration: const InputDecoration(
          labelText: 'Client',
          prefixIcon: Icon(Icons.person_outline),
        ),
        dropdownColor: AppColors.surfaceVariant,
        hint: const Text('Select Client'),
        validator: (value) => value == null ? 'Please select a client' : null,
        items: clients
            .map((c) => DropdownMenuItem(
                  value: c.id,
                  child: Text(c.fullName),
                ))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }
}
