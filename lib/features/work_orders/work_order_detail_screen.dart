import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/work_orders/work_order_provider.dart';
import 'package:vortice_app/models/profile.dart';
import 'package:vortice_app/models/work_order.dart';
import 'package:vortice_app/features/invoices/invoice_provider.dart';
import 'package:vortice_app/features/checklists/checklist_provider.dart';
import 'package:vortice_app/features/parts/pm_parts_provider.dart';
import 'package:vortice_app/features/parts/pm_kits_screen.dart';

class WorkOrderDetailScreen extends ConsumerWidget {
  final String workOrderId;
  const WorkOrderDetailScreen({super.key, required this.workOrderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final woAsync = ref.watch(workOrderByIdProvider(workOrderId));
    final profile = ref.watch(profileProvider).valueOrNull;
    final isOwner = profile?.role == UserRole.owner;
    final canManage =
        profile?.role == UserRole.owner || profile?.role == UserRole.employee;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.workOrderDetail),
        actions: [
          if (isOwner)
            woAsync.whenOrNull(
                  data: (wo) {
                    if (wo == null || wo.status == WorkOrderStatus.closed) {
                      return null;
                    }
                    return IconButton(
                      icon: const Icon(Icons.edit),
                      tooltip: l10n.edit,
                      onPressed: () => _showEditSheet(context, ref, wo),
                    );
                  },
                ) ??
                const SizedBox.shrink(),
        ],
      ),
      body: woAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Text(err.toString(),
              style: const TextStyle(color: AppColors.error)),
        ),
        data: (wo) {
          if (wo == null) return Center(child: Text(l10n.notFound));
          return _WorkOrderBody(
              workOrder: wo, canManage: canManage, profile: profile);
        },
      ),
    );
  }

  void _showEditSheet(BuildContext context, WidgetRef ref, WorkOrder wo) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _EditWorkOrderSheet(workOrder: wo),
    );
  }
}

class _WorkOrderBody extends ConsumerWidget {
  final WorkOrder workOrder;
  final bool canManage;
  final Profile? profile;

  const _WorkOrderBody({
    required this.workOrder,
    required this.canManage,
    this.profile,
  });

  Color _statusColor() => switch (workOrder.status) {
        WorkOrderStatus.draft => AppColors.textSecondary,
        WorkOrderStatus.assigned => AppColors.primary,
        WorkOrderStatus.inProgress => AppColors.warning,
        WorkOrderStatus.onHold => AppColors.warning,
        WorkOrderStatus.pendingReview => AppColors.primary,
        WorkOrderStatus.invoiced => AppColors.success,
        WorkOrderStatus.closed => AppColors.success,
      };

