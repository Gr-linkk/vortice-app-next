import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/assets/asset_provider.dart';
import 'package:vortice_app/features/assets/asset_type_provider.dart';
import 'package:vortice_app/features/engines/engine_screen.dart';
import 'package:vortice_app/models/asset.dart';

class EditAssetScreen extends ConsumerStatefulWidget {
  final Asset asset;
  const EditAssetScreen({super.key, required this.asset});

  @override
  ConsumerState<EditAssetScreen> createState() => _EditAssetScreenState();
}

class _EditAssetScreenState extends ConsumerState<EditAssetScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _serialCtrl;
  late final TextEditingController _modelCtrl;
  late final TextEditingController _manufacturerCtrl;
  late final TextEditingController _yearCtrl;
  late final TextEditingController _locationCtrl;
  late final TextEditingController _notesCtrl;
  late String? _selectedAssetTypeId;

  @override
  void initState() {
    super.initState();
    final a = widget.asset;
    _nameCtrl = TextEditingController(text: a.name);
    _serialCtrl = TextEditingController(text: a.serialNumber ?? '');
    _modelCtrl = TextEditingController(text: a.model ?? '');
    _manufacturerCtrl = TextEditingController(text: a.make ?? '');
    _yearCtrl = TextEditingController(text: a.year?.toString() ?? '');
    _locationCtrl = TextEditingController(text: a.location ?? '');
    _notesCtrl = TextEditingController(text: a.notes ?? '');
    _selectedAssetTypeId = a.assetTypeId;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _serialCtrl.dispose();
    _modelCtrl.dispose();
    _manufacturerCtrl.dispose();
    _yearCtrl.dispose();
    _locationCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final data = <String, dynamic>{
      'name': _nameCtrl.text.trim(),
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

    final success = await ref
        .read(assetControllerProvider.notifier)
        .updateAsset(widget.asset.id, data);

    if (success && mounted) context.pop(true);
    if (!success && mounted) {
      final err = ref.read(assetControllerProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(err.toString()),
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

    return Scaffold(
      appBar: AppBar(title: Text(l10n.editAsset)),
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
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EngineScreen(assetId: widget.asset.id),
                    ),
                  );
                },
                icon: const Icon(Icons.engineering),
                label: const Text('Manage engines / positions'),
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
                    : Text(l10n.save),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
