import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/parts/parts_inventory_provider.dart';
import 'package:vortice_app/models/parts_inventory.dart';

class PartsInventoryScreen extends ConsumerStatefulWidget {
  const PartsInventoryScreen({super.key});

  @override
  ConsumerState<PartsInventoryScreen> createState() =>
      _PartsInventoryScreenState();
}

class _PartsInventoryScreenState extends ConsumerState<PartsInventoryScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final inventoryAsync = ref.watch(inventorySearchProvider(_query));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.partsInventoryTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: l10n.searchParts,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: inventoryAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(err.toString(),
                        style: const TextStyle(color: AppColors.error)),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () => ref.invalidate(partsInventoryProvider),
                      child: Text(l10n.retry),
                    ),
                  ],
                ),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return Center(
                    child: Text(
                      _query.isEmpty ? l10n.noInventory : l10n.noInventory,
                      style:
                          const TextStyle(color: AppColors.textSecondary),
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async =>
                      ref.invalidate(partsInventoryProvider),
                  child: ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (_, i) => _InventoryCard(item: items[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showItemSheet(context, ref),
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showItemSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const _InventoryItemSheet(),
    );
  }
}

// ── Inventory card ──────────────────────────────────────────────────────────

class _InventoryCard extends ConsumerWidget {
  final PartsInventory item;

  const _InventoryCard({required this.item});

  Color _qtyColor() {
    if (item.qtyOnHand <= 0) return AppColors.error;
    if (item.minStockLevel > 0 && item.qtyOnHand < item.minStockLevel) {
      return AppColors.warning;
    }
    return AppColors.success;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppColors.error,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
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
                    style: const TextStyle(color: AppColors.error)),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) {
        ref
            .read(partsInventoryControllerProvider.notifier)
            .deleteItem(item.id);
      },
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: AppColors.surface,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            builder: (_) => _InventoryItemSheet(item: item),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.description,
                              style: Theme.of(context).textTheme.titleSmall),
                          if (item.partNumber != null)
                            Text('# ${item.partNumber}',
                                style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 11)),
                          if (item.supplier != null)
                            Text(item.supplier!,
                                style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          item.qtyOnHand.toStringAsFixed(
                              item.qtyOnHand == item.qtyOnHand.roundToDouble()
                                  ? 0
                                  : 1),
                          style: TextStyle(
                            color: _qtyColor(),
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(l10n.qtyOnHand,
                            style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 10)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (item.location != null) ...[
                      Chip(
                        label: Text(item.location!),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      '\$${item.lastUnitCost.toStringAsFixed(2)}',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Add / Edit sheet ────────────────────────────────────────────────────────

class _InventoryItemSheet extends ConsumerStatefulWidget {
  final PartsInventory? item;

  const _InventoryItemSheet({this.item});

  @override
  ConsumerState<_InventoryItemSheet> createState() =>
      _InventoryItemSheetState();
}

class _InventoryItemSheetState extends ConsumerState<_InventoryItemSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _descCtrl;
  late final TextEditingController _partNumberCtrl;
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _minStockCtrl;
  late final TextEditingController _locationCtrl;
  late final TextEditingController _supplierCtrl;
  late final TextEditingController _costCtrl;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _descCtrl = TextEditingController(text: item?.description ?? '');
    _partNumberCtrl = TextEditingController(text: item?.partNumber ?? '');
    _qtyCtrl = TextEditingController(
        text: item != null ? item.qtyOnHand.toString() : '0');
    _minStockCtrl = TextEditingController(
        text: item != null ? item.minStockLevel.toString() : '0');
    _locationCtrl = TextEditingController(text: item?.location ?? '');
    _supplierCtrl = TextEditingController(text: item?.supplier ?? '');
    _costCtrl = TextEditingController(
        text: item != null ? item.lastUnitCost.toString() : '0');
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _partNumberCtrl.dispose();
    _qtyCtrl.dispose();
    _minStockCtrl.dispose();
    _locationCtrl.dispose();
    _supplierCtrl.dispose();
    _costCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isLoading =
        ref.watch(partsInventoryControllerProvider).isLoading;
    final isEdit = widget.item != null;

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
                isEdit ? l10n.editInventoryItem : l10n.addInventoryItem,
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
                          InputDecoration(labelText: l10n.qtyOnHand),
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
                      controller: _minStockCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration:
                          InputDecoration(labelText: l10n.minStockLevel),
                      validator: (v) {
                        if (v == null || v.isEmpty) return null;
                        if (double.tryParse(v) == null) {
                          return l10n.invalidNumber;
                        }
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
                      controller: _locationCtrl,
                      decoration:
                          InputDecoration(labelText: l10n.partLocation),
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
              const SizedBox(height: 12),
              TextFormField(
                controller: _costCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: l10n.lastUnitCost,
                  prefixText: '\$',
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return null;
                  if (double.tryParse(v) == null) return l10n.invalidNumber;
                  return null;
                },
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

    final controller =
        ref.read(partsInventoryControllerProvider.notifier);
    final description = _descCtrl.text.trim();
    final partNumber = _partNumberCtrl.text.trim().isNotEmpty
        ? _partNumberCtrl.text.trim()
        : null;
    final qty = double.tryParse(_qtyCtrl.text.trim()) ?? 0.0;
    final minStock = double.tryParse(_minStockCtrl.text.trim()) ?? 0.0;
    final location = _locationCtrl.text.trim().isNotEmpty
        ? _locationCtrl.text.trim()
        : null;
    final supplier = _supplierCtrl.text.trim().isNotEmpty
        ? _supplierCtrl.text.trim()
        : null;
    final cost = double.tryParse(_costCtrl.text.trim()) ?? 0.0;

    bool success;
    if (widget.item != null) {
      success = await controller.updateItem(widget.item!.id, {
        'description': description,
        'part_number': partNumber,
        'qty_on_hand': qty,
        'min_stock_level': minStock,
        'location': location,
        'supplier': supplier,
        'last_unit_cost': cost,
      });
    } else {
      success = await controller.addItem(
        description: description,
        partNumber: partNumber,
        qtyOnHand: qty,
        minStockLevel: minStock,
        location: location,
        supplier: supplier,
        lastUnitCost: cost,
      );
    }

    if (success && mounted) Navigator.pop(context);
  }
}
