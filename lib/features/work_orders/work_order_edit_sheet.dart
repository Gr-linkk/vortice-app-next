import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/work_orders/work_order_edit_form.dart';
import 'package:vortice_app/features/work_orders/work_order_edit_support.dart';
import 'package:vortice_app/features/work_orders/work_order_provider.dart';
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
  const EditWorkOrderSheet({super.key, required this.workOrder});

  @override
  ConsumerState<EditWorkOrderSheet> createState() => _EditWorkOrderSheetState();
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final data = buildUpdateWorkOrderPayload(
      title: _titleCtrl.text,
      description: _descCtrl.text,
      assignedTechIds: _assignedTechIds,
      scheduledDate: _scheduledDate,
      hoursAtStartText: _hoursStartCtrl.text,
      hoursAtEndText: _hoursEndCtrl.text,
      labourHoursText: _labourCtrl.text,
      notesInternal: _notesCtrl.text,
      onHoldReason: _onHoldCtrl.text,
    );

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

  @override
  Widget build(BuildContext context) {
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

    return WorkOrderEditForm(
      workOrder: widget.workOrder,
      formKey: _formKey,
      titleCtrl: _titleCtrl,
      descCtrl: _descCtrl,
      hoursStartCtrl: _hoursStartCtrl,
      hoursEndCtrl: _hoursEndCtrl,
      labourCtrl: _labourCtrl,
      notesCtrl: _notesCtrl,
      onHoldCtrl: _onHoldCtrl,
      scheduledDate: _scheduledDate,
      assignedTechIds: _assignedTechIds,
      onScheduledDateChanged: (value) => setState(() => _scheduledDate = value),
      onAssignedTechIdsChanged: (value) =>
          setState(() => _assignedTechIds = value),
      onSave: _save,
    );
  }
}
