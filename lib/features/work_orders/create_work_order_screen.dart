import 'package:vortice_app/core/unsaved_form_guard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/assets/asset_provider.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/parts/pm_parts_provider.dart';
import 'package:vortice_app/features/service_intervals/maintenance_work_order_draft.dart';
import 'package:vortice_app/features/service_requests/service_request_provider.dart';
import 'package:vortice_app/features/work_orders/create_work_order_form.dart';
import 'package:vortice_app/features/work_orders/create_work_order_pm_parts_support.dart';
import 'package:vortice_app/features/work_orders/create_work_order_support.dart';
import 'package:vortice_app/features/work_orders/work_order_provider.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/models/work_order.dart';

class CreateWorkOrderScreen extends ConsumerStatefulWidget {
  final MaintenanceWorkOrderDraft? initialDraft;

  const CreateWorkOrderScreen({super.key, this.initialDraft});

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
    final engineHours = initialDraft?.engineHours;
    if (engineHours != null) {
      _hoursCtrl.text = engineHours.toString();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _prefillPartsFromTemplate(_selectedChecklistTemplateId);
    });
  }

  Future<void> _prefillPartsFromTemplate(String? templateId) async {
    if (templateId == null || !pmKitSelectionPrefillsWorkOrderPartsField()) {
      return;
    }

    try {
      final parts = await ref.read(
        pmPartsRequirementsProvider(templateId).future,
      );
      if (!mounted) return;
      setState(() {
        _partsCtrl.text = formatPmPartsForWorkOrderNotes(parts);
      });
    } catch (_) {
      // Parts preview still loads in the form when requirements are available.
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _hoursCtrl.dispose();
    _partsCtrl.dispose();
    super.dispose();
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

    final assets = ref.read(visibleAssetsProvider).valueOrNull ?? [];
    final selectedAsset = assets.firstWhere(
      (a) => a.id == _selectedAssetId,
      orElse: () => assets.first,
    );

    final data = buildCreateWorkOrderPayload(
      title: _titleCtrl.text,
      description: _descCtrl.text,
      jobType: _jobType,
      createdBy: profile.id,
      clientId: selectedAsset.clientId,
      assetId: _selectedAssetId!,
      assignedTechIds: _selectedTechIds,
      engineId: _selectedEngineId,
      checklistTemplateId: _selectedChecklistTemplateId,
      scheduledDate: _scheduledDate,
      hoursAtStart: parseHoursAtStart(_hoursCtrl.text),
      notesInternal: notesInternalFromParts(_partsCtrl.text),
    );

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
                            final name =
                                (employee['full_name'] as String?)
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

    return UnsavedFormGuard(
      controllers: [_titleCtrl, _descCtrl, _hoursCtrl, _partsCtrl],
      isDirty: () =>
          _titleCtrl.text.isNotEmpty ||
          _descCtrl.text.isNotEmpty ||
          _hoursCtrl.text.isNotEmpty ||
          _partsCtrl.text.isNotEmpty ||
          _selectedAssetId != null ||
          _scheduledDate != null ||
          _selectedTechIds.isNotEmpty ||
          _jobType != WorkOrderJobType.repair,
      busy: isLoading,
      fallbackRoute: '/more',
      child: Scaffold(
        appBar: AppBar(
          leading: const FormBackButton(fallbackRoute: '/more'),
          title: Text(l10n.createWorkOrder),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: CreateWorkOrderForm(
            formKey: _formKey,
            titleCtrl: _titleCtrl,
            descCtrl: _descCtrl,
            hoursCtrl: _hoursCtrl,
            partsCtrl: _partsCtrl,
            jobType: _jobType,
            selectedAssetId: _selectedAssetId,
            selectedEngineId: _selectedEngineId,
            selectedTechIds: _selectedTechIds,
            selectedChecklistTemplateId: _selectedChecklistTemplateId,
            scheduledDate: _scheduledDate,
            isLoading: isLoading,
            onJobTypeChanged: (v) => setState(() => _jobType = v),
            onAssetChanged: (v) => setState(() {
              _selectedAssetId = v;
              _selectedEngineId = null;
              _selectedChecklistTemplateId = null;
              _selectedTechIds = const [];
              _partsCtrl.clear();
            }),
            onEngineChanged: (v) => setState(() => _selectedEngineId = v),
            onChecklistTemplateChanged: (v) {
              setState(() => _selectedChecklistTemplateId = v);
              _prefillPartsFromTemplate(v);
            },
            onPickScheduledDate: _pickScheduledDate,
            onClearScheduledDate: () => setState(() => _scheduledDate = null),
            onPickTechnicians: _pickTechnicians,
            onSubmit: _submit,
          ),
        ),
      ),
    );
  }
}
