import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/assets/asset_provider.dart';
import 'package:vortice_app/features/checklists/checklist_provider.dart';
import 'package:vortice_app/features/parts/pm_kits_screen.dart';
import 'package:vortice_app/features/parts/pm_parts_provider.dart';
import 'package:vortice_app/features/service_intervals/maintenance_work_order_draft.dart';
import 'package:vortice_app/features/service_intervals/service_interval_provider.dart';
import 'package:vortice_app/features/clients/client_capability_gate.dart';
import 'package:vortice_app/models/asset.dart';
import 'package:vortice_app/models/checklist_template.dart';
import 'package:vortice_app/models/client_capability.dart';

class ServiceIntervalScreen extends ConsumerStatefulWidget {
  final String? assetId;
  final bool readOnly;

  const ServiceIntervalScreen({
    super.key,
    this.assetId,
    this.readOnly = false,
  });

  @override
  ConsumerState<ServiceIntervalScreen> createState() =>
      _ServiceIntervalScreenState();
}

class _ServiceIntervalScreenState extends ConsumerState<ServiceIntervalScreen> {
  Asset? _selectedAsset;

  bool get _isFixedAsset => widget.assetId != null;

  List<ChecklistTemplate> _maintenanceTemplatesForAsset(
    List<ChecklistTemplate> templates,
    Asset? asset,
  ) {
    final maintenanceTemplates = templates
        .where(
            (template) => template.isActive && template.checklistType == 'pm')
        .toList();
    final assetTypeId = asset?.assetTypeId;
    if (assetTypeId == null) {
      maintenanceTemplates.sort(_compareTemplatesForMaintenancePlan);
      return maintenanceTemplates;
    }

    final matching = maintenanceTemplates
        .where((template) => template.assetTypeId == assetTypeId)
        .toList();
    matching.sort(_compareTemplatesForMaintenancePlan);
    return matching.isNotEmpty ? matching : maintenanceTemplates
      ..sort(_compareTemplatesForMaintenancePlan);
  }

  int _compareTemplatesForMaintenancePlan(
    ChecklistTemplate a,
    ChecklistTemplate b,
  ) {
    final hoursCompare = (a.intervalHours ?? 1 << 30).compareTo(
      b.intervalHours ?? 1 << 30,
    );
    if (hoursCompare != 0) return hoursCompare;
    return a.name.compareTo(b.name);
  }

