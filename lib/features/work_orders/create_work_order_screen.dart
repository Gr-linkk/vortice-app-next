import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/assets/asset_provider.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/checklists/checklist_provider.dart';
import 'package:vortice_app/features/parts/pm_parts_provider.dart';
import 'package:vortice_app/features/work_orders/work_order_provider.dart';
import 'package:vortice_app/models/checklist_template.dart';
import 'package:vortice_app/models/work_order.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';

/// Provider that fetches all checklist template IDs linked to an asset's service intervals.
final _assetServiceTemplatesProvider =
    FutureProvider.family<List<String>, String>((ref, assetId) async {
  final rows = await supabase
      .from(AppConstants.tAssetServiceIntervals)
      .select('checklist_template_id')
      .eq('asset_id', assetId)
      .not('checklist_template_id', 'is', null);
  return (rows as List)
      .map((r) =>
          (r as Map<String, dynamic>)['checklist_template_id'] as String)
      .toSet()
      .toList();
});

class CreateWorkOrderScreen extends ConsumerStatefulWidget {
  const CreateWorkOrderScreen({super.key});

  @override
  ConsumerState<CreateWorkOrderScreen> createState() =>
      _CreateWorkOrderScreenState();
}

class _CreateWorkOrderScreenState extends ConsumerState<CreateWorkOrderScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _hoursCtrl = TextEditingController();
  final _partsCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  WorkOrderJobType _jobType = WorkOrderJobType.repair;
  String? _selectedAssetId;
  String? _selectedEngineId;
  String? _selectedTechId;
  String? _selectedChecklistTemplateId;
  DateTime? _scheduledDate;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _hoursCtrl.dispose();
    _partsCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Text(
        title,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Future<void> _pickScheduledDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(primary: AppColors.primary),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _scheduledDate = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final profile = ref.read(profileProvider).valueOrNull;
    if (profile == null) return;

    if (_selectedAssetId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select an asset'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final assets = ref.read(assetsProvider).valueOrNull ?? [];
    final selectedAsset = assets.firstWhere(
      (a) => a.id == _selectedAssetId,
      orElse: () => assets.first,
    );

    double? hoursAtStart;
    final hoursText = _hoursCtrl.text.trim();
    if (hoursText.isNotEmpty) {
      hoursAtStart = double.tryParse(hoursText);
    }

    String? notesInternal;
    final parts = _partsCtrl.text.trim();
    final internalNotes = _notesCtrl.text.trim();
    if (parts.isNotEmpty || internalNotes.isNotEmpty) {
      final buffer = StringBuffer();
      if (parts.isNotEmpty) {
        buffer.write('Parts expected: $parts');
        if (internalNotes.isNotEmpty) buffer.write('\n\n');
      }
      if (internalNotes.isNotEmpty) buffer.write(internalNotes);
      notesInternal = buffer.toString();
    }

    final data = <String, dynamic>{
      'title': _titleCtrl.text.trim(),
      'description':
          _descCtrl.text.trim().isNotEmpty ? _descCtrl.text.trim() : null,
      'job_type': _jobType.dbValue,
      'status': _selectedTechId != null
          ? WorkOrderStatus.assigned.dbValue
          : WorkOrderStatus.draft.dbValue,
      'created_by': profile.id,
      'client_id': selectedAsset.clientId,
      'asset_id': _selectedAssetId,
      if (_selectedEngineId != null) 'engine_id': _selectedEngineId,
      if (_selectedTechId != null) 'assigned_to': _selectedTechId,
      if (_selectedChecklistTemplateId != null)
        'checklist_template_id': _selectedChecklistTemplateId,
      'scheduled_date': _scheduledDate?.toIso8601String().split('T').first,
      if (hoursAtStart != null) 'hours_at_start': hoursAtStart,
      if (notesInternal != null) 'notes_internal': notesInternal,
    };

    final success = await ref
        .read(workOrderControllerProvider.notifier)
        .createWorkOrder(data);

    if (success && mounted) context.pop();
    if (!success && mounted) {
      final err = ref.read(workOrderControllerProvider).error;
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
    final isLoading = ref.watch(workOrderControllerProvider).isLoading;
    final assetsAsync = ref.watch(assetsProvider);
    final employeesAsync = ref.watch(employeesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.createWorkOrder)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── JOB DETAILS ───────────────────────────────────────
              _sectionHeader('JOB DETAILS'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _titleCtrl,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: l10n.workOrderTitle,
                  prefixIcon: const Icon(Icons.build_outlined),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? l10n.fieldRequired : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<WorkOrderJobType>(
                value: _jobType,
                decoration: InputDecoration(labelText: l10n.jobType),
                dropdownColor: AppColors.surfaceVariant,
                items: WorkOrderJobType.values
                    .map((t) => DropdownMenuItem(
                          value: t,
                          child: Text(t == WorkOrderJobType.preventative
                              ? 'Preventative Maintenance'
                              : 'Repair / Troubleshooting'),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _jobType = v!),
              ),
              const SizedBox(height: 16),
              assetsAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (_, __) => const SizedBox.shrink(),
                data: (assets) => DropdownButtonFormField<String?>(
                  value: _selectedAssetId,
                  decoration: InputDecoration(
                    labelText: '${l10n.linkedAsset} *',
                    prefixIcon:
                        const Icon(Icons.directions_boat_outlined),
                  ),
                  dropdownColor: AppColors.surfaceVariant,
                  items: [
                    DropdownMenuItem(
                      value: null,
                      child: Text(l10n.noAsset,
                          style: const TextStyle(
                              color: AppColors.textSecondary)),
                    ),
                    ...assets.map((a) => DropdownMenuItem(
                          value: a.id,
                          child: Text(a.name),
                        )),
                  ],
                  onChanged: (v) => setState(() {
                    _selectedAssetId = v;
                    _selectedEngineId = null;
                  }),
                ),
              ),
              // Engine field — only when an asset is selected and it has engines
              if (_selectedAssetId != null)
                ref.watch(assetEnginesProvider(_selectedAssetId!)).when(
                  loading: () => const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: SizedBox(
                      height: 48,
                      child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                  ),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (engines) {
                    if (engines.isEmpty) return const SizedBox.shrink();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String?>(
                          value: _selectedEngineId,
                          decoration: const InputDecoration(
                            labelText: 'Engine / Unit',
                            prefixIcon: Icon(Icons.settings_outlined),
                          ),
                          dropdownColor: AppColors.surfaceVariant,
                          items: [
                            const DropdownMenuItem(
                              value: null,
                              child: Text('None',
                                  style: TextStyle(
                                      color: AppColors.textSecondary)),
                            ),
                            ...engines.map((e) => DropdownMenuItem(
                                  value: e['id'] as String,
                                  child: Text(
                                    (e['label'] ?? e['kind'] ?? 'Engine')
                                        as String,
                                  ),
                                )),
                          ],
                          onChanged: (v) =>
                              setState(() => _selectedEngineId = v),
                        ),
                      ],
                    );
                  },
                ),

              // ── CHECKLIST TEMPLATE ──────────────────────────────────
              const SizedBox(height: 8),
              Text('Checklist Template',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              ref.watch(checklistTemplatesProvider).when(
                loading: () => const SizedBox(
                  height: 48,
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ),
                error: (_, __) => const Text('Could not load templates',
                    style: TextStyle(color: AppColors.error)),
                data: (templates) {
                  final flat = templates.toList();
                  return DropdownButtonFormField<String>(
                    value: _selectedChecklistTemplateId,
                    decoration: InputDecoration(
                      hintText: 'Optional — assign a checklist',
                      hintStyle: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 14),
                      filled: true,
                      fillColor: AppColors.surface,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppColors.divider),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppColors.divider),
                      ),
                    ),
                    dropdownColor: AppColors.surfaceVariant,
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('None',
                            style:
                                TextStyle(color: AppColors.textSecondary)),
                      ),
                      for (final t in flat)
                        DropdownMenuItem(
                          value: t.id,
                          child: Text(t.name, style: const TextStyle(fontSize: 14)),
                        ),
                    ],
                    onChanged: (v) =>
                        setState(() => _selectedChecklistTemplateId = v),
                  );
                },
              ),

              // ── PARTS READINESS ─────────────────────────────────────
              if (_jobType == WorkOrderJobType.preventative &&
                  _selectedAssetId != null)
                _PartsReadinessCard(assetId: _selectedAssetId!),

              // ── ASSIGNMENT ────────────────────────────────────────
              const SizedBox(height: 24),
              _sectionHeader('ASSIGNMENT'),
              const SizedBox(height: 8),
              employeesAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (_, __) => const SizedBox.shrink(),
                data: (employees) => DropdownButtonFormField<String?>(
                  value: _selectedTechId,
                  decoration: const InputDecoration(
                    labelText: 'Assigned Technician',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  dropdownColor: AppColors.surfaceVariant,
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('Unassigned',
                          style:
                              TextStyle(color: AppColors.textSecondary)),
                    ),
                    ...employees.map((e) => DropdownMenuItem(
                          value: e['id'] as String,
                          child: Text(
                              (e['full_name'] as String?) ?? ''),
                        )),
                  ],
                  onChanged: (v) => setState(() => _selectedTechId = v),
                ),
              ),

              // ── SCHEDULING ────────────────────────────────────────
              const SizedBox(height: 24),
              _sectionHeader('SCHEDULING'),
              const SizedBox(height: 8),
              InkWell(
                onTap: _pickScheduledDate,
                borderRadius: BorderRadius.circular(10),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: l10n.scheduledDate,
                    prefixIcon:
                        const Icon(Icons.calendar_today_outlined),
                    suffixIcon: _scheduledDate != null
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () =>
                                setState(() => _scheduledDate = null),
                          )
                        : null,
                  ),
                  child: Text(
                    _scheduledDate != null
                        ? _scheduledDate!
                            .toLocal()
                            .toString()
                            .split(' ')
                            .first
                        : l10n.selectDate,
                    style: TextStyle(
                      color: _scheduledDate != null
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _hoursCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Current Engine Hours',
                  hintText: 'e.g. 1250.5',
                  prefixIcon: Icon(Icons.timer_outlined),
                ),
              ),

              // ── NOTES ─────────────────────────────────────────────
              const SizedBox(height: 24),
              _sectionHeader('NOTES'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _descCtrl,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: l10n.description,
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _partsCtrl,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Parts / Materials Expected',
                  hintText: 'e.g. Oil filter, impeller, zincs...',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _notesCtrl,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Internal Notes (owner → tech only)',
                  alignLabelWithHint: true,
                ),
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
                    : Text(l10n.createWorkOrder),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Parts readiness card for PM work orders ─────────────────────────────────

