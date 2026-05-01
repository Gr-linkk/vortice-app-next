import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/hours/hour_log_provider.dart';
import 'package:vortice_app/models/hour_log.dart';
import 'package:intl/intl.dart';

class HourLogScreen extends ConsumerWidget {
  final String engineId;
  final String assetId;
  const HourLogScreen({
    super.key,
    required this.engineId,
    required this.assetId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final logsAsync = ref.watch(hourLogsForEngineProvider(engineId));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.hourLogsTitle)),
      body: logsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: AppColors.error, size: 48),
              const SizedBox(height: 12),
              Text(err.toString()),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () =>
                    ref.invalidate(hourLogsForEngineProvider(engineId)),
                child: Text(l10n.retry),
              ),
            ],
          ),
        ),
        data: (logs) {
          if (logs.isEmpty) {
            return Center(
              child: Text(l10n.noHourLogs,
                  style: const TextStyle(color: AppColors.textSecondary)),
            );
          }
          return RefreshIndicator(
            onRefresh: () async =>
                ref.invalidate(hourLogsForEngineProvider(engineId)),
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 80),
              itemCount: logs.length,
              itemBuilder: (_, i) => _HourLogTile(log: logs[i]),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showLogSheet(context, ref, l10n),
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showLogSheet(
      BuildContext context, WidgetRef ref, AppLocalizations l10n) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _HourLogForm(
        engineId: engineId,
        assetId: assetId,
      ),
    );
  }
}

class _HourLogTile extends StatelessWidget {
  final HourLog log;
  const _HourLogTile({required this.log});

  @override
  Widget build(BuildContext context) {
    final dateStr = log.createdAt != null
        ? DateFormat.yMMMd().add_jm().format(log.createdAt!.toLocal())
        : '—';

    return Card(
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.schedule, color: AppColors.primary, size: 22),
        ),
        title: Text(
          '${log.hours.toStringAsFixed(1)} hrs',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(dateStr,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 11)),
            if (log.source != null)
              Text('Source: ${log.source}',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 11)),
            if (log.notes != null && log.notes!.isNotEmpty)
              Text(log.notes!,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
          ],
        ),
        isThreeLine: true,
      ),
    );
  }
}

class _HourLogForm extends ConsumerStatefulWidget {
  final String engineId;
  final String assetId;

  const _HourLogForm({required this.engineId, required this.assetId});

  @override
  ConsumerState<_HourLogForm> createState() => _HourLogFormState();
}

class _HourLogFormState extends ConsumerState<_HourLogForm> {
  final _formKey = GlobalKey<FormState>();
  final _hoursCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  @override
  void dispose() {
    _hoursCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final success = await ref.read(hourLogControllerProvider.notifier).logHours(
          engineId: widget.engineId,
          assetId: widget.assetId,
          hours: double.parse(_hoursCtrl.text),
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        );
    if (success && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controllerState = ref.watch(hourLogControllerProvider);
    final isLoading = controllerState is AsyncLoading;

    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textSecondary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.logHours,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _hoursCtrl,
              decoration: InputDecoration(labelText: l10n.currentHours),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return l10n.fieldRequired;
                if (double.tryParse(v) == null) return l10n.invalidNumber;
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notesCtrl,
              decoration: InputDecoration(labelText: l10n.notes),
              maxLines: 3,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: isLoading ? null : _submit,
              child: isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.save),
            ),
          ],
        ),
      ),
    );
  }
}
