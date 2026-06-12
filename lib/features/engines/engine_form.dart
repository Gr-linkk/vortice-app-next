import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/engines/engine_kind_options.dart';
import 'package:vortice_app/features/engines/engine_provider.dart';
import 'package:vortice_app/features/engines/engine_screen_support.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/models/asset_engine.dart';

class EngineForm extends ConsumerStatefulWidget {
  final String assetId;
  final AssetEngine? engine;

  const EngineForm({super.key, required this.assetId, this.engine});

  @override
  ConsumerState<EngineForm> createState() => _EngineFormState();
}

class _EngineFormState extends ConsumerState<EngineForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _makeCtrl;
  late final TextEditingController _modelCtrl;
  late final TextEditingController _serialCtrl;
  String _kind = 'main';

  bool get _isEdit => widget.engine != null;

  @override
  void initState() {
    super.initState();
    _makeCtrl = TextEditingController(text: widget.engine?.make ?? '');
    _modelCtrl = TextEditingController(text: widget.engine?.model ?? '');
    _serialCtrl =
        TextEditingController(text: widget.engine?.serialNumber ?? '');
    _kind = normalizeEngineKind(widget.engine?.kind);
  }

  @override
  void dispose() {
    _makeCtrl.dispose();
    _modelCtrl.dispose();
    _serialCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final data = buildEngineFormPayload(
      assetId: widget.assetId,
      kind: _kind,
      make: _makeCtrl.text,
      model: _modelCtrl.text,
      serialNumber: _serialCtrl.text,
    );

    bool success;
    if (_isEdit) {
      success = await ref
          .read(engineControllerProvider.notifier)
          .updateEngine(widget.engine!.id, widget.assetId, data);
    } else {
      success =
          await ref.read(engineControllerProvider.notifier).addEngine(data);
    }
    if (success && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controllerState = ref.watch(engineControllerProvider);
    final isLoading = controllerState is AsyncLoading;

    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.textSecondary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _isEdit ? l10n.editEngine : l10n.addEngine,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _kind,
                decoration: const InputDecoration(labelText: 'Title'),
                dropdownColor: AppColors.surfaceVariant,
                items: kEngineKindOptions
                    .map((option) => DropdownMenuItem(
                          value: option.value,
                          child: Text(option.suggestedLabel),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _kind = v);
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _makeCtrl,
                decoration: InputDecoration(labelText: l10n.manufacturer),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _modelCtrl,
                decoration: InputDecoration(labelText: l10n.model),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _serialCtrl,
                decoration: InputDecoration(labelText: l10n.serialNumber),
              ),
              const SizedBox(height: 12),
              const Text(
                'Hours are pulled from the most recent work order for this engine.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: isLoading ? null : _submit,
                child: isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
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
