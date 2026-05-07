import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/assets/asset_provider.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/checklists/checklist_provider.dart';
import 'package:vortice_app/features/engines/engine_kind_options.dart';
import 'package:vortice_app/features/parts/pm_parts_provider.dart';
import 'package:vortice_app/features/service_intervals/maintenance_work_order_draft.dart';
import 'package:vortice_app/features/service_requests/service_request_provider.dart';
import 'package:vortice_app/features/work_orders/work_order_provider.dart';
import 'package:vortice_app/models/asset.dart';
import 'package:vortice_app/models/checklist_template.dart';
import 'package:vortice_app/models/work_order.dart';

class CreateWorkOrderScreen extends ConsumerStatefulWidget {
  final MaintenanceWorkOrderDraft? initialDraft;

  const CreateWorkOrderScreen({
    super.key,
    this.initialDraft,
  });

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

  WorkOrderJobType _jobType = WorkOrderJobType.repair;
  String? _selectedAssetId;
  String? _selectedEngineId;
  List<String> _selectedTechIds = const [];
  String? _selectedChecklistTemplateId;
  DateTime? _scheduledDate;

  @override
  void initState() {
    super.initState();
    final initialDraft = widget.initialDraft;
    _jobType = initialDraft?.jobType ?? WorkOrderJobType.repair;
    _selectedAssetId = initialDraft?.assetId;
    _selectedChecklistTemplateId = initialDraft?.checklistTemplateId;
    _titleCtrl.text = initialDraft?.title ?? '';
    _descCtrl.text = initialDraft?.description ?? '';
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _hoursCtrl.dispose();
    _partsCtrl.dispose();
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

  List<ChecklistTemplate> _checklistTemplatesForAsset(
    List<ChecklistTemplate> templates,
    Asset? asset,
  ) {
    final activeMaintenance = templates
        .where((template) =>
            template.isActive &&
            (template.checklistType == 'pm' ||
                template.checklistType == 'maintenance'))
        .toList();

    final assetTypeId = asset?.assetTypeId;
    if (assetTypeId != null) {
      final assetSpecific = activeMaintenance
          .where((template) => template.assetTypeId == assetTypeId)
          .toList()
        ..sort(_compareChecklistTemplates);
      if (assetSpecific.isNotEmpty) return assetSpecific;
    }

    return activeMaintenance
        .where((template) => template.assetTypeId == null)
        .toList()
      ..sort(_compareChecklistTemplates);
  }

  int _compareChecklistTemplates(ChecklistTemplate a, ChecklistTemplate b) {
    final aHours = a.intervalHours ?? _hoursFromTemplate(a) ?? (1 << 30);
    final bHours = b.intervalHours ?? _hoursFromTemplate(b) ?? (1 << 30);
    final hoursCompare = aHours.compareTo(bHours);
    if (hoursCompare != 0) return hoursCompare;

    final labelCompare =
        (a.intervalLabel ?? '').compareTo(b.intervalLabel ?? '');
    if (labelCompare != 0) return labelCompare;

    return a.name.compareTo(b.name);
  }

  int? _hoursFromTemplate(ChecklistTemplate template) {
    final candidates =
        [template.intervalLabel, template.name].whereType<String>().join(' ');
    final match = RegExp(r'(\d+)\s*(?:hr|hour|hours|h)\b', caseSensitive: false)
        .firstMatch(candidates);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  String _checklistTemplateLabel(ChecklistTemplate template) {
    final prefix = template.intervalLabel?.trim().isNotEmpty == true
        ? template.intervalLabel!.trim()
        : template.intervalHours != null
            ? '${template.intervalHours} HR'
            : null;
    if (prefix == null || template.name.contains(prefix)) return template.name;
    return '$prefix — ${template.name}';
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
    if (parts.isNotEmpty) {
      notesInternal = 'Parts expected: $parts';
    }

    final data = <String, dynamic>{
      'title': _titleCtrl.text.trim(),
      'description':
          _descCtrl.text.trim().isNotEmpty ? _descCtrl.text.trim() : null,
      'job_type': _jobType.dbValue,
      'status': _selectedTechIds.isNotEmpty
          ? WorkOrderStatus.assigned.dbValue
          : WorkOrderStatus.draft.dbValue,
      'created_by': profile.id,
      'client_id': selectedAsset.clientId,
      'asset_id': _selectedAssetId,
      if (_selectedEngineId != null) 'engine_id': _selectedEngineId,
      if (_selectedTechIds.isNotEmpty) 'assigned_to': _selectedTechIds.first,
      if (_selectedChecklistTemplateId != null)
        'checklist_template_id': _selectedChecklistTemplateId,
      'scheduled_date': _scheduledDate?.toIso8601String().split('T').first,
      if (hoursAtStart != null) 'hours_at_start': hoursAtStart,
      if (notesInternal != null) 'notes_internal': notesInternal,
    };

    final workOrderId = await ref
        .read(workOrderControllerProvider.notifier)
        .createWorkOrder(data, assignedProfileIds: _selectedTechIds);

    if (workOrderId != null) {
      final serviceRequestId = widget.initialDraft?.serviceRequestId;
      if (serviceRequestId != null) {
        await ref
            .read(serviceRequestControllerProvider.notifier)
            .markGeneratedWorkOrder(
              id: serviceRequestId,
              workOrderId: workOrderId,
            );
      }
      if (mounted) context.pop();
      return;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Work order could not be created while offline. Reconnect and try again.',
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _pickTechnicians(List<Map<String, dynamic>> employees) async {
    final selected = Set<String>.from(_selectedTechIds);

    final result = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Assigned Technicians',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: employees.map((employee) {
                            final id = employee['id'] as String;
                            final name = (employee['full_name'] as String?)
                                        ?.trim()
                                        .isNotEmpty ==
                                    true
                                ? employee['full_name'] as String
                                : 'Unnamed tech';
                            return CheckboxListTile(
                              value: selected.contains(id),
                              controlAffinity: ListTileControlAffinity.leading,
                              contentPadding: EdgeInsets.zero,
                              title: Text(name),
                              onChanged: (checked) {
                                setModalState(() {
                                  if (checked == true) {
                                    selected.add(id);
                                  } else {
                                    selected.remove(id);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(
                        context,
                        employees
                            .map((employee) => employee['id'] as String)
                            .where(selected.contains)
                            .toList(),
                      ),
                      child: const Text('Done'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (result != null) {
      setState(() => _selectedTechIds = result);
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
                initialValue: _jobType,
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
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) => const SizedBox.shrink(),
                data: (assets) => DropdownButtonFormField<String?>(
                  initialValue: _selectedAssetId,
                  decoration: InputDecoration(
                    labelText: '${l10n.linkedAsset} *',
                    prefixIcon: const Icon(Icons.directions_boat_outlined),
                  ),
                  dropdownColor: AppColors.surfaceVariant,
                  items: [
                    DropdownMenuItem(
                      value: null,
                      child: Text(l10n.noAsset,
                          style:
                              const TextStyle(color: AppColors.textSecondary)),
                    ),
                    ...assets.map((a) => DropdownMenuItem(
                          value: a.id,
                          child: Text(a.name),
                        )),
                  ],
                  onChanged: (v) => setState(() {
                    _selectedAssetId = v;
                    _selectedEngineId = null;
                    _selectedChecklistTemplateId = null;
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
                              initialValue: _selectedEngineId,
                              decoration: const InputDecoration(
                                labelText: 'Engine / Position',
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
                                ...engines.map((e) {
                                  final label = (e['label'] as String?)?.trim();
                                  final kind = e['kind'] as String?;
                                  return DropdownMenuItem(
                                    value: e['id'] as String,
                                    child: Text(
                                      label != null && label.isNotEmpty
                                          ? label
                                          : suggestedEngineLabel(kind),
                                    ),
                                  );
                                }),
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
                      child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                    error: (_, __) => const Text('Could not load templates',
                        style: TextStyle(color: AppColors.error)),
                    data: (templates) {
                      final selectedAsset = assetsAsync.valueOrNull
                          ?.where((asset) => asset.id == _selectedAssetId)
                          .firstOrNull;
                      final filtered =
                          _checklistTemplatesForAsset(templates, selectedAsset);
                      final selectedTemplateStillVisible = filtered
                          .any((t) => t.id == _selectedChecklistTemplateId);
                      final selectedValue = selectedTemplateStillVisible
                          ? _selectedChecklistTemplateId
                          : null;

                      return DropdownButtonFormField<String?>(
                        initialValue: selectedValue,
                        isExpanded: true,
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
                            borderSide:
                                const BorderSide(color: AppColors.divider),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                const BorderSide(color: AppColors.divider),
                          ),
                        ),
                        dropdownColor: AppColors.surfaceVariant,
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('None',
                                style:
                                    TextStyle(color: AppColors.textSecondary)),
                          ),
                          for (final t in filtered)
                            DropdownMenuItem<String?>(
                              value: t.id,
                              child: Text(
                                _checklistTemplateLabel(t),
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                        ],
                        onChanged: (v) =>
                            setState(() => _selectedChecklistTemplateId = v),
                      );
                    },
                  ),

              // ── PM PARTS ────────────────────────────────────────────
              if (_jobType == WorkOrderJobType.preventative &&
                  _selectedChecklistTemplateId != null)
                _PmPartsPreviewCard(
                  templateId: _selectedChecklistTemplateId!,
                ),

              // ── ASSIGNMENT ────────────────────────────────────────
              const SizedBox(height: 24),
              _sectionHeader('ASSIGNMENT'),
              const SizedBox(height: 8),
              employeesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) => const SizedBox.shrink(),
                data: (employees) {
                  final selectedNames = employees
                      .where((employee) =>
                          _selectedTechIds.contains(employee['id'] as String))
                      .map((employee) => (employee['full_name'] as String?)
                                  ?.trim()
                                  .isNotEmpty ==
                              true
                          ? employee['full_name'] as String
                          : 'Unnamed tech')
                      .toList();

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _pickTechnicians(employees),
                        icon: const Icon(Icons.people_outline),
                        label: Text(
                          selectedNames.isEmpty
                              ? 'Assign technicians'
                              : 'Assigned (${selectedNames.length})',
                        ),
                      ),
                      if (selectedNames.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: selectedNames
                              .map((name) => Chip(label: Text(name)))
                              .toList(),
                        ),
                      ] else
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            'No technicians assigned yet',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                    ],
                  );
                },
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
                    prefixIcon: const Icon(Icons.calendar_today_outlined),
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
                        ? _scheduledDate!.toLocal().toString().split(' ').first
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
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
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

// ── PM parts preview for PM work orders ─────────────────────────────────────

class _PmPartsPreviewCard extends ConsumerWidget {
  final String templateId;

  const _PmPartsPreviewCard({required this.templateId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: ref.watch(pmPartsRequirementsProvider(templateId)).when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (parts) {
              if (parts.isEmpty) return const SizedBox.shrink();

              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.inventory_2_outlined,
                            color: AppColors.primary, size: 18),
                        SizedBox(width: 8),
                        Text(
                          'Parts required',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...parts.map(
                      (part) => Padding(
                        padding: const EdgeInsets.only(left: 26, bottom: 4),
                        child: Text(
                          '• ${part.description} — ${part.qty} ${part.unit ?? 'ea'}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
    );
  }
}
