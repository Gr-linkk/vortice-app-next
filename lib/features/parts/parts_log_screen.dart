import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/parts/parts_provider.dart';
import 'package:vortice_app/features/work_orders/work_order_provider.dart';
import 'package:vortice_app/models/part.dart';
import 'package:vortice_app/models/profile.dart';

class PartsLogScreen extends ConsumerWidget {
  final bool embedded;
  const PartsLogScreen({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final partsAsync = ref.watch(allPartsProvider);
    final profile = ref.watch(profileProvider).valueOrNull;
    final canAdd =
        profile?.role == UserRole.owner || profile?.role == UserRole.employee;

    return Scaffold(
      appBar: embedded ? null : AppBar(title: Text(l10n.partsTitle)),
      body: partsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(err.toString(),
                  style: const TextStyle(color: AppColors.error)),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => ref.invalidate(allPartsProvider),
                child: Text(l10n.retry),
              ),
            ],
          ),
        ),
        data: (parts) {
          if (parts.isEmpty) {
            return Center(
              child: Text(l10n.noParts,
                  style: const TextStyle(color: AppColors.textSecondary)),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(allPartsProvider),
            child: ListView.builder(
              itemCount: parts.length,
              itemBuilder: (_, i) => _PartTile(
                part: parts[i],
                canDelete: canAdd,
              ),
            ),
          );
        },
      ),
      floatingActionButton: canAdd
          ? FloatingActionButton(
              onPressed: () => _showAddPartDialog(context, ref),
              backgroundColor: AppColors.primary,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  void _showAddPartDialog(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => const _AddPartSheet(),
    );
  }
}

class _PartTile extends ConsumerWidget {
  final Part part;
  final bool canDelete;

  const _PartTile({required this.part, required this.canDelete});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final totalCost = (part.unitCost * part.quantity).toStringAsFixed(2);

    return Card(
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: AppColors.surfaceVariant,
          child: Icon(Icons.settings, color: AppColors.primary, size: 20),
        ),
        title: Text(part.description),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (part.partNumber != null)
              Text('# ${part.partNumber}',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 11)),
            Row(
              children: [
                Text('${l10n.quantity}: ${part.quantity}',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12)),
                const Text(' · ',
                    style: TextStyle(color: AppColors.textSecondary)),
                Text('\$$totalCost',
                    style: const TextStyle(
                        color: AppColors.success,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ],
        ),
        trailing: canDelete
            ? IconButton(
                icon: const Icon(Icons.delete_outline,
                    color: AppColors.error, size: 20),
                onPressed: () async {
                  await ref
                      .read(partsControllerProvider.notifier)
                      .deletePart(part.id, part.workOrderId);
                },
              )
            : null,
        isThreeLine: part.partNumber != null,
      ),
    );
  }
}

class _AddPartSheet extends ConsumerStatefulWidget {
  const _AddPartSheet();

  @override
  ConsumerState<_AddPartSheet> createState() => _AddPartSheetState();
}

class _AddPartSheetState extends ConsumerState<_AddPartSheet> {
  final _formKey = GlobalKey<FormState>();
  final _descCtrl = TextEditingController();
  final _partNumberCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  final _costCtrl = TextEditingController();
  final _supplierCtrl = TextEditingController();
  String? _selectedWorkOrderId;

  @override
  void dispose() {
    _descCtrl.dispose();
    _partNumberCtrl.dispose();
    _qtyCtrl.dispose();
    _costCtrl.dispose();
    _supplierCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isLoading = ref.watch(partsControllerProvider).isLoading;
    final workOrdersAsync = ref.watch(workOrdersProvider);
    final profile = ref.watch(profileProvider).valueOrNull;

    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.addPart, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            workOrdersAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (orders) => DropdownButtonFormField<String>(
                initialValue: _selectedWorkOrderId,
                decoration: InputDecoration(labelText: l10n.linkedWorkOrder),
                dropdownColor: AppColors.surfaceVariant,
                menuMaxHeight: 320,
                isExpanded: true,
                items: orders
                    .map((w) => DropdownMenuItem(
                          value: w.id,
                          child: Text(w.title, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _selectedWorkOrderId = v),
                validator: (v) => v == null ? l10n.fieldRequired : null,
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descCtrl,
              decoration: InputDecoration(labelText: l10n.partName),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? l10n.fieldRequired : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _partNumberCtrl,
                    decoration: InputDecoration(labelText: l10n.partNumber),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _qtyCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: l10n.quantity),
                    validator: (v) {
                      if (v == null || v.isEmpty) return l10n.fieldRequired;
                      if (double.tryParse(v) == null) return l10n.invalidNumber;
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _costCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: l10n.unitCost,
                      prefixText: '\$',
                      helperText: 'Optional — owner can price later',
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null;
                      if (double.tryParse(v) == null) return l10n.invalidNumber;
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _supplierCtrl,
                    decoration: InputDecoration(labelText: l10n.supplier),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      if (!_formKey.currentState!.validate()) return;
                      final success = await ref
                          .read(partsControllerProvider.notifier)
                          .addPart(
                            workOrderId: _selectedWorkOrderId!,
                            description: _descCtrl.text.trim(),
                            partNumber: _partNumberCtrl.text.trim().isNotEmpty
                                ? _partNumberCtrl.text.trim()
                                : null,
                            quantity:
                                double.tryParse(_qtyCtrl.text.trim()) ?? 1,
                            unitCost:
                                double.tryParse(_costCtrl.text.trim()) ?? 0,
                            supplier: _supplierCtrl.text.trim().isNotEmpty
                                ? _supplierCtrl.text.trim()
                                : null,
                            loggedBy: profile?.id ?? '',
                          );
                      if (!context.mounted) return;
                      if (success) {
                        Navigator.pop(context);
                      } else {
                        final errorState = ref.read(partsControllerProvider);
                        final errorMsg = errorState.error?.toString() ??
                            'Failed to save part. Check your connection and try again.';
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(errorMsg),
                            backgroundColor: AppColors.error,
                          ),
                        );
                      }
                    },
              child: Text(l10n.addPart),
            ),
          ],
        ),
      ),
    );
  }
}
