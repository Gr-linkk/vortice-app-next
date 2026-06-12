import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/assets/asset_provider.dart';
import 'package:vortice_app/features/checklists/checklist_provider.dart';
import 'package:vortice_app/features/engines/engine_kind_options.dart';
import 'package:vortice_app/features/work_orders/create_work_order_pm_parts_preview.dart';
import 'package:vortice_app/features/work_orders/create_work_order_support.dart';
import 'package:vortice_app/features/work_orders/work_order_provider.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/models/work_order.dart';

class CreateWorkOrderForm extends ConsumerWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController titleCtrl;
  final TextEditingController descCtrl;
  final TextEditingController hoursCtrl;
  final TextEditingController partsCtrl;
  final WorkOrderJobType jobType;
  final String? selectedAssetId;
  final String? selectedEngineId;
  final List<String> selectedTechIds;
  final String? selectedChecklistTemplateId;
  final DateTime? scheduledDate;
  final bool isLoading;
  final ValueChanged<WorkOrderJobType> onJobTypeChanged;
  final ValueChanged<String?> onAssetChanged;
  final ValueChanged<String?> onEngineChanged;
  final ValueChanged<String?> onChecklistTemplateChanged;
  final VoidCallback onPickScheduledDate;
  final VoidCallback onClearScheduledDate;
  final Future<void> Function(List<Map<String, dynamic>> employees)
      onPickTechnicians;
  final VoidCallback onSubmit;

  const CreateWorkOrderForm({
    super.key,
    required this.formKey,
    required this.titleCtrl,
    required this.descCtrl,
    required this.hoursCtrl,
    required this.partsCtrl,
    required this.jobType,
    required this.selectedAssetId,
    required this.selectedEngineId,
    required this.selectedTechIds,
    required this.selectedChecklistTemplateId,
    required this.scheduledDate,
    required this.isLoading,
    required this.onJobTypeChanged,
    required this.onAssetChanged,
    required this.onEngineChanged,
    required this.onChecklistTemplateChanged,
    required this.onPickScheduledDate,
    required this.onClearScheduledDate,
    required this.onPickTechnicians,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final assetsAsync = ref.watch(visibleAssetsProvider);
    final selectedAssetForAssignment = assetsAsync.valueOrNull
        ?.where((asset) => asset.id == selectedAssetId)
        .firstOrNull;
    final assignableProfilesAsync = ref.watch(
      assignableWorkOrderProfilesProvider(selectedAssetForAssignment?.clientId),
    );

    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── JOB DETAILS ───────────────────────────────────────
          createWorkOrderSectionHeader('JOB DETAILS'),
          const SizedBox(height: 8),
          TextFormField(
            controller: titleCtrl,
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
            initialValue: jobType,
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
            onChanged: (v) => onJobTypeChanged(v!),
          ),
          const SizedBox(height: 16),
          assetsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => const SizedBox.shrink(),
            data: (assets) => DropdownButtonFormField<String?>(
              initialValue: selectedAssetId,
              decoration: InputDecoration(
                labelText: '${l10n.linkedAsset} *',
                prefixIcon: const Icon(Icons.directions_boat_outlined),
              ),
              dropdownColor: AppColors.surfaceVariant,
              items: [
                DropdownMenuItem(
                  value: null,
                  child: Text(l10n.noAsset,
                      style: const TextStyle(color: AppColors.textSecondary)),
                ),
                ...assets.map((a) => DropdownMenuItem(
                      value: a.id,
                      child: Text(a.name),
                    )),
              ],
              onChanged: onAssetChanged,
            ),
          ),
          if (selectedAssetId != null)
            ref.watch(assetEnginesProvider(selectedAssetId!)).when(
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
                          initialValue: selectedEngineId,
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
                          onChanged: onEngineChanged,
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
                      ?.where((asset) => asset.id == selectedAssetId)
                      .firstOrNull;
                  final filtered =
                      checklistTemplatesForAsset(templates, selectedAsset);
                  final selectedTemplateStillVisible = filtered
                      .any((t) => t.id == selectedChecklistTemplateId);
                  final selectedValue = selectedTemplateStillVisible
                      ? selectedChecklistTemplateId
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
                        borderSide: const BorderSide(color: AppColors.divider),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppColors.divider),
                      ),
                    ),
                    dropdownColor: AppColors.surfaceVariant,
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('None',
                            style: TextStyle(color: AppColors.textSecondary)),
                      ),
                      for (final t in filtered)
                        DropdownMenuItem<String?>(
                          value: t.id,
                          child: Text(
                            checklistTemplateLabel(t),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                    ],
                    onChanged: onChecklistTemplateChanged,
                  );
                },
              ),

          // ── PM PARTS ────────────────────────────────────────────
          if (jobType == WorkOrderJobType.preventative &&
              selectedChecklistTemplateId != null)
            CreateWorkOrderPmPartsPreview(
              templateId: selectedChecklistTemplateId!,
            ),

          // ── ASSIGNMENT ────────────────────────────────────────
          const SizedBox(height: 24),
          createWorkOrderSectionHeader('ASSIGNMENT'),
          const SizedBox(height: 8),
          assignableProfilesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => const SizedBox.shrink(),
            data: (employees) {
              final selectedNames = employees
                  .where((employee) =>
                      selectedTechIds.contains(employee['id'] as String))
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
                    onPressed: () => onPickTechnicians(employees),
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
          createWorkOrderSectionHeader('SCHEDULING'),
          const SizedBox(height: 8),
          InkWell(
            onTap: onPickScheduledDate,
            borderRadius: BorderRadius.circular(10),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: l10n.scheduledDate,
                prefixIcon: const Icon(Icons.calendar_today_outlined),
                suffixIcon: scheduledDate != null
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: onClearScheduledDate,
                      )
                    : null,
              ),
              child: Text(
                scheduledDate != null
                    ? scheduledDate!.toLocal().toString().split(' ').first
                    : l10n.selectDate,
                style: TextStyle(
                  color: scheduledDate != null
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: hoursCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Current Engine Hours',
              hintText: 'e.g. 1250.5',
              prefixIcon: Icon(Icons.timer_outlined),
            ),
          ),

          // ── NOTES ─────────────────────────────────────────────
          const SizedBox(height: 24),
          createWorkOrderSectionHeader('NOTES'),
          const SizedBox(height: 8),
          TextFormField(
            controller: descCtrl,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: l10n.description,
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: partsCtrl,
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
            onPressed: isLoading ? null : onSubmit,
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
    );
  }
}
