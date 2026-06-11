import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/work_orders/work_order_provider.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/models/work_order.dart';

void showEditWorkOrderSheet(BuildContext context, WorkOrder workOrder) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => EditWorkOrderSheet(workOrder: workOrder),
  );
}

class EditWorkOrderSheet extends ConsumerStatefulWidget {
  final WorkOrder workOrder;
  const EditWorkOrderSheet({required this.workOrder});

  @override
  ConsumerState<EditWorkOrderSheet> createState() =>
      _EditWorkOrderSheetState();
}

class _EditWorkOrderSheetState extends ConsumerState<EditWorkOrderSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _hoursStartCtrl;
  late final TextEditingController _hoursEndCtrl;
  late final TextEditingController _labourCtrl;
  late final TextEditingController _notesCtrl;
  late final TextEditingController _onHoldCtrl;
  late DateTime? _scheduledDate;
  List<String> _assignedTechIds = const [];
  bool _didSeedAssignments = false;

  @override
  void initState() {
    super.initState();
    final wo = widget.workOrder;
    _titleCtrl = TextEditingController(text: wo.title);
    _descCtrl = TextEditingController(text: wo.description ?? '');
    _hoursStartCtrl =
        TextEditingController(text: wo.hoursAtStart?.toString() ?? '');
    _hoursEndCtrl =
        TextEditingController(text: wo.hoursAtEnd?.toString() ?? '');
    _labourCtrl = TextEditingController(text: wo.labourHours?.toString() ?? '');
    _notesCtrl = TextEditingController(text: wo.notesInternal ?? '');
    _onHoldCtrl = TextEditingController(text: wo.onHoldReason ?? '');
    _scheduledDate = wo.scheduledDate;
    _assignedTechIds = wo.assignedTo != null ? [wo.assignedTo!] : const [];
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _hoursStartCtrl.dispose();
    _hoursEndCtrl.dispose();
    _labourCtrl.dispose();
    _notesCtrl.dispose();
    _onHoldCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _scheduledDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2040),
    );
    if (picked != null) setState(() => _scheduledDate = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final data = <String, dynamic>{
      'title': _titleCtrl.text.trim(),
      'description':
          _descCtrl.text.trim().isNotEmpty ? _descCtrl.text.trim() : null,
      'assigned_to':
          _assignedTechIds.isNotEmpty ? _assignedTechIds.first : null,
      'scheduled_date': _scheduledDate?.toIso8601String(),
      'hours_at_start': double.tryParse(_hoursStartCtrl.text.trim()),
      'hours_at_end': double.tryParse(_hoursEndCtrl.text.trim()),
      'labour_hours': double.tryParse(_labourCtrl.text.trim()),
      'notes_internal':
          _notesCtrl.text.trim().isNotEmpty ? _notesCtrl.text.trim() : null,
      'on_hold_reason':
          _onHoldCtrl.text.trim().isNotEmpty ? _onHoldCtrl.text.trim() : null,
    };

    final success =
        await ref.read(workOrderControllerProvider.notifier).updateWorkOrder(
              widget.workOrder.id,
              data,
              assignedProfileIds: _assignedTechIds,
            );

    if (success && mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _pickTechnicians(List<Map<String, dynamic>> employees) async {
    final selected = Set<String>.from(_assignedTechIds);

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
      setState(() => _assignedTechIds = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isLoading = ref.watch(workOrderControllerProvider).isLoading;
    final dateFmt = DateFormat.yMMMd();
    final assignmentsAsync =
        ref.watch(workOrderAssignmentsProvider(widget.workOrder.id));

    if (!_didSeedAssignments) {
      assignmentsAsync.whenData((assignments) {
        _didSeedAssignments = true;
        final assignmentIds = assignments.map((a) => a.profileId).toList();
        if (assignmentIds.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() => _assignedTechIds = assignmentIds);
          });
        }
      });
    }

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
              Text(l10n.editWorkOrder,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              TextFormField(
                controller: _titleCtrl,
                decoration: InputDecoration(labelText: l10n.workOrderTitle),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? l10n.fieldRequired : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descCtrl,
                maxLines: 3,
                decoration: InputDecoration(labelText: l10n.description),
              ),
              const SizedBox(height: 12),
              // Tech reassignment
              Consumer(builder: (context, ref, _) {
                final assignableAsync = ref.watch(
                  assignableWorkOrderProfilesProvider(
                      widget.workOrder.clientId),
                );
                return assignableAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (employees) {
                    final selectedNames = employees
                        .where((employee) =>
                            _assignedTechIds.contains(employee['id'] as String))
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
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: AppColors.textSecondary),
                            ),
                          ),
                      ],
                    );
                  },
                );
              }),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: _pickDate,
                child: AbsorbPointer(
                  child: TextFormField(
                    decoration: InputDecoration(
                      labelText: l10n.scheduledDate,
                      suffixIcon: const Icon(Icons.calendar_today),
                    ),
                    controller: TextEditingController(
                      text: _scheduledDate != null
                          ? dateFmt.format(_scheduledDate!)
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
                      controller: _hoursStartCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: l10n.hoursAtStart),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _hoursEndCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: l10n.hoursAtEnd),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _labourCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: l10n.labourHours),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesCtrl,
                maxLines: 2,
                decoration: InputDecoration(labelText: l10n.internalNotes),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _onHoldCtrl,
                decoration: InputDecoration(labelText: l10n.onHoldReason),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: isLoading ? null : _save,
                child: isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
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
