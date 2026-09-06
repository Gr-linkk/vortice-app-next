import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/work_orders/work_order_provider.dart';
import 'package:vortice_app/features/work_orders/work_order_hours_validation.dart';
import 'package:vortice_app/l10n/app_localizations.dart';

class LogHoursSheet extends ConsumerStatefulWidget {
  final String workOrderId;
  const LogHoursSheet({super.key, required this.workOrderId});

  @override
  ConsumerState<LogHoursSheet> createState() => _LogHoursSheetState();
}

class _LogHoursSheetState extends ConsumerState<LogHoursSheet> {
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
        16,
        16,
        16,
        MediaQuery.of(context).viewInsets.bottom + 16,
      ),
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
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: l10n.labourHours,
                hintText: '0.0',
                prefixIcon: const Icon(Icons.access_time),
              ),
              validator: (v) => validateWorkOrderHours(v, l10n, required: true),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _engineHoursEndCtrl,
              validator: (v) => validateWorkOrderHours(v, l10n),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
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
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(l10n.save),
            ),
          ],
        ),
      ),
    );
  }
}