  void _showWorkOrderActionFailed(BuildContext context, WidgetRef ref) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Work order could not be updated right now. Reconnect and try again.',
        ),
        backgroundColor: AppColors.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final isLoading = ref.watch(workOrderControllerProvider).isLoading;
    final isOwner = profile?.role == UserRole.owner;
    final isOwnerOrEmployee = isOwner || profile?.role == UserRole.employee;

    // Fetch related names
    final assetNameAsync = ref.watch(assetNameProvider(workOrder.assetId));
    final techNameAsync = workOrder.assignedTo != null
        ? ref.watch(profileNameProvider(workOrder.assignedTo!))
        : null;
    final assignmentNamesAsync =
        ref.watch(workOrderAssignmentNamesProvider(workOrder.id));

    final prefix = switch (profile?.role) {
      UserRole.owner => '/owner',
      UserRole.employee => '/employee',
      _ => '/owner',
    };

    final checklistDoneAsync =
        ref.watch(checklistHasResponsesProvider(workOrder.id));
    final checklistDone = checklistDoneAsync.valueOrNull ?? false;

    final dateFmt = DateFormat.yMMMd();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Status banner ──────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _statusColor().withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _statusColor().withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(workOrder.title,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _statusColor().withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  workOrder.status.name,
                  style: TextStyle(
                      color: _statusColor(),
                      fontSize: 11,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── Description ────────────────────────────────────────────
        if (workOrder.description != null) ...[
          Text(l10n.description,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: AppColors.primary, letterSpacing: 1.2)),
          const SizedBox(height: 6),
          Text(workOrder.description!),
          const SizedBox(height: 16),
        ],

        // ── Details section ────────────────────────────────────────
        Text(
          l10n.woDetailsSection.toUpperCase(),
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: AppColors.primary, letterSpacing: 1.2),
        ),
        const SizedBox(height: 8),

        // Asset name
        assetNameAsync.when(
          loading: () => _InfoRow(
              icon: Icons.directions_boat,
              label: l10n.linkedAsset,
              value: '...'),
          error: (_, __) => _InfoRow(
              icon: Icons.directions_boat, label: l10n.linkedAsset, value: '—'),
          data: (name) => _InfoRow(
              icon: Icons.directions_boat,
              label: l10n.linkedAsset,
              value: name ?? '—'),
        ),

        // Job type
        _InfoRow(
          icon: Icons.build_outlined,
          label: l10n.jobType,
          value: workOrder.jobType.name,
        ),

        // Assigned tech(s)
        assignmentNamesAsync.when(
          loading: () => const _InfoRow(
              icon: Icons.people_outline,
              label: 'Assigned Techs',
              value: '...'),
          error: (_, __) {
            if (techNameAsync == null) {
              return const _InfoRow(
                icon: Icons.people_outline,
                label: 'Assigned Techs',
                value: '—',
              );
            }

            return techNameAsync.when(
              loading: () => _InfoRow(
                  icon: Icons.person_outline,
                  label: l10n.assignedTech,
                  value: '...'),
              error: (_, __) => _InfoRow(
                  icon: Icons.person_outline,
                  label: l10n.assignedTech,
                  value: '—'),
              data: (name) => _InfoRow(
                  icon: Icons.person_outline,
                  label: l10n.assignedTech,
                  value: name ?? '—'),
            );
          },
          data: (names) {
            if (names.isEmpty) {
              if (techNameAsync == null) {
                return const SizedBox.shrink();
              }

              return techNameAsync.when(
                loading: () => _InfoRow(
                    icon: Icons.person_outline,
                    label: l10n.assignedTech,
                    value: '...'),
                error: (_, __) => _InfoRow(
                    icon: Icons.person_outline,
                    label: l10n.assignedTech,
                    value: '—'),
                data: (name) => _InfoRow(
                    icon: Icons.person_outline,
                    label: l10n.assignedTech,
                    value: name ?? '—'),
              );
            }

            return _InfoRow(
              icon: Icons.people_outline,
              label: 'Assigned Techs',
              value: names.join(', '),
            );
          },
        ),

        // Scheduled date
        if (workOrder.scheduledDate != null)
          _InfoRow(
            icon: Icons.calendar_today,
            label: l10n.scheduledDate,
            value: dateFmt.format(workOrder.scheduledDate!),
          ),

        // Engine hours at start
        if (workOrder.hoursAtStart != null)
          _InfoRow(
            icon: Icons.speed,
            label: l10n.hoursAtStart,
            value: workOrder.hoursAtStart!.toStringAsFixed(1),
          ),

        // Engine hours at end
        if (workOrder.hoursAtEnd != null)
          _InfoRow(
            icon: Icons.speed,
            label: l10n.hoursAtEnd,
            value: workOrder.hoursAtEnd!.toStringAsFixed(1),
          ),

        // Labour hours
        if (workOrder.labourHours != null)
          _InfoRow(
            icon: Icons.access_time,
            label: l10n.labourHours,
            value: workOrder.labourHours!.toStringAsFixed(1),
          ),

        // Internal notes — owner/employee only
        if (isOwnerOrEmployee && workOrder.notesInternal != null) ...[
          const SizedBox(height: 12),
          Text(
            l10n.internalNotes.toUpperCase(),
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: AppColors.warning, letterSpacing: 1.2),
          ),
          const SizedBox(height: 4),
          Text(workOrder.notesInternal!, style: const TextStyle(fontSize: 13)),
        ],

        // On-hold reason — only when on_hold
        if (workOrder.status == WorkOrderStatus.onHold &&
            workOrder.onHoldReason != null) ...[
          const SizedBox(height: 12),
          _InfoRow(
            icon: Icons.pause_circle_outline,
            label: l10n.onHoldReason,
            value: workOrder.onHoldReason!,
            color: AppColors.warning,
          ),
        ],

        // Completed at
        if (workOrder.completedAt != null)
          _InfoRow(
            icon: Icons.check_circle,
            label: l10n.completedAt,
            value: dateFmt.format(workOrder.completedAt!.toLocal()),
            color: AppColors.success,
          ),

        // ── PM Parts Kit (read-only for tech) ──────────────────────────
        if (workOrder.checklistTemplateId != null)
          _PmKitSection(templateId: workOrder.checklistTemplateId!),

        const SizedBox(height: 24),

        // ── Actions ────────────────────────────────────────────────
        if (canManage) ...[
          Text(
            l10n.actions.toUpperCase(),
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: AppColors.primary, letterSpacing: 1.2),
          ),
          const SizedBox(height: 12),
          if (workOrder.status == WorkOrderStatus.draft ||
              workOrder.status == WorkOrderStatus.assigned)
            ElevatedButton.icon(
              onPressed: isLoading
                  ? null
                  : () async {
                      final success = await ref
                          .read(workOrderControllerProvider.notifier)
                          .updateStatus(
                            workOrder.id,
                            WorkOrderStatus.inProgress,
                          );
                      if (!success && context.mounted) {
                        _showWorkOrderActionFailed(context, ref);
                      }
                    },
              icon: const Icon(Icons.play_arrow),
              label: Text(l10n.startWorkOrder),
            ),
          if (workOrder.status == WorkOrderStatus.inProgress) ...[
            ElevatedButton.icon(
              onPressed: isLoading
                  ? null
                  : () async {
                      final success = await ref
                          .read(workOrderControllerProvider.notifier)
                          .updateStatus(workOrder.id, WorkOrderStatus.closed);
                      if (!context.mounted) return;
                      if (success) {
                        context.pop();
                      } else {
                        _showWorkOrderActionFailed(context, ref);
                      }
                    },
              icon: const Icon(Icons.check),
              label: Text(l10n.completeWorkOrder),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () =>
                  context.push('$prefix/checklists/${workOrder.id}'),
              icon: Icon(
                checklistDone ? Icons.check_circle : Icons.checklist,
                color: checklistDone ? AppColors.success : null,
              ),
              label: Text(
                checklistDone
                    ? '${l10n.viewChecklist} \u2022 ${l10n.statusCompleted}'
                    : l10n.viewChecklist,
              ),
              style: checklistDone
                  ? OutlinedButton.styleFrom(
                      foregroundColor: AppColors.success,
                      side: const BorderSide(color: AppColors.success),
                    )
                  : null,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => context.push('$prefix/service-reports'),
              icon: const Icon(Icons.description_outlined),
              label: Text(l10n.serviceReport),
            ),
            if (profile?.role == UserRole.employee) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: AppColors.surface,
                  shape: const RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  builder: (_) => _LogHoursSheet(workOrderId: workOrder.id),
                ),
                icon: const Icon(Icons.access_time),
                label: Text(l10n.logHours),
              ),
            ],
          ],
          // Reopen — both owner and tech can reopen a closed WO
          if (workOrder.status == WorkOrderStatus.closed) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: isLoading
                  ? null
                  : () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text(l10n.reopenWorkOrder),
                          content: const Text(
                              'Reopen this work order and continue working?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Cancel'),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: Text(l10n.reopenWorkOrder),
                            ),
                          ],
                        ),
                      );
                      if (confirm != true) return;
                      final success = await ref
                          .read(workOrderControllerProvider.notifier)
                          .reopenStatus(workOrder.id);
                      if (!context.mounted) return;
                      if (success) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Work order reopened'),
                            backgroundColor: AppColors.primary,
                          ),
                        );
                      } else {
                        _showWorkOrderActionFailed(context, ref);
                      }
                    },
              icon: const Icon(Icons.refresh),
              label: Text(l10n.reopenWorkOrder),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.warning,
                side: const BorderSide(color: AppColors.warning),
              ),
            ),
          ],
          // Generate Invoice — owner only, when WO is pending review or completed
          if (isOwner &&
              (workOrder.status == WorkOrderStatus.pendingReview ||
                  workOrder.status == WorkOrderStatus.inProgress ||
                  workOrder.status == WorkOrderStatus.closed)) ...[
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: isLoading
                  ? null
                  : () async {
                      final newId = await ref
                          .read(invoiceControllerProvider.notifier)
                          .generateFromWorkOrder(workOrder.id);
                      if (newId != null && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(l10n.invoiceGenerated),
                            backgroundColor: AppColors.success,
                          ),
                        );
                        context.push('$prefix/invoices/$newId');
                      }
                    },
              icon: const Icon(Icons.receipt_long),
              label: Text(l10n.generateInvoice),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E40AF),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

