import 'dart:async';
import 'dart:convert';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vortice_app/core/account_storage.dart';
import 'package:vortice_app/features/operator/operator_checklist_support.dart';
import 'package:vortice_app/features/assets/asset_provider.dart';
import 'package:vortice_app/features/assets/client_team_asset_access.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/checklists/checklist_provider.dart';
import 'package:vortice_app/features/clients/client_capability_provider.dart';
import 'package:vortice_app/features/maintenance/maintenance_models.dart';
import 'package:vortice_app/features/maintenance/maintenance_repository.dart';
import 'package:vortice_app/features/orgs/org_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'field_work_provider.dart';
import 'field_work_queue.dart';
import 'evidence_recovery.dart';
import 'package:vortice_app/features/service_reports/service_report_screen.dart';
import 'package:vortice_app/features/service_requests/service_request_form_screen.dart';

String _operationTitle(FieldOperation row, bool es) {
  if (row.kind == 'request_submission') {
    return es ? 'Solicitud de servicio' : 'Service request';
  }
  if (row.kind == 'report_submission') {
    return es ? 'Informe y evidencias' : 'Report and evidence';
  }
  if (row.kind == 'upload') return es ? 'Foto' : 'Photo';
  return switch (row.payload['p_action']) {
    'start' => es ? 'Inicio del trabajo' : 'Work started',
    'pause' => es ? 'Pausa del trabajo' : 'Work paused',
    'block' => es ? 'Trabajo en espera' : 'Work put on hold',
    'save_report' => es ? 'Borrador del informe' : 'Report draft',
    'submit' => es ? 'Informe para revisión' : 'Report for review',
    'add_part' => es ? 'Pieza añadida' : 'Part added',
    'remove_part' => es ? 'Pieza retirada' : 'Part removed',
    _ => es ? 'Lista del operador' : 'Operator checklist',
  };
}

String _operationDetails(FieldOperation row, bool es) {
  final data = row.payload['p_data'] as Map? ?? {};
  final details = <String>[];
  if (row.error != null) {
    details.add(
      row.needsAttention
          ? (es
                ? 'Este cambio no se pudo guardar. Revisa los datos antes de reintentar.'
                : 'This change could not be saved. Review it before retrying.')
          : (es
                ? 'La carga se reintentará cuando haya conexión.'
                : 'Upload will retry when a connection is available.'),
    );
    if (row.error!.contains('changed') || row.error!.contains('40001')) {
      details.add(
        es
            ? 'El registro cambió. Abre la versión actual y corrige tu envío.'
            : 'This record changed. Open the current version and correct your submission.',
      );
    }
  }
  for (final field in [
    ('title', es ? 'Título' : 'Title'),
    ('complaint', es ? 'Problema' : 'Complaint'),
    ('cause', es ? 'Causa' : 'Cause'),
    ('correction', es ? 'Corrección' : 'Correction'),
    ('collateral', es ? 'Daño adicional' : 'Collateral'),
    ('comments', es ? 'Comentarios' : 'Comments'),
    ('diagnosis', es ? 'Diagnóstico' : 'Diagnosis'),
    ('repair', es ? 'Reparación y pruebas' : 'Repair and test results'),
    ('notes', es ? 'Notas' : 'Notes'),
    ('note', es ? 'Motivo' : 'Reason'),
    ('general_notes', es ? 'Notas generales' : 'General notes'),
    ('description', es ? 'Pieza' : 'Part'),
    ('quantity', es ? 'Cantidad' : 'Quantity'),
    ('completion_hours', es ? 'Horas del equipo' : 'Equipment hours'),
  ]) {
    final value = data[field.$1];
    if (value != null && value is! Map && value.toString().trim().isNotEmpty) {
      details.add('${field.$2}: $value');
    }
  }
  final responses = data['responses'] as Map?;
  if (responses != null) {
    details.add(
      es
          ? '${responses.length} respuestas guardadas'
          : '${responses.length} answers saved',
    );
    for (final note in (data['notes'] as Map? ?? {}).values) {
      if (note.toString().trim().isNotEmpty) details.add(note.toString());
    }
  }
  return details.join('\n\n');
}

/// Foreground retries and visible, account-scoped delivery state.
class FieldSyncStatus extends ConsumerStatefulWidget {
  const FieldSyncStatus({super.key});
  @override
  ConsumerState<FieldSyncStatus> createState() => _FieldSyncStatusState();
}