  @override
  Widget build(BuildContext context) {
    final fixedAssetAsync =
        _isFixedAsset ? ref.watch(assetByIdProvider(widget.assetId!)) : null;
    final assetsAsync = _isFixedAsset ? null : ref.watch(assetsProvider);
    ref.watch(checklistTemplatesProvider);
    final activeAsset =
        _isFixedAsset ? fixedAssetAsync?.valueOrNull : _selectedAsset;
    final activeAssetId = activeAsset?.id;

    final scaffold = Scaffold(
      appBar: AppBar(
        title:
            Text(widget.readOnly ? 'Parts & Maintenance' : 'Maintenance Plan'),
      ),
      floatingActionButton: widget.readOnly || activeAssetId == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _showAddSheet(context, activeAsset!),
              icon: const Icon(Icons.add),
              label: const Text('Add Interval'),
              backgroundColor: AppColors.primary,
            ),
      body: Column(
        children: [
          if (_isFixedAsset)
            fixedAssetAsync!.when(
              loading: () => const LinearProgressIndicator(),
              error: (err, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text(err.toString(),
                    style: const TextStyle(color: AppColors.error)),
              ),
              data: (asset) => _AssetHeader(asset: asset),
            )
          else
            Padding(
              padding: const EdgeInsets.all(16),
              child: assetsAsync!.when(
                loading: () => const LinearProgressIndicator(),
                error: (err, _) => Text(err.toString(),
                    style: const TextStyle(color: AppColors.error)),
                data: (assets) => DropdownButtonFormField<Asset>(
                  initialValue: _selectedAsset,
                  decoration: const InputDecoration(
                    labelText: 'Select Asset',
                    prefixIcon: Icon(Icons.directions_boat_outlined),
                  ),
                  dropdownColor: AppColors.surfaceVariant,
                  items: assets
                      .map((a) => DropdownMenuItem<Asset>(
                            value: a,
                            child:
                                Text(a.name, overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (a) => setState(() => _selectedAsset = a),
                ),
              ),
            ),
          Expanded(
            child: activeAssetId == null
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.schedule,
                            size: 56, color: AppColors.textSecondary),
                        SizedBox(height: 12),
                        Text(
                          'Select an asset to manage its\nservice intervals.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  )
                : _IntervalList(
                    assetId: activeAssetId,
                    readOnly: widget.readOnly,
                    onEdit: widget.readOnly
                        ? null
                        : (summary) => _showEditSheet(
                              context,
                              activeAsset!,
                              summary,
                            ),
                  ),
          ),
        ],
      ),
    );

    if (widget.readOnly) return scaffold;

    return ClientCapabilityGate(
      clientId: activeAsset?.clientId,
      capability: ClientCapability.maintenancePlanning,
      allowedBuilder: (_) => scaffold,
      blockedBuilder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Maintenance Plan')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: ClientCapabilityDisabledPanel(
              capability: ClientCapability.maintenancePlanning,
              message:
                  'Maintenance planning is not enabled for this client. Existing service history remains available read-only.',
            ),
          ),
        ),
      ),
    );
  }

  void _showAddSheet(BuildContext context, Asset asset) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _AddIntervalSheet(
        assetId: asset.id,
        templates: _maintenanceTemplatesForAsset(
          ref.read(checklistTemplatesProvider).valueOrNull ?? const [],
          asset,
        ),
      ),
    );
  }

  void _showEditSheet(
    BuildContext context,
    Asset asset,
    ServiceIntervalSummary summary,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _EditIntervalSheet(
        assetId: asset.id,
        summary: summary,
        templates: _maintenanceTemplatesForAsset(
          ref.read(checklistTemplatesProvider).valueOrNull ?? const [],
          asset,
        ),
      ),
    );
  }
}

class _AssetHeader extends StatelessWidget {
  final Asset? asset;
  const _AssetHeader({required this.asset});

