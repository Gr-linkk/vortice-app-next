import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/parts/parts_log_screen.dart';
import 'package:vortice_app/features/parts/pm_parts_provider.dart';
import 'package:vortice_app/models/pm_parts_requirement.dart';

// ── Owner Parts Screen (tabs: Parts Log + PM Kits) ───────────────────────────

class OwnerPartsScreen extends StatelessWidget {
  const OwnerPartsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Parts'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.list_alt_outlined), text: 'Parts Log'),
              Tab(icon: Icon(Icons.inventory_2_outlined), text: 'PM Kits'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            PartsLogScreen(embedded: true),
            PmKitsScreen(),
          ],
        ),
      ),
    );
  }
}

// ── Provider: all clients with their assets and interval-linked PM kits ───────

final pmKitsByClientProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final clients = await supabase
      .from(AppConstants.tProfiles)
      .select('id, full_name, subscription_tier')
      .inFilter('role', ['client', 'client_admin']).order('full_name');

  final result = <Map<String, dynamic>>[];

  for (final client in clients as List) {
    final clientId = client['id'] as String;

    final assets = await supabase
        .from(AppConstants.tAssets)
        .select('id, name, make, model')
        .eq('client_id', clientId)
        .order('name');

    final assetList = <Map<String, dynamic>>[];

    for (final asset in assets as List) {
      final assetId = asset['id'] as String;

      final intervals = await supabase
          .from(AppConstants.tAssetServiceIntervals)
          .select('id, interval_hours, checklist_template_id')
          .eq('asset_id', assetId)
          .not('checklist_template_id', 'is', null)
          .order('interval_hours');

      final kits = <Map<String, dynamic>>[];

      for (final interval in intervals as List) {
        final intervalMap = interval as Map<String, dynamic>;
        final templateId = intervalMap['checklist_template_id'] as String?;
        if (templateId == null) continue;

        final template = await supabase
            .from(AppConstants.tChecklistTemplates)
            .select('id, name, interval_label')
            .eq('id', templateId)
            .maybeSingle();

        final parts = await supabase
            .from(AppConstants.tPmPartsRequirements)
            .select()
            .eq('template_id', templateId)
            .order('description');

        kits.add({
          'interval_id': intervalMap['id'],
          'template_id': templateId,
          'template_name': template?['name'] ?? 'Unknown',
          'interval_label': template?['interval_label'] ??
              '${intervalMap['interval_hours']}HR',
          'interval_hours': intervalMap['interval_hours'],
          'parts': List<Map<String, dynamic>>.from(parts as List),
        });
      }

      if (kits.isNotEmpty) {
        assetList.add({
          'id': assetId,
          'name': asset['name'],
          'make': asset['make'],
          'model': asset['model'],
          'kits': kits,
        });
      }
    }

    if (assetList.isNotEmpty) {
      result.add({
        'id': clientId,
        'name': client['full_name'],
        'tier': client['subscription_tier'],
        'assets': assetList,
      });
    }
  }

  return result;
});

// ── Screen ───────────────────────────────────────────────────────────────────

class PmKitsScreen extends ConsumerWidget {
  const PmKitsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kitsAsync = ref.watch(pmKitsByClientProvider);

    return kitsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(
          child: Text(err.toString(),
              style: const TextStyle(color: AppColors.error))),
      data: (clients) {
        if (clients.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.inventory_2_outlined,
                    size: 56, color: AppColors.textSecondary),
                SizedBox(height: 12),
                Text('No PM kits set up yet.',
                    style: TextStyle(color: AppColors.textSecondary)),
                SizedBox(height: 4),
                Text(
                    'Link checklist templates to service reminders\nto build PM kits per vessel.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(pmKitsByClientProvider),
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 32),
            itemCount: clients.length,
            itemBuilder: (_, ci) {
              final client = clients[ci];
              final assets = client['assets'] as List<Map<String, dynamic>>;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Client header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                    child: Row(
                      children: [
                        const Icon(Icons.person_outline,
                            size: 16, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Text(
                          client['name'] as String,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(color: AppColors.primary),
                        ),
                      ],
                    ),
                  ),
                  // Assets
                  ...assets.map((asset) {
                    final kits = asset['kits'] as List<Map<String, dynamic>>;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 8, 16, 4),
                          child: Row(
                            children: [
                              const Icon(Icons.directions_boat_outlined,
                                  size: 14, color: AppColors.textSecondary),
                              const SizedBox(width: 6),
                              Text(
                                asset['name'] as String,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(color: AppColors.textSecondary),
                              ),
                              if (asset['make'] != null ||
                                  asset['model'] != null) ...[
                                const SizedBox(width: 6),
                                Text(
                                  [asset['make'], asset['model']]
                                      .whereType<String>()
                                      .join(' '),
                                  style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 11),
                                ),
                              ],
                            ],
                          ),
                        ),
                        // PM kits for this vessel
                        ...kits.map((kit) => _PmKitCard(
                              kit: kit,
                              assetName: asset['name'] as String,
                              onRefresh: () =>
                                  ref.invalidate(pmKitsByClientProvider),
                            )),
                      ],
                    );
                  }),
                  const Divider(height: 1),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

