import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/parts/pm_parts_provider.dart';
import 'package:vortice_app/models/pm_parts_requirement.dart';

class PmPartsSetupScreen extends ConsumerWidget {
  final String templateId;
  final String templateName;

  const PmPartsSetupScreen({
    super.key,
    required this.templateId,
    required this.templateName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final requirementsAsync =
        ref.watch(pmPartsRequirementsProvider(templateId));

    return Scaffold(
      appBar: AppBar(
        title: Text('$templateName — ${l10n.pmPartsTitle}'),
      ),
      body: requirementsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(err.toString(),
                  style: const TextStyle(color: AppColors.error)),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () =>
                    ref.invalidate(pmPartsRequirementsProvider(templateId)),
                child: Text(l10n.retry),
              ),
            ],
          ),
        ),
        data: (requirements) {
          if (requirements.isEmpty) {
            return Center(
              child: Text(l10n.noPmParts,
                  style:
                      const TextStyle(color: AppColors.textSecondary)),
            );
          }
          return ListView.builder(
            itemCount: requirements.length,
            itemBuilder: (_, i) => _PmPartTile(
              requirement: requirements[i],
              templateId: templateId,
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showSheet(context, ref),
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showSheet(BuildContext context, WidgetRef ref,
      [PmPartsRequirement? requirement]) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _PmPartSheet(
        templateId: templateId,
        requirement: requirement,
      ),
    );
  }
}

// ── Requirement tile ────────────────────────────────────────────────────────

class _PmPartTile extends ConsumerWidget {
  final PmPartsRequirement requirement;
  final String templateId;

  const _PmPartTile({required this.requirement, required this.templateId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: AppColors.surface,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          builder: (_) => _PmPartSheet(
            templateId: templateId,
            requirement: requirement,
          ),
        ),
        child: ListTile(
          leading: const CircleAvatar(
            backgroundColor: AppColors.surfaceVariant,
            child: Icon(Icons.build_circle_outlined,
                color: AppColors.primary, size: 20),
          ),
          title: Text(requirement.description),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (requirement.partNumber != null)
                Text('# ${requirement.partNumber}',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 11)),
              Row(
                children: [
                  Text(
                    '${l10n.quantity}: ${requirement.qty}',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                  ),
                  if (requirement.unit != null) ...[
                    const Text(' ',
                        style:
                            TextStyle(color: AppColors.textSecondary)),
                    Text(
                      requirement.unit!,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ],
          ),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline,
                color: AppColors.error, size: 20),
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: AppColors.surface,
                  title: Text(l10n.confirmDelete),
                  content: Text(l10n.confirmDeleteMessage),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(l10n.cancel),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(l10n.delete,
                          style:
                              const TextStyle(color: AppColors.error)),
                    ),
                  ],
                ),
              );
              if (confirmed == true) {
                await ref
                    .read(pmPartsControllerProvider.notifier)
                    .removeRequirement(requirement.id, templateId);
              }
            },
          ),
          isThreeLine: requirement.partNumber != null,
        ),
      ),
    );
  }
}

// ── Add / Edit sheet ────────────────────────────────────────────────────────

class _PmPartSheet extends ConsumerStatefulWidget {
  final String templateId;
  final PmPartsRequirement? requirement;

  const _PmPartSheet({required this.templateId, this.requirement});

  @override
  ConsumerState<_PmPartSheet> createState() => _PmPartSheetState();
}

class _PmPartSheetState extends ConsumerState<_PmPartSheet> {
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
    _unitCtrl = TextEditingController(text: req?.unit ?? '');
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
    final l10n = AppLocalizations.of(context);
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
                isEdit ? l10n.editPmPart : l10n.addPmPart,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descCtrl,
                decoration: InputDecoration(labelText: l10n.partName),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? l10n.fieldRequired
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _partNumberCtrl,
                decoration: InputDecoration(labelText: l10n.partNumber),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _qtyCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration:
                          InputDecoration(labelText: l10n.quantity),
                      validator: (v) {
                        if (v == null || v.isEmpty) return l10n.fieldRequired;
                        if (double.tryParse(v) == null) {
                          return l10n.invalidNumber;
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _unitCtrl,
                      decoration:
                          InputDecoration(labelText: l10n.partsUnit),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesCtrl,
                decoration: InputDecoration(labelText: l10n.notes),
                maxLines: 2,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: isLoading ? null : _submit,
                child: Text(l10n.save),
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

    bool success;
    if (widget.requirement != null) {
      success = await controller.updateRequirement(
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
    } else {
      success = await controller.addRequirement(
        templateId: widget.templateId,
        description: description,
        partNumber: partNumber,
        qty: qty,
        unit: unit,
        notes: notes,
      );
    }

    if (success && mounted) Navigator.pop(context);
  }
}