  @override
  Widget build(BuildContext context) {
    if (asset == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.directions_boat_outlined, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(asset!.name,
                    style: Theme.of(context).textTheme.titleSmall),
                if (asset!.make != null || asset!.model != null)
                  Text(
                    [asset!.make, asset!.model].whereType<String>().join(' '),
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IntervalList extends ConsumerWidget {
  final String assetId;
  final bool readOnly;
  final void Function(ServiceIntervalSummary summary)? onEdit;

  const _IntervalList({
    required this.assetId,
    required this.readOnly,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final intervalsAsync = ref.watch(serviceIntervalSummariesProvider(assetId));

    return intervalsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(
        child: Text(err.toString(),
            style: const TextStyle(color: AppColors.error)),
      ),
      data: (intervals) {
        final visible = readOnly
            ? intervals.where((summary) => summary.interval.enabled).toList()
            : intervals;
        if (visible.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.schedule,
                    size: 48, color: AppColors.textSecondary),
                const SizedBox(height: 12),
                Text(
                  readOnly
                      ? 'No published maintenance plan yet.'
                      : 'No service intervals configured.\nTap + to add one.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          itemCount: visible.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) => _IntervalCard(
            summary: visible[i],
            assetId: assetId,
            readOnly: readOnly,
            onEdit: onEdit,
          ),
        );
      },
    );
  }
}

class _IntervalCard extends ConsumerWidget {
  final ServiceIntervalSummary summary;
  final String assetId;
  final bool readOnly;
  final void Function(ServiceIntervalSummary summary)? onEdit;

  const _IntervalCard({
    required this.summary,
    required this.assetId,
    required this.readOnly,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final interval = summary.interval;
    final card = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: interval.enabled
              ? AppColors.cardBorder
              : AppColors.cardBorder.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '${interval.intervalHours.toInt()}h',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        interval.label ??
                            '${interval.intervalHours.toInt()}h Service',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: interval.enabled
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    if (!readOnly)
                      IconButton(
                        onPressed: () => onEdit?.call(summary),
                        icon: const Icon(Icons.tune_outlined, size: 18),
                        tooltip: 'Edit schedule',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                _TemplateLabel(templateId: interval.checklistTemplateId),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (summary.currentHours != null)
                      _MetricChip(
                        icon: Icons.speed_outlined,
                        label:
                            'Last known ${summary.currentHours!.toStringAsFixed(0)}h',
                      ),
                    if (summary.nextDueHours != null)
                      _MetricChip(
                        icon: Icons.schedule_outlined,
                        label:
                            'Next due ${summary.nextDueHours!.toStringAsFixed(0)}h',
                      ),
                    if (summary.hoursRemaining != null)
                      _MetricChip(
                        icon: Icons.timelapse_outlined,
                        label:
                            '${summary.hoursRemaining!.toStringAsFixed(0)}h remaining',
                      ),
                  ],
                ),
                if (interval.checklistTemplateId != null) ...[
                  const SizedBox(height: 8),
                  _PartsSummary(
                    templateId: interval.checklistTemplateId!,
                    fallbackName: interval.label ??
                        '${interval.intervalHours.toInt()}h Service',
                    canEdit: !readOnly,
                  ),
                ],
                if (!readOnly) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _openWorkOrderFlow(context, ref),
                    icon: Icon(
                      summary.activeWorkOrderId == null
                          ? Icons.add_task_outlined
                          : Icons.edit_outlined,
                      size: 18,
                    ),
                    label: Text(summary.activeWorkOrderId == null
                        ? 'Create work order'
                        : 'Edit work order'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    if (readOnly) return card;

    return Dismissible(
      key: Key(interval.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppColors.error.withOpacity(0.8),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete Interval'),
            content: Text(
                'Delete the ${interval.intervalHours.toInt()}h service interval?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style:
                    ElevatedButton.styleFrom(backgroundColor: AppColors.error),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (confirmed != true) return false;

        final success = await ref
            .read(serviceIntervalControllerProvider.notifier)
            .deleteInterval(interval.id, assetId);
        if (!success && context.mounted) {
          final error =
              ref.read(serviceIntervalControllerProvider.notifier).lastError;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(error ?? 'Failed to delete interval. Try again.'),
              backgroundColor: AppColors.error,
            ),
          );
        }
        return success;
      },
      child: card,
    );
  }

  void _openWorkOrderFlow(BuildContext context, WidgetRef ref) {
    if (summary.activeWorkOrderId != null) {
      context.push('/owner/work-orders/${summary.activeWorkOrderId}');
      return;
    }

    final interval = summary.interval;
    final templates = ref.read(checklistTemplatesProvider).valueOrNull;
    final templateName = interval.checklistTemplateId == null
        ? null
        : templates
            ?.where((t) => t.id == interval.checklistTemplateId)
            .firstOrNull
            ?.name;
    final draft = MaintenanceWorkOrderDraft.preventativeMaintenance(
      assetId: assetId,
      intervalHours: interval.intervalHours,
      currentHours: summary.currentHours,
      nextDueHours: summary.nextDueHours,
      intervalLabel: interval.label,
      checklistTemplateId: interval.checklistTemplateId,
      checklistTemplateName: templateName,
    );
    context.push(Uri(
      path: '/owner/work-orders/create',
      queryParameters: draft.toQueryParameters(),
    ).toString());
  }
}

class _MetricChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetricChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Chip(
      visualDensity: VisualDensity.compact,
      backgroundColor: AppColors.surfaceVariant,
      avatar: Icon(icon, size: 16),
      label: Text(label),
    );
  }
}

class _TemplateLabel extends ConsumerWidget {
  final String? templateId;
  const _TemplateLabel({required this.templateId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (templateId == null) {
      return const Text(
        'No checklist template',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
      );
    }
    final templatesAsync = ref.watch(checklistTemplatesProvider);
    return templatesAsync.when(
      loading: () => const Text('...',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      error: (_, __) => const Text('—',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      data: (templates) {
        final template = templates.where((t) => t.id == templateId).firstOrNull;
        return Text(
          template?.name ?? 'Unknown template',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        );
      },
    );
  }
}

class _PartsSummary extends ConsumerWidget {
  final String templateId;
  final String fallbackName;
  final bool canEdit;

  const _PartsSummary({
    required this.templateId,
    required this.fallbackName,
    required this.canEdit,
  });

  void _showPartsSheet(
      BuildContext context, String templateId, String templateName) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PmPartsListSheet(
        templateId: templateId,
        templateName: templateName,
        canEdit: canEdit,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partsAsync = ref.watch(pmPartsRequirementsProvider(templateId));
    final templatesAsync = ref.watch(checklistTemplatesProvider);

    return partsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (parts) {
        final templateName = templatesAsync.valueOrNull
                ?.where((t) => t.id == templateId)
                .firstOrNull
                ?.name ??
            fallbackName;
        return Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Chip(
              visualDensity: VisualDensity.compact,
              backgroundColor: AppColors.surfaceVariant,
              avatar: const Icon(Icons.inventory_2_outlined, size: 16),
              label:
                  Text('${parts.length} part${parts.length == 1 ? '' : 's'}'),
            ),
            TextButton.icon(
              onPressed: () =>
                  _showPartsSheet(context, templateId, templateName),
              icon: const Icon(Icons.visibility_outlined, size: 16),
              label: Text(canEdit ? 'Review parts' : 'View parts'),
            ),
          ],
        );
      },
    );
  }
}

class _AddIntervalSheet extends ConsumerStatefulWidget {
  final String assetId;
  final List<ChecklistTemplate> templates;
  const _AddIntervalSheet({required this.assetId, required this.templates});