class _FieldSyncStatusState extends ConsumerState<FieldSyncStatus>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _active = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_active) _retry();
    });
    Future.microtask(_retry);
  }

  Future<void> _retry() async {
    if (!mounted) return;
    try {
      final queue = ref.read(fieldWorkQueueProvider);
      await queue?.flush();
      await queue?.cleanCompleted();
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (_active) _retry();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final es = isSpanish(context);
    final rows = ref.watch(fieldOperationsProvider).valueOrNull ?? [];
    if (rows.isEmpty) return const SizedBox.shrink();
    final waiting = rows
        .where((r) => !r.synced && r.status != 'cancelled')
        .length;
    final failed = rows.any((r) => r.needsAttention);
    return Material(
      color: failed
          ? Theme.of(context).colorScheme.errorContainer
          : Theme.of(context).colorScheme.surfaceContainerHighest,
      child: SafeArea(
        bottom: false,
        child: ListTile(
          dense: true,
          leading: Icon(
            failed
                ? Icons.error_outline
                : waiting > 0
                ? Icons.cloud_upload_outlined
                : Icons.cloud_done_outlined,
          ),
          title: Text(
            failed
                ? (es ? 'Necesita atención' : 'Needs attention')
                : waiting > 0
                ? (es
                      ? 'Guardado en este dispositivo · $waiting pendientes'
                      : 'Saved on this device · $waiting pending upload')
                : (es ? 'Sincronizado' : 'Synced'),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const FieldQueueScreen()),
          ),
        ),
      ),
    );
  }
}

