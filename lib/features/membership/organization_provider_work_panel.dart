import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:uuid/uuid.dart';
import 'package:vortice_app/core/account_storage.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/maintenance/maintenance_models.dart';
import 'package:vortice_app/features/parts/work_parts_progress.dart';
import 'organization_work_execution.dart';
import 'organization_work_report_editor.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/features/membership/organization_work_provider.dart';
import 'package:vortice_app/features/work_orders/work_order_provider.dart';
import 'package:vortice_app/sync/online_action_gate.dart';

/// The organization-aware controls inside the existing provider Work Order
/// detail route. Orders, reports, parts and invoices retain their shared IDs.
class OrganizationProviderWorkPanel extends ConsumerStatefulWidget {
  const OrganizationProviderWorkPanel({super.key, required this.workOrderId});
  final String workOrderId;
  @override
  ConsumerState<OrganizationProviderWorkPanel> createState() =>
      _OrganizationProviderWorkPanelState();
}

class _OrganizationProviderWorkPanelState
    extends ConsumerState<OrganizationProviderWorkPanel> {
  bool _busy = false, _ready = false;
  Map<String, dynamic>? _pending;
  late String _account;
  bool get _locked => _busy || !_ready || _pending != null;
  String get _pendingKey =>
      accountStorageKey(_account, 'provider_action:${widget.workOrderId}');
  @override
  void initState() {
    super.initState();
    _account = ref.read(sessionProvider)?.user.id ?? '';
    _restore();
  }

  Future<void> _restore() async {
    final raw = (await SharedPreferences.getInstance()).getString(_pendingKey);
    if (!mounted) return;
    if (raw != null) {
      try {
        _pending = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      } catch (_) {}
    }
    setState(() => _ready = true);
  }

  Future<void> _persist() async {
    if (ref.read(sessionProvider)?.user.id != _account) {
      throw const AccountChangedException();
    }
    final prefs = await SharedPreferences.getInstance();
    if (_pending == null) {
      await prefs.remove(_pendingKey);
    } else {
      await prefs.setString(_pendingKey, jsonEncode(_pending));
    }
  }

  String _t(String en, String es) => isSpanish(context) ? es : en;
  Future<void> _run(Future<void> Function() action) async {
    if (_busy || !await requireOnlineAction(context, ref) || !mounted) return;
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(organizationWorkOrderContextProvider(widget.workOrderId));
      ref.invalidate(workOrderByIdProvider(widget.workOrderId));
      ref.invalidate(workOrdersProvider);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(context, error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<Map<String, String>?> _fields(
    String title,
    List<(String, String, String, bool)> fields,
    String action,
  ) => showModalBottomSheet<Map<String, String>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) =>
        _ProviderWorkFieldsSheet(title: title, fields: fields, action: action),
  );

  Future<void> _action(
    Map<String, dynamic> data,
    String action, {
    Map<String, dynamic> values = const {},
  }) async {
    await _run(() async {
      _pending ??= {
        'id': const Uuid().v4(),
        'revision': data['revision'],
        'action': action,
        'data': jsonDecode(jsonEncode(values)),
      };
      await _persist();
      try {
        final pending = _pending!;
        await ref
            .read(organizationWorkRepositoryProvider)
            .changeOperation(
              widget.workOrderId,
              (pending['revision'] as num).toInt(),
              pending['id'] as String,
              pending['action'] as String,
              Map<String, dynamic>.from(pending['data'] as Map),
            );
        _pending = null;
        await _persist();
      } on PostgrestException {
        _pending = null;
        await _persist();
        rethrow;
      }
    });
  }

  Future<void> _prepare(Map<String, dynamic> data) async {
    final values = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => OrganizationWorkSetupSheet(data: data),
    );
    if (values != null && mounted) {
      await _action(data, 'configure', values: values);
    }
  }

  Future<void> _executionAction(
    Map<String, dynamic> data,
    String action,
  ) async {
    final order = data['work_order'] as Map;
    if ((action == 'start' || action == 'resume') &&
        order['started_at'] == null &&
        order['engine_id'] != null) {
      final unit = order['meter_unit']?.toString() ?? 'hours';
      final values = await _fields(_t('Start work', 'Iniciar trabajo'), [
        (
          'meter_value',
          _t('Starting meter ($unit)', 'Medidor inicial ($unit)'),
          data['current_meter']?.toString() ?? '',
          true,
        ),
      ], _t('Start work', 'Iniciar trabajo'));
      if (values != null && mounted) {
        await _action(data, action, values: {...values, 'meter_unit': unit});
      }
    } else if (action == 'block') {
      final values = await _fields(
        _t('Record a blocker', 'Registrar bloqueo'),
        [
          (
            'note',
            _t('What is blocking the work?', '¿Qué impide continuar?'),
            '',
            false,
          ),
        ],
        _t('Record blocker', 'Registrar bloqueo'),
      );
      if (values != null && mounted) {
        await _action(data, action, values: values);
      }
    } else {
      await _action(data, action);
    }
  }

  Future<void> _assign(Map<String, dynamic> data) async {
    final assignee = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (context) => ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              _t('Assign teammate', 'Asignar persona'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          for (final raw in data['people'] as List)
            ListTile(
              title: Text(raw['name'] as String),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pop(context, raw['id'] as String),
            ),
        ],
      ),
    );
    if (assignee != null) {
      await _action(data, 'assign', values: {'assigned_to': assignee});
    }
  }

  Future<void> _report(Map<String, dynamic> data) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => OrganizationWorkReportEditor(data: data),
      ),
    );
    if (saved == true && mounted) {
      ref.invalidate(organizationWorkOrderContextProvider(widget.workOrderId));
      ref.invalidate(workOrderByIdProvider(widget.workOrderId));
      ref.invalidate(workOrdersProvider);
    }
  }

  Future<void> _invoice() async {
    final values = await _fields(
      _t('Customer charges', 'Cargos al cliente'),
      [
        (
          'billable_rate',
          _t('Labour rate (USD/hour)', 'Tarifa de trabajo (USD/hora)'),
          '',
          true,
        ),
        (
          'parts_total',
          _t('Customer parts charge (USD)', 'Cargo de piezas al cliente (USD)'),
          '0',
          true,
        ),
        ('tax_percent', _t('Tax (%)', 'Impuesto (%)'), '0', true),
        ('exchange_rate', _t('MXN per USD', 'MXN por USD'), '1', true),
      ],
      _t('Generate invoice draft', 'Generar borrador de factura'),
    );
    if (values != null) {
      await _run(
        () => ref
            .read(organizationWorkRepositoryProvider)
            .invoice(widget.workOrderId, 'generate', values),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_t('Work order', 'Orden de trabajo'))),
    body: ref
        .watch(organizationWorkOrderContextProvider(widget.workOrderId))
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => AppErrorState(
            error: error,
            onRetry: () => ref.invalidate(
              organizationWorkOrderContextProvider(widget.workOrderId),
            ),
          ),
          data: (data) {
            final order = Map<String, dynamic>.from(data['work_order'] as Map);
            final status = order['status'] as String;
            final provider = data['is_provider'] == true;
            final manage = data['can_manage'] == true;
            final work = data['can_work'] == true;
            final bill = data['can_bill'] == true;
            final report = data['report'] as Map?;
            final invoice = data['invoice'] as Map?;
            final statusLabel = maintenanceStatus(
              status,
              isSpanish(context),
              booked:
                  DateTime.tryParse(
                    order['scheduled_date']?.toString() ?? '',
                  ) !=
                  null,
              returned: data['returned_at'] != null,
            );
            return RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(
                  organizationWorkOrderContextProvider(widget.workOrderId),
                );
              },
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    order['title'] as String,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text('${data['asset_name']} · $statusLabel'),
                  const SizedBox(height: 8),
                  Text(
                    _t(
                      'Provider: ${data['provider_name']}',
                      'Proveedor: ${data['provider_name']}',
                    ),
                  ),
                  Text(
                    _t(
                      'Customer: ${data['customer_name']}',
                      'Cliente: ${data['customer_name']}',
                    ),
                  ),
                  if ((order['description'] as String? ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(order['description'] as String),
                    ),
                  if (data['assignee_name'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _t(
                          'Assigned to ${data['assignee_name']}',
                          'Asignado a ${data['assignee_name']}',
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  if (manage &&
                      const {
                        'draft',
                        'assigned',
                        'in_progress',
                      }.contains(status))
                    OutlinedButton.icon(
                      onPressed: _locked ? null : () => _assign(data),
                      icon: const Icon(Icons.person_outline),
                      label: Text(_t('Assign teammate', 'Asignar persona')),
                    ),
                  if (provider) ...[
                    if (_pending != null)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                _t(
                                  'The last action is unconfirmed. Retry it before making another change.',
                                  'La última acción no se ha confirmado. Reinténtala antes de hacer otro cambio.',
                                ),
                              ),
                              FilledButton(
                                onPressed: _busy
                                    ? null
                                    : () => _action(
                                        data,
                                        _pending!['action'] as String,
                                      ),
                                child: Text(
                                  _t('Retry action', 'Reintentar acción'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    OrganizationWorkExecution(
                      data: data,
                      busy: _locked,
                      onAction: (action) => _executionAction(data, action),
                      onReport: () => _report(data),
                      onPrepare: () => _prepare(data),
                    ),
                    WorkPartsProgress(jobId: widget.workOrderId),
                    for (final source in maintenanceRows(data['sources']))
                      if (source['snapshot'] is Map)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            '${_t('Request', 'Solicitud')}: ${(source['snapshot'] as Map)['title']}\n${(source['snapshot'] as Map)['description'] ?? ''}',
                          ),
                        ),
                  ],
                  if (data['review_note'] != null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          _t(
                            'Review: ${data['review_note']}',
                            'Revisión: ${data['review_note']}',
                          ),
                        ),
                      ),
                    ),
                  if (work &&
                      const ['in_progress', 'on_hold'].contains(status)) ...[
                    OutlinedButton.icon(
                      onPressed: _locked
                          ? null
                          : () async {
                              final values = await _fields(
                                _t('Record a part', 'Registrar una pieza'),
                                [
                                  (
                                    'description',
                                    _t('Part description', 'Descripción'),
                                    '',
                                    false,
                                  ),
                                  (
                                    'quantity',
                                    _t('Quantity', 'Cantidad'),
                                    '1',
                                    true,
                                  ),
                                  (
                                    'unit_cost',
                                    _t(
                                      'Internal unit cost (USD)',
                                      'Costo unitario interno (USD)',
                                    ),
                                    '',
                                    true,
                                  ),
                                ],
                                _t('Record part', 'Registrar pieza'),
                              );
                              if (values != null) {
                                await _action(data, 'add_part', values: values);
                              }
                            },
                      icon: const Icon(Icons.inventory_2_outlined),
                      label: Text(_t('Record a part', 'Registrar una pieza')),
                    ),
                  ],
                  if (report != null) ...[
                    const Divider(height: 32),
                    Text(
                      provider && status != 'closed' && status != 'invoiced'
                          ? _t(
                              'Provider report draft',
                              'Borrador del proveedor',
                            )
                          : _t('Service report', 'Informe de servicio'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _t('Diagnosis', 'Diagnóstico'),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(report['diagnosis']?.toString() ?? ''),
                    const SizedBox(height: 12),
                    Text(
                      _t(
                        'Repair / work performed',
                        'Reparación / trabajo realizado',
                      ),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(report['repair']?.toString() ?? ''),
                    if ((report['notes']?.toString() ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(report['notes'].toString()),
                      ),
                  ],
                  if (!provider &&
                      report != null &&
                      report['evidence_paths'] is List)
                    OrganizationWorkEvidence(
                      paths: (report['evidence_paths'] as List).cast<String>(),
                    ),
                  if (!provider &&
                      report != null &&
                      report['checklist_snapshot'] is List)
                    for (final item in maintenanceRows(
                      report['checklist_snapshot'],
                    ))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          (isSpanish(context) ? item['description_es'] : null)
                                  ?.toString() ??
                              item['description_en']?.toString() ??
                              '',
                        ),
                        subtitle: Text(
                          '${(report['answers'] as Map?)?[item['id']]?['result'] ?? ''} · ${(report['answers'] as Map?)?[item['id']]?['note'] ?? ''}',
                        ),
                      ),
                  if (manage && status == 'pending_review') ...[
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _locked
                          ? null
                          : () => _action(data, 'approve'),
                      child: Text(
                        _t(
                          'Approve and share report',
                          'Aprobar y compartir informe',
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _locked
                          ? null
                          : () async {
                              final values = await _fields(
                                _t(
                                  'Return for changes',
                                  'Devolver para corregir',
                                ),
                                [
                                  (
                                    'note',
                                    _t(
                                      'What needs to change?',
                                      '¿Qué debe cambiar?',
                                    ),
                                    '',
                                    false,
                                  ),
                                ],
                                _t('Return report', 'Devolver informe'),
                              );
                              if (values != null) {
                                await _action(data, 'return', values: values);
                              }
                            },
                      child: Text(
                        _t('Return for changes', 'Devolver para corregir'),
                      ),
                    ),
                  ],
                  if (provider) ...[
                    const Divider(height: 32),
                    Text(
                      _t(
                        'Internal labour and parts',
                        'Trabajo y piezas internos',
                      ),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      _t(
                        '${((data['labour_hours'] as num?) ?? 0).toStringAsFixed(2)} labour hours',
                        '${((data['labour_hours'] as num?) ?? 0).toStringAsFixed(2)} horas de trabajo',
                      ),
                    ),
                    for (final part in data['parts'] as List? ?? const [])
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(part['description'] as String),
                        subtitle: Text(
                          '${part['quantity']} × ${part['unit_cost']} USD',
                        ),
                      ),
                  ],
                  if (bill && status == 'closed' && invoice == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 24),
                      child: FilledButton.icon(
                        onPressed: _locked ? null : _invoice,
                        icon: const Icon(Icons.receipt_long_outlined),
                        label: Text(_t('Generate invoice', 'Generar factura')),
                      ),
                    ),
                  if (invoice != null) ...[
                    const Divider(height: 32),
                    Text(
                      invoice['invoice_number'] as String,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      '${invoice['total_usd']} USD · ${invoice['total_mxn']} MXN',
                    ),
                    Text(
                      invoice['status'] == 'draft'
                          ? _t('Draft', 'Borrador')
                          : invoice['status'] == 'paid'
                          ? _t('Paid', 'Pagada')
                          : _t('Issued', 'Emitida'),
                    ),
                    if (bill && invoice['status'] == 'draft')
                      FilledButton(
                        onPressed: _locked
                            ? null
                            : () => _run(
                                () => ref
                                    .read(organizationWorkRepositoryProvider)
                                    .invoice(widget.workOrderId, 'sent', {}),
                              ),
                        child: Text(
                          _t(
                            'Issue invoice to customer',
                            'Emitir factura al cliente',
                          ),
                        ),
                      ),
                    if (bill && invoice['status'] == 'sent')
                      OutlinedButton(
                        onPressed: _locked
                            ? null
                            : () => _run(
                                () => ref
                                    .read(organizationWorkRepositoryProvider)
                                    .invoice(widget.workOrderId, 'paid', {}),
                              ),
                        child: Text(_t('Mark paid', 'Marcar como pagada')),
                      ),
                  ],
                ],
              ),
            );
          },
        ),
  );
}