  @override
  ConsumerState<_AddIntervalSheet> createState() => _AddIntervalSheetState();
}

class _AddIntervalSheetState extends ConsumerState<_AddIntervalSheet> {
  final _formKey = GlobalKey<FormState>();
  final _hoursCtrl = TextEditingController();
  final _labelCtrl = TextEditingController();
  final _nextDueCtrl = TextEditingController();
  ChecklistTemplate? _selectedTemplate;

  @override
  void dispose() {
    _hoursCtrl.dispose();
    _labelCtrl.dispose();
    _nextDueCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final hours = int.tryParse(_hoursCtrl.text.trim());
    if (hours == null) return;

    final success = await ref
        .read(serviceIntervalControllerProvider.notifier)
        .createInterval(
          assetId: widget.assetId,
          intervalHours: hours,
          checklistTemplateId: _selectedTemplate?.id,
          label: _labelCtrl.text.trim(),
          nextDueHours: double.tryParse(_nextDueCtrl.text.trim()),
        );

    if (success && mounted) {
      Navigator.pop(context);
    } else if (!success && mounted) {
      final error =
          ref.read(serviceIntervalControllerProvider.notifier).lastError;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error ?? 'Failed to save interval. Try again.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(serviceIntervalControllerProvider).isLoading;
    final templates = widget.templates;

    return SafeArea(
      top: false,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Add Service Interval',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _labelCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Service Label (optional)',
                    prefixIcon: Icon(Icons.label_outline),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _hoursCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Interval Hours (e.g. 250)',
                    prefixIcon: Icon(Icons.schedule),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Required';
                    }
                    if (int.tryParse(v.trim()) == null) {
                      return 'Enter a whole number of hours';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nextDueCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Next Due Hours (optional)',
                    helperText:
                        'Set this when real-world service timing was reset.',
                    prefixIcon: Icon(Icons.flag_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<ChecklistTemplate?>(
                  initialValue: _selectedTemplate,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Checklist Template (optional)',
                    helperText: templates.isEmpty
                        ? 'No maintenance templates match this asset yet.'
                        : 'Showing maintenance templates for this asset only.',
                    prefixIcon: const Icon(Icons.checklist_outlined),
                  ),
                  dropdownColor: AppColors.surfaceVariant,
                  items: [
                    const DropdownMenuItem<ChecklistTemplate?>(
                      value: null,
                      child: Text('— No template —',
                          style: TextStyle(color: AppColors.textSecondary)),
                    ),
                    ...templates
                        .map((t) => DropdownMenuItem<ChecklistTemplate?>(
                              value: t,
                              child:
                                  Text(t.name, overflow: TextOverflow.ellipsis),
                            )),
                  ],
                  onChanged: (t) => setState(() => _selectedTemplate = t),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: isLoading ? null : _save,
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
      ),
    );
  }
}

class _EditIntervalSheet extends ConsumerStatefulWidget {
  final String assetId;
  final ServiceIntervalSummary summary;
  final List<ChecklistTemplate> templates;

