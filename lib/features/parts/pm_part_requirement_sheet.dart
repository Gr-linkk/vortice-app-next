import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/features/parts/pm_parts_provider.dart';
import 'package:vortice_app/models/pm_parts_requirement.dart';

class PmPartRequirementSheet extends ConsumerStatefulWidget {
  final String templateId;
  final PmPartsRequirement? requirement;

  const PmPartRequirementSheet({
    super.key,
    required this.templateId,
    this.requirement,
  });

  @override
  ConsumerState<PmPartRequirementSheet> createState() =>
      _PmPartRequirementSheetState();
}

class _PmPartRequirementSheetState
    extends ConsumerState<PmPartRequirementSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _descCtrl;
  late final TextEditingController _partNumberCtrl;
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _unitCtrl;
  late final TextEditingController _notesCtrl;

  @override
  void initState() {
    super.initState();
    final req = widget.requirement;
    _descCtrl = TextEditingController(text: req?.description ?? '');
    _partNumberCtrl = TextEditingController(text: req?.partNumber ?? '');
    _qtyCtrl =
        TextEditingController(text: req != null ? req.qty.toString() : '1');
    _unitCtrl = TextEditingController(text: req?.unit ?? 'ea');
    _notesCtrl = TextEditingController(text: req?.notes ?? '');
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _partNumberCtrl.dispose();
    _qtyCtrl.dispose();
    _unitCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(pmPartsControllerProvider).isLoading;
    final isEdit = widget.requirement != null;

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
              Text(
                isEdit ? 'Edit part' : 'Add part',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descCtrl,
                decoration: const InputDecoration(labelText: 'Description'),
                textCapitalization: TextCapitalization.sentences,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _partNumberCtrl,
                decoration: const InputDecoration(labelText: 'Part number'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _qtyCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Qty'),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Required';
                        if (double.tryParse(v.trim()) == null) {
                          return 'Invalid number';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _unitCtrl,
                      decoration: const InputDecoration(labelText: 'Unit'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesCtrl,
                decoration: const InputDecoration(labelText: 'Notes'),
                maxLines: 2,
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: isLoading ? null : _submit,
                icon: isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save),
                label: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final controller = ref.read(pmPartsControllerProvider.notifier);
    final description = _descCtrl.text.trim();
    final partNumber = _partNumberCtrl.text.trim().isNotEmpty
        ? _partNumberCtrl.text.trim()
        : null;
    final qty = double.tryParse(_qtyCtrl.text.trim()) ?? 1.0;
    final unit =
        _unitCtrl.text.trim().isNotEmpty ? _unitCtrl.text.trim() : null;
    final notes =
        _notesCtrl.text.trim().isNotEmpty ? _notesCtrl.text.trim() : null;

    final success = widget.requirement == null
        ? await controller.addRequirement(
            templateId: widget.templateId,
            description: description,
            partNumber: partNumber,
            qty: qty,
            unit: unit,
            notes: notes,
          )
        : await controller.updateRequirement(
            widget.requirement!.id,
            widget.templateId,
            {
              'description': description,
              'part_number': partNumber,
              'qty': qty,
              'unit': unit,
              'notes': notes,
            },
          );

    if (success && mounted) Navigator.pop(context);
  }
}
