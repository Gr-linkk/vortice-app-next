import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/work_orders/work_order_edit_support.dart';
import 'package:vortice_app/features/work_orders/work_order_edit_tech_picker_sheet.dart';
import 'package:vortice_app/features/work_orders/work_order_provider.dart';
import 'package:vortice_app/features/work_orders/work_order_hours_validation.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/models/work_order.dart';

class WorkOrderEditForm extends ConsumerWidget {
  final WorkOrder workOrder;
  final GlobalKey<FormState> formKey;
  final TextEditingController titleCtrl;
  final TextEditingController descCtrl;
  final TextEditingController hoursStartCtrl;
  final TextEditingController hoursEndCtrl;
  final TextEditingController labourCtrl;
  final TextEditingController notesCtrl;
  final TextEditingController onHoldCtrl;
  final DateTime? scheduledDate;
  final List<String> assignedTechIds;
  final ValueChanged<DateTime?> onScheduledDateChanged;
  final ValueChanged<List<String>> onAssignedTechIdsChanged;
  final VoidCallback onSave;

  const WorkOrderEditForm({
    super.key,
    required this.workOrder,
    required this.formKey,
    required this.titleCtrl,
    required this.descCtrl,
    required this.hoursStartCtrl,
    required this.hoursEndCtrl,
    required this.labourCtrl,
    required this.notesCtrl,
    required this.onHoldCtrl,
    required this.scheduledDate,
    required this.assignedTechIds,
    required this.onScheduledDateChanged,
    required this.onAssignedTechIdsChanged,
    required this.onSave,
  });

  Future<void> _pickDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: scheduledDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2040),
    );
    if (picked != null) onScheduledDateChanged(picked);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final isLoading = ref.watch(workOrderControllerProvider).isLoading;
    final dateFmt = DateFormat.yMMMd();

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Form(
        key: formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.editWorkOrder,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: titleCtrl,
                decoration: InputDecoration(labelText: l10n.workOrderTitle),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? l10n.fieldRequired : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: descCtrl,
                maxLines: 3,
                decoration: InputDecoration(labelText: l10n.description),
              ),
              const SizedBox(height: 12),
              _TechnicianAssignmentField(
                clientId: workOrder.clientId,
                assignedTechIds: assignedTechIds,
                onAssignedTechIdsChanged: onAssignedTechIdsChanged,
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => _pickDate(context),
                child: AbsorbPointer(
                  child: TextFormField(
                    decoration: InputDecoration(
                      labelText: l10n.scheduledDate,
                      suffixIcon: const Icon(Icons.calendar_today),
                    ),
                    controller: TextEditingController(
                      text: scheduledDate != null
                          ? dateFmt.format(scheduledDate!)
                          : '',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: hoursStartCtrl,
                      validator: (v) => validateWorkOrderHours(v, l10n),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(labelText: l10n.hoursAtStart),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: hoursEndCtrl,
                      validator: (v) => validateWorkOrderHours(v, l10n),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(labelText: l10n.hoursAtEnd),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: labourCtrl,
                validator: (v) => validateWorkOrderHours(v, l10n),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(labelText: l10n.labourHours),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: notesCtrl,
                maxLines: 2,
                decoration: InputDecoration(labelText: l10n.internalNotes),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: onHoldCtrl,
                decoration: InputDecoration(labelText: l10n.onHoldReason),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: isLoading ? null : onSave,
                child: isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(l10n.save),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TechnicianAssignmentField extends ConsumerWidget {
  final String? clientId;
  final List<String> assignedTechIds;
  final ValueChanged<List<String>> onAssignedTechIdsChanged;

  const _TechnicianAssignmentField({
    required this.clientId,
    required this.assignedTechIds,
    required this.onAssignedTechIdsChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final assignableAsync = ref.watch(
      assignableWorkOrderProfilesProvider(clientId),
    );

    return assignableAsync.when(
      loading: () => const LinearProgressIndicator(),
      error: (_, __) => const SizedBox.shrink(),
      data: (employees) {
        final selectedNames = selectedTechnicianNames(
          employees,
          assignedTechIds,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton.icon(
              onPressed: () async {
                final result = await showWorkOrderTechPickerSheet(
                  context: context,
                  employees: employees,
                  initialSelection: assignedTechIds,
                );
                if (result != null) onAssignedTechIdsChanged(result);
              },
              icon: const Icon(Icons.people_outline),
              label: Text(
                selectedNames.isEmpty
                    ? l10n.reassignTech
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
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'No technicians assigned',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
