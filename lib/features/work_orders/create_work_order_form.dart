import 'package:vortice_app/core/app_dropdown_field.dart';
import 'package:vortice_app/core/localized_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/assets/asset_provider.dart';
import 'package:vortice_app/features/checklists/checklist_provider.dart';
import 'package:vortice_app/features/engines/engine_kind_options.dart';
import 'package:vortice_app/features/work_orders/create_work_order_pm_parts_preview.dart';
import 'package:vortice_app/features/work_orders/create_work_order_pm_parts_support.dart';
import 'package:vortice_app/features/work_orders/create_work_order_support.dart';
import 'package:vortice_app/features/work_orders/work_order_provider.dart';
import 'package:vortice_app/features/work_orders/work_order_hours_validation.dart';
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
    final es = Localizations.localeOf(context).languageCode == 'es';
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
          createWorkOrderSectionHeader(
            context,
            localizedText(
              context,
              'JOB DETAILS',
              'DETALLES DEL TRABAJO',
              'DÉTAILS DU TRAVAIL',
            ),
          ),
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
          AppDropdownField<WorkOrderJobType>(
            initialValue: jobType,
            decoration: InputDecoration(labelText: l10n.jobType),
            dropdownColor: context.appColors.surfaceVariant,
            items: WorkOrderJobType.values
                .map(
                  (t) => DropdownMenuItem(
                    value: t,
                    child: Text(
                      t.label(
                        Localizations.localeOf(context).languageCode == 'es',
                        fr: isFrench(context),
                      ),
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) => onJobTypeChanged(v!),
          ),
          const SizedBox(height: 16),
          assetsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => const SizedBox.shrink(),
            data: (assets) => AppDropdownField<String?>(
              initialValue: selectedAssetId,
              decoration: InputDecoration(
                labelText: '${l10n.linkedAsset} *',
                prefixIcon: const Icon(Icons.directions_boat_outlined),
              ),
              dropdownColor: context.appColors.surfaceVariant,
              items: [
                DropdownMenuItem(
                  value: null,
                  child: Text(
                    l10n.noAsset,
                    style: TextStyle(color: context.appColors.textSecondary),
                  ),
                ),
                ...assets.map(
                  (a) => DropdownMenuItem(value: a.id, child: Text(a.name)),
                ),
              ],
              onChanged: onAssetChanged,
            ),
          ),
          if (selectedAssetId != null)
            ref
                .watch(assetEnginesProvider(selectedAssetId!))
                .when(
                  loading: () => const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: SizedBox(
                      height: 48,
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (engines) {
                    if (engines.isEmpty) return const SizedBox.shrink();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 16),
                        AppDropdownField<String?>(
                          initialValue: selectedEngineId,
                          decoration: InputDecoration(
                            labelText: es
                                ? 'Motor / Posición'
                                : 'Engine / Position',
                            prefixIcon: const Icon(Icons.settings_outlined),
                          ),
                          dropdownColor: context.appColors.surfaceVariant,
                          items: [
                            DropdownMenuItem(
                              value: null,
                              child: Text(
                                localizedText(
                                  context,
                                  'None',
                                  'Ninguno',
                                  'Aucun',
                                ),
                                style: TextStyle(
                                  color: context.appColors.textSecondary,
                                ),
                              ),
                            ),
                            ...engines.map((e) {
                              final label = (e['label'] as String?)?.trim();
                              final kind = e['kind'] as String?;
                              return DropdownMenuItem(
                                value: e['id'] as String,
                                child: Text(
                                  label != null && label.isNotEmpty
                                      ? label
                                      : _localizedEngineLabel(kind, es),
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
          Text(
            localizedText(
              context,
              'Checklist Template',
              'Plantilla de lista de verificación',
              'Modèle de liste de contrôle',
            ),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          ref
              .watch(checklistTemplatesProvider)
              .when(
                loading: () => const SizedBox(
                  height: 48,
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                error: (_, __) => Text(
                  es
                      ? 'No se pudieron cargar las plantillas'
                      : 'Could not load templates',
                  style: TextStyle(color: context.appColors.error),
                ),
                data: (templates) {
                  final selectedAsset = assetsAsync.valueOrNull
                      ?.where((asset) => asset.id == selectedAssetId)
                      .firstOrNull;
                  final filtered = checklistTemplatesForAsset(
                    templates,
                    selectedAsset,
                    engineId: selectedEngineId,
                  );
                  final selectedTemplateStillVisible = filtered.any(
                    (t) => t.id == selectedChecklistTemplateId,
                  );
                  final selectedValue = selectedTemplateStillVisible
                      ? selectedChecklistTemplateId
                      : null;

                  return AppDropdownField<String?>(
                    initialValue: selectedValue,
                    isExpanded: true,
                    decoration: InputDecoration(
                      hintText: es
                          ? 'Opcional: asignar una lista'
                          : 'Optional — assign a checklist',
                      hintStyle: TextStyle(
                        color: context.appColors.textSecondary,
                        fontSize: 14,
                      ),
                      filled: true,
                      fillColor: context.appColors.surface,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: context.appColors.divider,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: context.appColors.divider,
                        ),
                      ),
                    ),
                    dropdownColor: context.appColors.surfaceVariant,
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text(
                          localizedText(context, 'None', 'Ninguna', 'Aucune'),
                          style: TextStyle(
                            color: context.appColors.textSecondary,
                          ),
                        ),
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
          if (shouldShowPmPartsKitPreview(
            jobType: jobType,
            checklistTemplateId: selectedChecklistTemplateId,
          ))
            CreateWorkOrderPmPartsPreview(
              templateId: selectedChecklistTemplateId!,
            ),

          // ── ASSIGNMENT ────────────────────────────────────────
          const SizedBox(height: 24),
          createWorkOrderSectionHeader(
            context,
            localizedText(context, 'ASSIGNMENT', 'ASIGNACIÓN', 'AFFECTATION'),
          ),
          const SizedBox(height: 8),
          assignableProfilesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => const SizedBox.shrink(),
            data: (employees) {
              final selectedNames = employees
                  .where(
                    (employee) =>
                        selectedTechIds.contains(employee['id'] as String),
                  )
                  .map(
                    (employee) =>
                        (employee['full_name'] as String?)?.trim().isNotEmpty ==
                            true
                        ? employee['full_name'] as String
                        : localizedText(
                            context,
                            'Unnamed tech',
                            'Técnico sin nombre',
                            'Technicien sans nom',
                          ),
                  )
                  .toList();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => onPickTechnicians(employees),
                    icon: const Icon(Icons.people_outline),
                    label: Text(
                      selectedNames.isEmpty
                          ? localizedText(
                              context,
                              'Assign technicians',
                              'Asignar técnicos',
                              'Affecter des techniciens',
                            )
                          : (es
                                ? 'Asignados (${selectedNames.length})'
                                : 'Assigned (${selectedNames.length})'),
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
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        es
                            ? 'Aún no hay técnicos asignados'
                            : 'No technicians assigned yet',
                        style: TextStyle(
                          color: context.appColors.textSecondary,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),

          // ── SCHEDULING ────────────────────────────────────────
          const SizedBox(height: 24),
          createWorkOrderSectionHeader(
            context,
            localizedText(
              context,
              'SCHEDULING',
              'PROGRAMACIÓN',
              'PLANIFICATION',
            ),
          ),
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
                      ? context.appColors.textPrimary
                      : context.appColors.textSecondary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: hoursCtrl,
            validator: (v) => validateWorkOrderHours(v, l10n),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: es
                  ? 'Horas actuales del motor'
                  : 'Current Engine Hours',
              hintText: localizedText(
                context,
                'e.g. 1250.5',
                'p. ej., 1250.5',
                'p. ex. 1 250,5',
              ),
              prefixIcon: const Icon(Icons.timer_outlined),
            ),
          ),

          // ── NOTES ─────────────────────────────────────────────
          const SizedBox(height: 24),
          createWorkOrderSectionHeader(
            context,
            localizedText(context, 'NOTES', 'NOTAS', 'NOTES'),
          ),
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
            decoration: InputDecoration(
              labelText: es
                  ? 'Piezas / Materiales previstos'
                  : 'Parts / Materials Expected',
              hintText: es
                  ? 'p. ej., filtro de aceite, impulsor, ánodos...'
                  : 'e.g. Oil filter, impeller, zincs...',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: isLoading ? null : onSubmit,
            child: isLoading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: context.appColors.onPrimary,
                    ),
                  )
                : Text(l10n.createWorkOrder),
          ),
        ],
      ),
    );
  }
}

String _localizedEngineLabel(String? kind, bool es) {
  if (!es) return suggestedEngineLabel(kind);
  return switch (normalizeEngineKind(kind)) {
    'port' => 'Motor de babor',
    'starboard' => 'Motor de estribor',
    'wing' => 'Motor de apoyo',
    'generator' => 'Generador',
    'auxiliary' => 'Motor auxiliar',
    _ => 'Motor principal',
  };
}