// Text controllers belong to the mounted sheet, including its exit animation.
class _ProviderWorkFieldsSheet extends StatefulWidget {
  const _ProviderWorkFieldsSheet({
    required this.title,
    required this.fields,
    required this.action,
  });
  final String title, action;
  final List<(String, String, String, bool)> fields;
  @override
  State<_ProviderWorkFieldsSheet> createState() =>
      _ProviderWorkFieldsSheetState();
}

class _ProviderWorkFieldsSheetState extends State<_ProviderWorkFieldsSheet> {
  late final controllers = {
    for (final f in widget.fields) f.$1: TextEditingController(text: f.$3),
  };
  @override
  void dispose() {
    for (final controller in controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      24,
      24,
      24,
      MediaQuery.viewInsetsOf(context).bottom + 24,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
          const OnlineOnlyNotice(),
          const SizedBox(height: 20),
          for (final f in widget.fields)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: TextField(
                controller: controllers[f.$1],
                keyboardType: f.$4
                    ? const TextInputType.numberWithOptions(decimal: true)
                    : TextInputType.multiline,
                maxLines: f.$4 ? 1 : 3,
                decoration: InputDecoration(labelText: f.$2),
              ),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(context, {
              for (final entry in controllers.entries)
                entry.key: entry.value.text.trim(),
            }),
            child: Text(widget.action),
          ),
        ],
      ),
    ),
  );
}