class FieldQueueScreen extends ConsumerWidget {
  const FieldQueueScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final es = isSpanish(context);
    final rows = ref.watch(fieldOperationsProvider).valueOrNull ?? [];
    return Scaffold(
      appBar: AppBar(
        title: Text(es ? 'Guardado y sincronización' : 'Saved work and sync'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const OfflinePreparationButton(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              es
                  ? 'Sin conexión: consulta datos preparados durante un máximo de 24 horas y guarda informes, listas y evidencias. Facturas, asignaciones y cambios de empresa necesitan conexión. Los permisos se comprueban al reconectar. Los envíos confirmados se limpian después de 7 días; el trabajo pendiente o rechazado se conserva.'
                  : 'Offline: view prepared records for up to 24 hours and save reports, checklists and evidence. Invoices, assignments and company changes need a connection. Access is checked when you reconnect. Confirmed uploads are cleaned after 7 days; pending or rejected work stays on this device.',
            ),
          ),

          Text(
            es
                ? 'Los cambios pendientes se envían al abrir la app o mientras está en primer plano. Los errores conservan tus datos.'
                : 'Pending changes upload when you open the app or while it is in the foreground. Rejected changes keep your data.',
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () async {
              try {
                await ref
                    .read(fieldWorkQueueProvider)
                    ?.flush(retryFailed: true);
              } catch (_) {}
            },
            icon: const Icon(Icons.sync),
            label: Text(es ? 'Reintentar' : 'Retry uploads'),
          ),
          for (final row in rows.reversed)
            Card(
              child: ExpansionTile(
                title: Text(_operationTitle(row, es)),
                subtitle: Text(
                  row.synced
                      ? (es ? 'Sincronizado' : 'Synced')
                      : row.needsAttention
                      ? (es ? 'Necesita atención' : 'Needs attention')
                      : row.status == 'cancelled'
                      ? (es ? 'Archivado' : 'Archived')
                      : (es ? 'Pendiente' : 'Pending upload'),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        if (row.kind == 'upload')
                          Image.memory(
                            base64Decode(row.payload['bytes'] as String),
                            height: 200,
                            fit: BoxFit.contain,
                          ),
                        SelectableText(_operationDetails(row, es)),
                        for (final upload
                            in (row.payload['uploads'] as List? ?? const []))
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Image.memory(
                              base64Decode(upload['bytes'] as String),
                              height: 160,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => Text(
                                es
                                    ? 'Archivo guardado no visible'
                                    : 'Stored file cannot be previewed',
                              ),
                            ),
                          ),
                        if ([
                              'request_submission',
                              'report_submission',
                            ].contains(row.kind) &&
                            (row.needsAttention || row.status == 'cancelled'))
                          TextButton(
                            onPressed: () async {
                              final queue = ref.read(fieldWorkQueueProvider);
                              if (queue == null) return;
                              final key = await restoreSubmissionDraft(
                                queue,
                                row,
                              );
                              if (!context.mounted) return;
                              await Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      row.kind == 'request_submission'
                                      ? ServiceRequestFormScreen(
                                          draftStorageKey: key,
                                        )
                                      : ServiceReportScreen(
                                          initialWorkOrderId:
                                              row.payload['p_data']['work_order_id']
                                                  as String,
                                          draftStorageKey: key,
                                        ),
                                ),
                              );
                            },
                            child: Text(
                              es
                                  ? 'Corregir envío guardado'
                                  : 'Correct saved submission',
                            ),
                          ),
                        if (row.kind == 'apply_maintenance_field_action')
                          TextButton(
                            onPressed: () =>
                                context.go('/maintenance/jobs/${row.subject}'),
                            child: Text(es ? 'Abrir trabajo' : 'Open job'),
                          ),
                      ],
                    ),
                  ),
                  if (row.needsAttention &&
                      ![
                        'request_submission',
                        'report_submission',
                      ].contains(row.kind))
                    TextButton(
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text(
                              es
                                  ? '¿Apartar los cambios sin enviar?'
                                  : 'Set aside unsent changes?',
                            ),
                            content: Text(
                              es
                                  ? 'Todos los cambios sin enviar de este registro dejarán de reintentarse. El texto permanecerá aquí para copiarlo. Abre de nuevo el registro para guardar los cambios corregidos.'
                                  : 'All unsent changes for this record will stop retrying. Their text will stay here to copy. Reopen the record to save corrected changes.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: Text(es ? 'Cancelar' : 'Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: Text(es ? 'Apartar cambios' : 'Set aside'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true) {
                          final queue = ref.read(fieldWorkQueueProvider);
                          if (queue == null) return;
                          final related = (await queue.list())
                              .where((r) => r.subject == row.subject)
                              .toList();
                          final latestReport = related
                              .where(
                                (r) => [
                                  'save_report',
                                  'submit',
                                ].contains(r.payload['p_action']),
                              )
                              .lastOrNull;
                          final checklist = related
                              .where(
                                (r) => r.kind == 'submit_operations_checklist',
                              )
                              .lastOrNull;
                          final prefs = await SharedPreferences.getInstance();
                          if (latestReport != null) {
                            final data = latestReport.payload['p_data'] as Map;
                            await prefs.setString(
                              accountStorageKey(
                                queue.account,
                                'maintenance_report:${row.subject}',
                              ),
                              jsonEncode({
                                'diagnosis': data['diagnosis'],
                                'repair': data['repair'],
                                'notes': data['notes'],
                                'hours':
                                    data['completion_hours']?.toString() ?? '',
                                'answers': data['answers'],
                                'evidence': data['evidence_paths'],
                              }),
                            );
                          }
                          if (checklist != null) {
                            final data = checklist.payload['p_data'] as Map;
                            final photos = <String, String>{};
                            for (final entry
                                in (data['photos'] as Map).entries) {
                              final upload = related
                                  .where(
                                    (r) =>
                                        r.kind == 'upload' &&
                                        r.payload['path'] == entry.value,
                                  )
                                  .firstOrNull;
                              if (upload != null) {
                                photos[entry.key as String] =
                                    upload.payload['bytes'] as String;
                              }
                            }
                            await prefs.setString(
                              accountStorageKey(
                                queue.account,
                                operatorChecklistDraftKey,
                              ),
                              jsonEncode({
                                'assetId': data['asset_id'],
                                'templateId': data['template_id'],
                                'completedAt': data['completed_at'],
                                'responses': data['responses'],
                                'notes': data['notes'],
                                'currentHours': data['current_hours'],
                                'generalNotes': data['general_notes'],
                                'photos': photos,
                              }),
                            );
                          }
                          await queue.archiveSubject(row.subject);
                          if (context.mounted) {
                            context.go(
                              checklist != null
                                  ? '/operator/checklist'
                                  : '/maintenance/jobs/${row.subject}',
                            );
                          }
                        }
                      },
                      child: Text(
                        es ? 'Apartar cambios sin enviar' : 'Set aside unsent changes',
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class OfflinePreparationButton extends ConsumerStatefulWidget {
  const OfflinePreparationButton({super.key});
  @override
  ConsumerState<OfflinePreparationButton> createState() =>
      _OfflinePreparationButtonState();
}

class _OfflinePreparationButtonState
    extends ConsumerState<OfflinePreparationButton> {
  bool _busy = false;
  String? _message;
  Future<void> _prepare() async {
    final es = isSpanish(context);
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final profile = await ref.read(profileProvider.future);
      if (profile == null) throw StateError('Sign in first');
      await ref.read(currentUserOrgProvider.future);
      await ref.read(currentClientFleetAssetsProvider.future);
      final assets = await ref.read(assetsProvider.future);
      for (final client in assets.map((a) => a.clientId).toSet()) {
        await ref.read(clientCapabilitiesProvider(client).future);
      }
      final templates = await ref.read(checklistTemplatesProvider.future);
      for (final template in templates) {
        await ref.read(checklistItemsProvider(template.id).future);
      }
      if (canUseMaintenance(profile.role)) {
        final repository = ref.read(maintenanceRepositoryProvider);
        await repository.workspace();
        final jobs = await repository.jobs();
        for (final asset in jobs.map((j) => j.assetId).toSet()) {
          await repository.assetContext(asset);
        }
      }
      if (mounted) {
        setState(
          () => _message = es
              ? 'Trabajos y listas guardados para esta cuenta. Abre los registros que usarás antes de salir.'
              : 'Jobs and checklists saved for this account. Open the records you will use before leaving.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = es
              ? 'No se pudo preparar todo. Reintenta con conexión.'
              : 'Could not prepare everything. Retry with a connection.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          onPressed: _busy ? null : _prepare,
          icon: const Icon(Icons.download_for_offline_outlined),
          label: Text(
            isSpanish(context)
                ? 'Preparar trabajo sin conexión'
                : 'Prepare for offline work',
          ),
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_message != null) Text(_message!),
      ],
    ),
  );
}