// ── Edit work order bottom sheet ─────────────────────────────────────────────

class _EditWorkOrderSheet extends ConsumerStatefulWidget {
  final WorkOrder workOrder;
  const _EditWorkOrderSheet({required this.workOrder});

  @override
  ConsumerState<_EditWorkOrderSheet> createState() =>
      _EditWorkOrderSheetState();
}

class _EditWorkOrderSheetState extends ConsumerState<_EditWorkOrderSheet> {
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
                final employeesAsync = ref.watch(employeesProvider);
                return employeesAsync.when(
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

// ── Log Hours bottom sheet (employee only) ──────────────────────────────────

class _LogHoursSheet extends ConsumerStatefulWidget {
  final String workOrderId;
  const _LogHoursSheet({required this.workOrderId});

  @override
  ConsumerState<_LogHoursSheet> createState() => _LogHoursSheetState();
}

class _LogHoursSheetState extends ConsumerState<_LogHoursSheet> {
  final _formKey = GlobalKey<FormState>();
  final _hoursWorkedCtrl = TextEditingController();
  final _engineHoursEndCtrl = TextEditingController();

  @override
  void dispose() {
    _hoursWorkedCtrl.dispose();
    _engineHoursEndCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final labourHours = double.tryParse(_hoursWorkedCtrl.text.trim());
    final engineHoursEnd = double.tryParse(_engineHoursEndCtrl.text.trim());

    final data = <String, dynamic>{
      if (labourHours != null) 'labour_hours': labourHours,
      if (engineHoursEnd != null) 'hours_at_end': engineHoursEnd,
    };

    if (data.isEmpty) return;

    final success = await ref
        .read(workOrderControllerProvider.notifier)
        .updateWorkOrder(widget.workOrderId, data);

    if (mounted) {
      if (success) {
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Changes could not be saved right now. Reconnect and try again.',
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isLoading = ref.watch(workOrderControllerProvider).isLoading;

    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.logHours, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            TextFormField(
              controller: _hoursWorkedCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: l10n.labourHours,
                hintText: '0.0',
                prefixIcon: const Icon(Icons.access_time),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? l10n.fieldRequired : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _engineHoursEndCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: l10n.hoursAtEnd,
                hintText: '0.0',
                prefixIcon: const Icon(Icons.speed),
              ),
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
    );
  }
}

// ── Shared info row widget ───────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? color;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color ?? AppColors.textSecondary),
          const SizedBox(width: 8),
          Text('$label: ',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13)),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    color: color ?? AppColors.textPrimary, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

// ── PM Kit Section (read-only) ─────────────────────────────────────────────

class _PmKitSection extends ConsumerWidget {
  final String templateId;
  const _PmKitSection({required this.templateId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partsAsync = ref.watch(pmPartsRequirementsProvider(templateId));

    return partsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (parts) {
        if (parts.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.inventory_2_outlined,
                      size: 16, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Text(
                    'PM PARTS KIT',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.primary,
                          letterSpacing: 1.2,
                        ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => PmPartsListSheet(
                        templateId: templateId,
                        templateName: 'Parts Required',
                      ),
                    ),
                    child: const Text('View all'),
                  ),
                ],
              ),
            ),
            ...parts.take(5).map((part) => Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: Row(
                    children: [
                      const Icon(Icons.circle,
                          size: 5, color: AppColors.textSecondary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          part.description,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      if (part.partNumber != null)
                        Text(
                          part.partNumber!,
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 11),
                        ),
                      const SizedBox(width: 8),
                      Text(
                        '${part.qty} ${part.unit ?? 'ea'}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 12),
                      ),
                    ],
                  ),
                )),
            if (parts.length > 5)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text(
                  '+${parts.length - 5} more — tap View all',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12),
                ),
              ),
          ],
        );
      },
    );
  }
}
