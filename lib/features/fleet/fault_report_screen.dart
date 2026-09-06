import 'package:vortice_app/core/unsaved_form_guard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/fleet/fleet_providers.dart';
import 'package:vortice_app/features/fleet/fleet_repository.dart';
import 'package:vortice_app/features/fleet/fleet_widgets.dart';

class FaultReportScreen extends ConsumerStatefulWidget {
  const FaultReportScreen({super.key, this.assetId});
  final String? assetId;
  @override
  ConsumerState<FaultReportScreen> createState() => _FaultReportScreenState();
}

class _FaultReportScreenState extends ConsumerState<FaultReportScreen> {
  final _form = GlobalKey<FormState>();
  final _description = TextEditingController();
  final _requestId = const Uuid().v4();
  String? _assetId;
  bool _urgent = false, _saving = false;
  Object? _error;
  @override
  void initState() {
    super.initState();
    _assetId = widget.assetId;
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final id = await ref
          .read(fleetRepositoryProvider)
          .report(
            requestId: _requestId,
            assetId: _assetId!,
            description: _description.text,
            urgent: _urgent,
          );
      if (!mounted) return;
      refreshFleet(ref);
      context.replace('/fleet/faults/$id');
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final es = fleetSpanish(context);
    final assets = ref.watch(fleetAssetsProvider);
    return UnsavedFormGuard(
      controllers: [_description],
      isDirty: () =>
          _description.text.isNotEmpty || _urgent || _assetId != widget.assetId,
      busy: _saving,
      fallbackRoute: '/fleet',
      child: Scaffold(
        appBar: AppBar(
          leading: const FormBackButton(fallbackRoute: '/fleet'),
          title: Text(es ? 'Reportar falla' : 'Report a fault'),
        ),
        body: SafeArea(
          child: assets.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => FleetError(
              error: error,
              onRetry: () => ref.invalidate(fleetAssetsProvider),
            ),
            data: (rows) {
              if (rows.isEmpty) {
                return FleetEmpty(
                  title: es ? 'No hay equipos asignados' : 'No assigned assets',
                  message: es
                      ? 'Pide a tu administrador que asigne tu flota.'
                      : 'Ask your administrator to assign your fleet.',
                );
              }
              final selected = rows.where((a) => a.id == _assetId).firstOrNull;
              return Form(
                key: _form,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      es ? '¿Qué necesita atención?' : 'What needs attention?',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      es
                          ? 'Tu equipo puede seguir la reparación desde este reporte.'
                          : 'Your team can follow the repair from this report.',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 24),
                    DropdownButtonFormField<String>(
                      initialValue: selected?.id,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: es ? 'Equipo' : 'Asset',
                      ),
                      items: rows
                          .map(
                            (a) => DropdownMenuItem(
                              value: a.id,
                              child: Text(
                                a.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: _saving
                          ? null
                          : (id) => setState(() => _assetId = id),
                      validator: (value) => value == null
                          ? (es ? 'Selecciona un equipo' : 'Select an asset')
                          : null,
                    ),
                    if (selected != null) ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OperatingStateBadge(state: selected.state),
                      ),
                    ],
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _description,
                      enabled: !_saving,
                      maxLines: 5,
                      maxLength: 4000,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        labelText: es
                            ? 'Describe la falla'
                            : 'Describe the fault',
                        hintText: es
                            ? 'Qué ocurre, dónde y desde cuándo'
                            : 'What is happening, where, and when it started',
                        alignLabelWithHint: true,
                      ),
                      validator: (value) => (value?.trim().length ?? 0) < 3
                          ? (es ? 'Añade una descripción' : 'Add a description')
                          : null,
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text(es ? 'Urgente' : 'Urgent'),
                      subtitle: Text(
                        es
                            ? 'Requiere atención inmediata del responsable.'
                            : 'Needs prompt attention from the responsible manager.',
                      ),
                      value: _urgent,
                      onChanged: _saving
                          ? null
                          : (value) => setState(() => _urgent = value),
                    ),
                    if (_urgent)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          es
                              ? 'La disponibilidad se evalúa por separado. Informa también al responsable si el equipo no debe usarse.'
                              : 'Availability is assessed separately. Also contact the responsible manager if the equipment should not be used.',
                          style: const TextStyle(color: AppColors.warning),
                        ),
                      ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          fleetErrorMessage(_error!, es),
                          style: const TextStyle(color: AppColors.warning),
                        ),
                      ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.flag_outlined),
                      label: Text(
                        _saving
                            ? (es ? 'Guardando…' : 'Saving…')
                            : (es ? 'Enviar reporte' : 'Submit report'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      es
                          ? 'Se requiere conexión para confirmar el reporte.'
                          : 'A connection is required to confirm the report.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
