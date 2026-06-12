import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/service_intervals/service_interval_provider.dart';
import 'package:vortice_app/models/checklist_template.dart';

class ServiceIntervalAddSheet extends ConsumerStatefulWidget {
  final String assetId;
  final List<ChecklistTemplate> templates;

  const ServiceIntervalAddSheet({
    super.key,
    required this.assetId,
    required this.templates,
  });

  @override
  ConsumerState<ServiceIntervalAddSheet> createState() =>
      _ServiceIntervalAddSheetState();
}

class _ServiceIntervalAddSheetState
    extends ConsumerState<ServiceIntervalAddSheet> {
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
                    labelText: 'Due Hours (optional)',
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
