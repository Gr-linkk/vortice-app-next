import 'package:vortice_app/core/app_retry_panel.dart';
import 'package:vortice_app/core/meter_units.dart';
import 'package:vortice_app/features/engines/engine_provider.dart';
import 'package:vortice_app/core/user_feedback.dart';
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
      appBar: AppBar(
        title: Text(
          isSpanish(context) ? 'Historial de lecturas' : 'Meter history',
        ),
      ),
      body: logsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => AppRetryPanel(
          error: err,
          onRetry: () => ref.invalidate(hourLogsForEngineProvider(engineId)),
        ),
        data: (logs) {
          if (logs.isEmpty) {
            return Center(
              child: Text(
                isSpanish(context)
                    ? 'Todavía no hay lecturas'
                    : 'No readings yet',
                style: TextStyle(color: context.appColors.textSecondary),
              ),
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
        backgroundColor: context.appColors.primary,
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showLogSheet(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.appColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _HourLogForm(engineId: engineId, assetId: assetId),
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
            color: context.appColors.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.schedule,
            color: context.appColors.primary,
            size: 22,
          ),
        ),
        title: Text(
          formatMeter(log.hours, log.meterUnit),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              dateStr,
              style: TextStyle(
                color: context.appColors.textSecondary,
                fontSize: 11,
              ),
            ),
            if (log.source != null)
              Text(
                'Source: ${log.source}',
                style: TextStyle(
                  color: context.appColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            if (log.notes != null && log.notes!.isNotEmpty)
              Text(
                log.notes!,
                style: TextStyle(
                  color: context.appColors.textSecondary,
                  fontSize: 12,
                ),
              ),
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
    final engine = ref.read(engineByIdProvider(widget.engineId)).valueOrNull;
    if (engine == null) return;

    final success = await ref
        .read(hourLogControllerProvider.notifier)
        .logHours(
          engineId: widget.engineId,
          assetId: widget.assetId,
          hours: double.parse(_hoursCtrl.text),
          meterUnit: engine.meterUnit,
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        );
    if (!mounted) return;
    if (success) {
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyError(context, ref.read(hourLogControllerProvider).error),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controllerState = ref.watch(hourLogControllerProvider);
    final isLoading = controllerState is AsyncLoading;
    final engine = ref.watch(engineByIdProvider(widget.engineId));
    final unit = engine.valueOrNull?.meterUnit;

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
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.appColors.textSecondary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isSpanish(context) ? 'Registrar lectura' : 'Record meter reading',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _hoursCtrl,
              enabled: unit != null,
              decoration: InputDecoration(
                labelText: unit == null
                    ? (isSpanish(context)
                          ? 'Cargando unidad'
                          : 'Loading meter unit')
                    : '${isSpanish(context) ? 'Lectura' : 'Reading'} (${meterSymbol(unit)})',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return l10n.fieldRequired;
                final reading = double.tryParse(v);
                if (reading == null || !reading.isFinite || reading < 0) {
                  return l10n.invalidNumber;
                }
                if (reading < (engine.valueOrNull?.currentHours ?? 0)) {
                  return isSpanish(context)
                      ? 'La lectura no puede disminuir'
                      : 'Reading cannot decrease';
                }
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
              onPressed: isLoading || unit == null ? null : _submit,
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