class _PartsReadinessCard extends ConsumerWidget {
  final String assetId;

  const _PartsReadinessCard({required this.assetId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final templatesAsync = ref.watch(_assetServiceTemplatesProvider(assetId));

    return templatesAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.only(top: 12),
        child: SizedBox(
          height: 24,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (templateIds) {
        if (templateIds.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: templateIds.map((tid) {
              return ref.watch(pmReadinessProvider(tid)).when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (readiness) {
                  if (readiness.totalRequired == 0) {
                    return const SizedBox.shrink();
                  }
                  final Color chipColor;
                  final IconData chipIcon;
                  final String chipLabel;

                  switch (readiness.level) {
                    case ReadinessLevel.ready:
                      chipColor = AppColors.success;
                      chipIcon = Icons.check_circle_outline;
                      chipLabel = l10n.partsReady;
                    case ReadinessLevel.partial:
                      chipColor = AppColors.warning;
                      chipIcon = Icons.warning_amber_outlined;
                      chipLabel =
                          '${l10n.partsPartial} (${l10n.partsMissing(readiness.missingParts.length)})';
                    case ReadinessLevel.notReady:
                      chipColor = AppColors.error;
                      chipIcon = Icons.cancel_outlined;
                      chipLabel = l10n.partsNotReady;
                  }

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: chipColor.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: chipColor.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(chipIcon, color: chipColor, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              '${l10n.partsReadiness}: $chipLabel',
                              style: TextStyle(
                                color: chipColor,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        if (readiness.missingParts.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          ...readiness.missingParts.map(
                            (p) => Padding(
                              padding: const EdgeInsets.only(left: 26),
                              child: Text(
                                '\u2022 $p',
                                style: TextStyle(
                                  color: chipColor.withOpacity(0.8),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }
}