  const _EditIntervalSheet({
    required this.assetId,
    required this.summary,
    required this.templates,
  });

  @override
  ConsumerState<_EditIntervalSheet> createState() => _EditIntervalSheetState();
}

class _EditIntervalSheetState extends ConsumerState<_EditIntervalSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _labelCtrl;
  late final TextEditingController _hoursCtrl;
  late final TextEditingController _nextDueCtrl;
  late bool _enabled;
  ChecklistTemplate? _selectedTemplate;

  @override
  void initState() {
    super.initState();
    final interval = widget.summary.interval;
    _labelCtrl = TextEditingController(text: interval.label ?? '');
    _hoursCtrl =
        TextEditingController(text: interval.intervalHours.toInt().toString());
    _nextDueCtrl = TextEditingController(
      text: widget.summary.nextDueHours?.toStringAsFixed(0) ?? '',
    );
    _enabled = interval.enabled;
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _hoursCtrl.dispose();
    _nextDueCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final hours = int.tryParse(_hoursCtrl.text.trim());
    if (hours == null) return;

    final success = await ref
        .read(serviceIntervalControllerProvider.notifier)
        .updateInterval(
          widget.summary.interval.id,
          assetId: widget.assetId,
          intervalHours: hours,
          checklistTemplateId: _selectedTemplate?.id,
          clearChecklistTemplate: _selectedTemplate == null &&
              widget.summary.interval.checklistTemplateId != null,
          label: _labelCtrl.text.trim(),
          enabled: _enabled,
          nextDueHours: double.tryParse(_nextDueCtrl.text.trim()),
        );

    if (success && mounted) {
      Navigator.pop(context);
    } else if (!success && mounted) {
      final error =
          ref.read(serviceIntervalControllerProvider.notifier).lastError;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error ?? 'Failed to update interval. Try again.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(serviceIntervalControllerProvider).isLoading;
    final templates = widget.templates;
    final interval = widget.summary.interval;

    return SafeArea(
      top: false,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Edit Service Interval',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _labelCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Service Label (optional)',
                    prefixIcon: Icon(Icons.label_outline),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _hoursCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Interval Hours',
                    prefixIcon: Icon(Icons.schedule),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Required';
                    }
                    if (int.tryParse(v.trim()) == null) {
                      return 'Enter a whole number of hours';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nextDueCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Next Due Hours',
                    helperText:
                        'Use this to re-anchor the schedule after real-world service.',
                    prefixIcon: Icon(Icons.flag_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                Builder(builder: (context) {
                  _selectedTemplate ??= templates
                      .where((t) => t.id == interval.checklistTemplateId)
                      .firstOrNull;
                  return DropdownButtonFormField<ChecklistTemplate?>(
                    initialValue: _selectedTemplate,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Checklist Template (optional)',
                      helperText: templates.isEmpty
                          ? 'No maintenance templates match this asset yet.'
                          : 'Showing maintenance templates for this asset only.',
                      prefixIcon: const Icon(Icons.checklist_outlined),
                    ),
                    dropdownColor: AppColors.surfaceVariant,
                    items: [
                      const DropdownMenuItem<ChecklistTemplate?>(
                        value: null,
                        child: Text('— No template —',
                            style: TextStyle(color: AppColors.textSecondary)),
                      ),
                      ...templates
                          .map((t) => DropdownMenuItem<ChecklistTemplate?>(
                                value: t,
                                child: Text(t.name,
                                    overflow: TextOverflow.ellipsis),
                              )),
                    ],
                    onChanged: (t) => setState(() => _selectedTemplate = t),
                  );
                }),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Visible to client'),
                  subtitle:
                      const Text('Hide intervals you do not want published.'),
                  value: _enabled,
                  onChanged: isLoading
                      ? null
                      : (value) => setState(() => _enabled = value),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: isLoading ? null : _save,
                  icon: isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.save),
                  label: const Text('Save Changes'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