// ── PM Kit Card ───────────────────────────────────────────────────────────────

class _PmKitCard extends StatefulWidget {
  final Map<String, dynamic> kit;
  final String assetName;
  final VoidCallback onRefresh;

  const _PmKitCard({
    required this.kit,
    required this.assetName,
    required this.onRefresh,
  });

  @override
  State<_PmKitCard> createState() => _PmKitCardState();
}

class _PmKitCardState extends State<_PmKitCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final kit = widget.kit;
    final parts = kit['parts'] as List<Map<String, dynamic>>;
    final templateName = kit['template_name'] as String;
    final intervalLabel = kit['interval_label'] as String;

    return Card(
      margin: const EdgeInsets.fromLTRB(24, 4, 16, 4),
      child: Column(
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.primary.withValues(alpha: 0.1),
              child: const Icon(Icons.inventory_2_outlined,
                  size: 18, color: AppColors.primary),
            ),
            title: Text(intervalLabel,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
              '$templateName • ${parts.length} part${parts.length == 1 ? '' : 's'}',
              style:
                  const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.add, size: 20),
                  tooltip: 'Add part',
                  onPressed: () =>
                      _showAddPartSheet(context, kit['template_id'] as String),
                ),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
            onTap: () => setState(() => _expanded = !_expanded),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            if (parts.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No parts added yet.',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 13)),
              )
            else
              ...parts.map((part) => _PartRow(
                    part: part,
                    templateId: kit['template_id'] as String,
                    onRefresh: widget.onRefresh,
                  )),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }

  void _showAddPartSheet(BuildContext context, String templateId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) =>
          _AddPartSheet(templateId: templateId, onSaved: widget.onRefresh),
    );
  }
}

// ── Part Row ──────────────────────────────────────────────────────────────────

class _PartRow extends StatelessWidget {
  final Map<String, dynamic> part;
  final String templateId;
  final VoidCallback onRefresh;

  const _PartRow({
    required this.part,
    required this.templateId,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.circle, size: 6, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(part['description'] as String? ?? '—',
                    style: const TextStyle(fontSize: 13)),
                if (part['part_number'] != null)
                  Text('PN: ${part['part_number']}',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 11)),
              ],
            ),
          ),
          Text(
            '${part['qty'] ?? 1} ${part['unit'] ?? 'ea'}',
            style:
                const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline,
                size: 16, color: AppColors.error),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () async {
              await supabase
                  .from('pm_parts_requirements')
                  .delete()
                  .eq('id', part['id'] as String);
              onRefresh();
            },
          ),
        ],
      ),
    );
  }
}

// ── Add Part Sheet ────────────────────────────────────────────────────────────

class _AddPartSheet extends StatefulWidget {
  final String templateId;
  final VoidCallback onSaved;

  const _AddPartSheet({required this.templateId, required this.onSaved});

  @override
  State<_AddPartSheet> createState() => _AddPartSheetState();
}

