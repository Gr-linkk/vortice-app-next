import 'package:vortice_app/core/app_dropdown_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/unsaved_form_guard.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'maintenance_models.dart';
import 'maintenance_repository.dart';
import 'maintenance_refresh.dart';

class MaintenanceCreateScreen extends ConsumerStatefulWidget {
  const MaintenanceCreateScreen({
    super.key,
    this.assetId,
    this.planId,
    this.parentJobId,
  });
  final String? assetId, planId, parentJobId;
  @override
  ConsumerState<MaintenanceCreateScreen> createState() =>
      _MaintenanceCreateScreenState();
}

class _MaintenanceCreateScreenState
    extends ConsumerState<MaintenanceCreateScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController(),
      _instructions = TextEditingController(),
      _cost = TextEditingController(text: '0');
  String? _asset, _assignee, _plan, _component;
  String _priority = 'normal';
  DateTime? _due;
  MaintenanceWrite? _pending;
  Object? _error;
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    _asset = widget.assetId;
    _plan = widget.planId;
  }

  @override
  void dispose() {
    _title.dispose();
    _instructions.dispose();
    _cost.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate() || _asset == null) return;
    _pending ??= MaintenanceWrite({
      'asset_id': _asset,
      'title': _title.text.trim(),
      'description': _instructions.text.trim(),
      'assigned_to': _assignee,
      'priority': _priority,
      'service_interval_id': _plan,
      'engine_id': _component,
      'parent_job_id': widget.parentJobId,
      'hourly_cost': double.tryParse(_cost.text) ?? 0,
      'due_date': _due?.toIso8601String().split('T').first,
    });
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final id = await ref
          .read(maintenanceRepositoryProvider)
          .create(_pending!.id, _pending!.data);
      if (!mounted) return;
      refreshMaintenance(ref);
      context.go('/maintenance/jobs/$id');
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          if (maintenanceWriteWasRejected(error)) _pending = null;
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final es = isSpanish(context);
    if (!isMaintenanceManager(ref.watch(profileProvider).valueOrNull?.role)) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Text(
            es
                ? 'Acceso de responsable requerido.'
                : 'Manager access required.',
          ),
        ),
      );
    }
    final workspace = ref.watch(maintenanceWorkspaceProvider);
    final catalog = _asset == null
        ? null
        : ref.watch(maintenanceAssetProvider(_asset!));
    final data = catalog?.valueOrNull;
    final frozen = _saving || _pending != null;
    return UnsavedFormGuard(
      isDirty: () =>
          _title.text.isNotEmpty ||
          _instructions.text.isNotEmpty ||
          _pending != null,
      controllers: [_title, _instructions],
      busy: _saving,
      fallbackRoute: '/maintenance',
      child: Scaffold(
        appBar: AppBar(
          leading: const FormBackButton(fallbackRoute: '/maintenance'),
          title: Text(es ? 'Crear trabajo' : 'New maintenance job'),
        ),
        body: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              workspace.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => _retry(
                  e,
                  () => ref.invalidate(maintenanceWorkspaceProvider),
                ),
                data: (w) => AppDropdownField<String>(
                  initialValue: _asset,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: es ? 'Equipo' : 'Asset',
                  ),
                  items: maintenanceRows(w['assets'])
                      .map(
                        (a) => DropdownMenuItem(
                          value: a['id'] as String,
                          child: Text(a['name'] as String),
                        ),
                      )
                      .toList(),
                  onChanged: frozen || widget.parentJobId != null
                      ? null
                      : (v) => setState(() {
                          _asset = v;
                          _plan = null;
                          _assignee = null;
                          _component = null;
                        }),
                  validator: (v) => v == null
                      ? (es ? 'Selecciona un equipo' : 'Select an asset')
                      : null,
                ),
              ),
              const SizedBox(height: 16),
              if (catalog?.isLoading == true) const LinearProgressIndicator(),
              if (catalog?.hasError == true)
                _retry(
                  catalog!.error!,
                  () => ref.invalidate(maintenanceAssetProvider(_asset!)),
                ),
              if (data != null) ...[
                if (data['can_execute'] != true)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      es
                          ? 'El mantenimiento interno no está habilitado para esta empresa.'
                          : 'Internal maintenance is not enabled for this company.',
                    ),
                  ),
                TextFormField(
                  controller: _title,
                  enabled: !frozen,
                  maxLength: 200,
                  decoration: InputDecoration(
                    labelText: es ? 'Trabajo a realizar' : 'Work to do',
                  ),
                  validator: (v) => (v?.trim().length ?? 0) < 3
                      ? (es ? 'Describe el trabajo' : 'Describe the job')
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _instructions,
                  enabled: !frozen,
                  minLines: 3,
                  maxLines: 6,
                  decoration: InputDecoration(
                    labelText: es ? 'Instrucciones' : 'Instructions',
                  ),
                ),
                const SizedBox(height: 16),
                AppDropdownField<String>(
                  key: ValueKey('plan-$_asset'),
                  initialValue: _plan,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: es
                        ? 'Plan (opcional)'
                        : 'Service plan (optional)',
                  ),
                  items: [
                    DropdownMenuItem<String>(
                      value: '',
                      child: Text(
                        es ? 'Reparación sin plan' : 'Repair without a plan',
                      ),
                    ),
                    ...maintenanceRows(data['plans'])
                        .where(
                          (p) =>
                              p['engine_id'] != null && p['is_active'] == true,
                        )
                        .map(
                          (p) => DropdownMenuItem(
                            value: p['id'] as String,
                            child: Text(
                              '${p['interval_label'] ?? p['interval_hours']} · ${p['component_name']}',
                            ),
                          ),
                        ),
                  ],
                  onChanged: frozen || data['can_plan'] != true
                      ? null
                      : (v) => setState(() => _plan = v == '' ? null : v),
                ),
                const SizedBox(height: 16),
                if (_plan == null) ...[
                  AppDropdownField<String>(
                    key: ValueKey('component-$_asset'),
                    initialValue: _component,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: es ? 'Componente' : 'Component (optional)',
                    ),
                    items: maintenanceRows(data['components'])
                        .map(
                          (e) => DropdownMenuItem(
                            value: e['id'] as String,
                            child: Text(e['label'] as String),
                          ),
                        )
                        .toList(),
                    onChanged: frozen
                        ? null
                        : (v) => setState(() => _component = v),
                  ),
                  const SizedBox(height: 16),
                ],
                AppDropdownField<String>(
                  key: ValueKey('assignee-$_asset'),
                  initialValue: _assignee,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: es ? 'Responsable' : 'Assigned to',
                  ),
                  items: maintenanceRows(data['assignees'])
                      .map(
                        (p) => DropdownMenuItem(
                          value: p['id'] as String,
                          child: Text(p['name'] as String),
                        ),
                      )
                      .toList(),
                  onChanged: frozen
                      ? null
                      : (v) => setState(() => _assignee = v),
                ),
                const SizedBox(height: 16),
                AppDropdownField<String>(
                  initialValue: _priority,
                  decoration: InputDecoration(
                    labelText: es ? 'Prioridad' : 'Priority',
                  ),
                  items: [
                    for (final p in ['low', 'normal', 'high', 'urgent'])
                      DropdownMenuItem(
                        value: p,
                        child: Text(maintenancePriority(p, es)),
                      ),
                  ],
                  onChanged: frozen
                      ? null
                      : (v) => setState(() => _priority = v!),
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(es ? 'Fecha límite' : 'Due date'),
                  subtitle: Text(
                    _due?.toIso8601String().split('T').first ??
                        (es ? 'Sin fecha' : 'Not set'),
                  ),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: frozen
                      ? null
                      : () async {
                          final now = DateTime.now();
                          final date = await showDatePicker(
                            context: context,
                            initialDate: _due ?? now,
                            firstDate: DateTime(now.year - 1),
                            lastDate: DateTime(now.year + 10),
                          );
                          if (mounted && date != null) {
                            setState(() => _due = date);
                          }
                        },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _cost,
                  enabled: !frozen,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: es
                        ? 'Costo/hora (USD)'
                        : 'Internal hourly cost (USD)',
                  ),
                  validator: (v) =>
                      double.tryParse(v ?? '')?.isFinite != true ||
                          double.parse(v!) < 0
                      ? (es ? 'Ingresa un costo válido' : 'Enter a valid cost')
                      : null,
                ),
                const SizedBox(height: 12),
                Text(
                  es
                      ? 'Este trabajo no genera una factura.'
                      : 'This job does not generate an invoice.',
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(maintenanceError(_error!, es)),
                  ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed:
                      _saving ||
                          data['can_execute'] != true ||
                          (_plan != null && data['can_plan'] != true)
                      ? null
                      : _save,
                  child: Text(
                    _saving
                        ? (es ? 'Guardando…' : 'Saving…')
                        : _pending != null
                        ? (es ? 'Reintentar guardado' : 'Retry save')
                        : (es ? 'Crear trabajo' : 'Create job'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _retry(Object error, VoidCallback retry) => Column(
    children: [
      Text(maintenanceError(error, isSpanish(context))),
      TextButton(
        onPressed: retry,
        child: Text(isSpanish(context) ? 'Reintentar' : 'Try again'),
      ),
    ],
  );
}