class _AddPartSheetState extends State<_AddPartSheet> {
  final _descCtrl = TextEditingController();
  final _pnCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  final _unitCtrl = TextEditingController(text: 'ea');
  final _notesCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _descCtrl.dispose();
    _pnCtrl.dispose();
    _qtyCtrl.dispose();
    _unitCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Add Part to Kit',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          TextField(
            controller: _descCtrl,
            decoration: const InputDecoration(labelText: 'Description *'),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _pnCtrl,
            decoration: const InputDecoration(labelText: 'Part Number'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _qtyCtrl,
                  decoration: const InputDecoration(labelText: 'Qty'),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _unitCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Unit (ea, L, kg...)'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _notesCtrl,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _saving || _descCtrl.text.trim().isEmpty ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Add Part'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await supabase.from('pm_parts_requirements').insert({
        'template_id': widget.templateId,
        'description': _descCtrl.text.trim(),
        'part_number':
            _pnCtrl.text.trim().isNotEmpty ? _pnCtrl.text.trim() : null,
        'qty': double.tryParse(_qtyCtrl.text.trim()) ?? 1,
        'unit': _unitCtrl.text.trim().isNotEmpty ? _unitCtrl.text.trim() : 'ea',
        'notes':
            _notesCtrl.text.trim().isNotEmpty ? _notesCtrl.text.trim() : null,
      });
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

// ── PM parts list sheet ───────────────────────────────────────────────────────

class PmPartsListSheet extends ConsumerWidget {
  final String templateId;
  final String templateName;
  final bool canEdit;

  const PmPartsListSheet({
    super.key,
    required this.templateId,
    required this.templateName,
    this.canEdit = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partsAsync = ref.watch(pmPartsRequirementsProvider(templateId));

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  const Icon(Icons.inventory_2_outlined,
                      color: AppColors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      templateName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (canEdit)
                    TextButton.icon(
                      onPressed: () => _showPartSheet(context),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add'),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: partsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) =>
                    const Center(child: Text('Could not load parts list.')),
                data: (parts) {
                  if (parts.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('No parts list for this service.',
                                style:
                                    TextStyle(color: AppColors.textSecondary)),
                            if (canEdit) ...[
                              const SizedBox(height: 12),
                              ElevatedButton.icon(
                                onPressed: () => _showPartSheet(context),
                                icon: const Icon(Icons.add),
                                label: const Text('Add first part'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    controller: ctrl,
                    padding: const EdgeInsets.all(16),
                    itemCount: parts.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final part = parts[i];
                      return InkWell(
                        onTap: canEdit
                            ? () => _showPartSheet(context, requirement: part)
                            : null,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(part.description,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w500)),
                                    if (part.partNumber != null)
                                      Text('PN: ${part.partNumber}',
                                          style: const TextStyle(
                                              color: AppColors.textSecondary,
                                              fontSize: 12)),
                                    if (part.notes != null)
                                      Text(part.notes!,
                                          style: const TextStyle(
                                              color: AppColors.textSecondary,
                                              fontSize: 11,
                                              fontStyle: FontStyle.italic)),
                                  ],
                                ),
                              ),
                              Text(
                                '${part.qty} ${part.unit ?? 'ea'}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                              if (canEdit) ...[
                                const SizedBox(width: 4),
                                IconButton(
                                  tooltip: 'Delete part',
                                  icon: const Icon(Icons.delete_outline,
                                      color: AppColors.error, size: 20),
                                  onPressed: () async {
                                    final confirmed = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        backgroundColor: AppColors.surface,
                                        title: const Text('Delete part?'),
                                        content: Text(part.description),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, false),
                                            child: const Text('Cancel'),
                                          ),
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, true),
                                            child: const Text('Delete',
                                                style: TextStyle(
                                                    color: AppColors.error)),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirmed == true) {
                                      await ref
                                          .read(pmPartsControllerProvider
                                              .notifier)
                                          .removeRequirement(
                                              part.id, templateId);
                                    }
                                  },
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPartSheet(BuildContext context, {PmPartsRequirement? requirement}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _PmPartRequirementSheet(
        templateId: templateId,
        requirement: requirement,
      ),
    );
  }
}

class _PmPartRequirementSheet extends ConsumerStatefulWidget {
  final String templateId;
  final PmPartsRequirement? requirement;

  const _PmPartRequirementSheet({
    required this.templateId,
    this.requirement,
  });

  @override
  ConsumerState<_PmPartRequirementSheet> createState() =>
      _PmPartRequirementSheetState();
}

class _PmPartRequirementSheetState
    extends ConsumerState<_PmPartRequirementSheet> {
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
