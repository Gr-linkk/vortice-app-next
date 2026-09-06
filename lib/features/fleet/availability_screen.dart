import 'package:vortice_app/core/app_dropdown_field.dart';
import 'package:flutter/material.dart';
import 'package:vortice_app/features/coordination/coordination_entry.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/fleet/fleet_models.dart';
import 'package:vortice_app/features/fleet/fleet_policy.dart';
import 'package:vortice_app/features/fleet/fleet_providers.dart';
import 'package:vortice_app/features/fleet/fleet_repository.dart';
import 'package:vortice_app/features/fleet/fleet_widgets.dart';

class AvailabilityScreen extends ConsumerWidget {
  const AvailabilityScreen({super.key, required this.assetId});
  final String assetId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final es = fleetSpanish(context);
    final manager = canManageFleet(
      ref.watch(profileProvider).valueOrNull?.role,
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(es ? 'Disponibilidad del equipo' : 'Asset availability'),
        actions: [
          IconButton(
            tooltip: es ? 'Actualizar' : 'Refresh',
            onPressed: () => refreshFleet(ref, assetId: assetId),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ref
          .watch(fleetAssetsProvider)
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => FleetError(
              error: error,
              onRetry: () => ref.invalidate(fleetAssetsProvider),
            ),
            data: (rows) {
              final asset = rows.where((a) => a.id == assetId).firstOrNull;
              if (asset == null) {
                return FleetEmpty(
                  title: es ? 'Equipo no disponible' : 'Asset unavailable',
                  message: es
                      ? 'No existe o no pertenece a tu flota.'
                      : 'It does not exist or is outside your fleet.',
                );
              }
              return RefreshIndicator(
                onRefresh: () async {
                  refreshFleet(ref, assetId: assetId);
                  await ref.read(fleetAssetsProvider.future);
                },
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      asset.name,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    CoordinationEntry(assetId: assetId),
                    if (asset.location != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        asset.location!,
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OperatingStateBadge(state: asset.state),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      asset.reason ??
                          (es
                              ? 'Un responsable aún no ha evaluado la disponibilidad.'
                              : 'A manager has not assessed availability yet.'),
                    ),
                    if (asset.changedAt != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        '${asset.changedByName ?? ''} · ${fleetDate(context, asset.changedAt)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              es
                                  ? 'Tiempo no disponible registrado'
                                  : 'Recorded downtime',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              asset.totalDowntime(DateTime.now()) ==
                                      Duration.zero
                                  ? '0 h'
                                  : downtimeLabel(
                                      asset.totalDowntime(DateTime.now()),
                                    ),
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              asset.unavailableSince == null
                                  ? (es
                                        ? 'Total desde el inicio del registro.'
                                        : 'Total since tracking began.')
                                  : (es
                                        ? 'Incluye la parada actual desde ${fleetDate(context, asset.unavailableSince)}.'
                                        : 'Includes the current outage since ${fleetDate(context, asset.unavailableSince)}.'),
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (asset.urgentFaults > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          es
                              ? '${asset.urgentFaults} fallas urgentes requieren revisión antes de marcar Disponible.'
                              : '${asset.urgentFaults} urgent faults need review before marking Available.',
                          style: const TextStyle(color: AppColors.warning),
                        ),
                      ),
                    const SizedBox(height: 20),
                    OutlinedButton.icon(
                      onPressed: () => context.push('/fleet?assetId=$assetId'),
                      icon: const Icon(Icons.flag_outlined),
                      label: Text(
                        es
                            ? 'Ver fallas (${asset.openFaults} activas)'
                            : 'View faults (${asset.openFaults} active)',
                      ),
                    ),
                    if (manager) ...[
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: () async {
                          await showModalBottomSheet<bool>(
                            context: context,
                            isScrollControlled: true,
                            isDismissible: false,
                            enableDrag: false,
                            useSafeArea: true,
                            builder: (_) => AvailabilityEditSheet(asset: asset),
                          );
                          if (context.mounted) {
                            refreshFleet(ref, assetId: assetId);
                          }
                        },
                        icon: const Icon(Icons.edit_outlined),
                        label: Text(
                          es
                              ? 'Actualizar disponibilidad'
                              : 'Update availability',
                        ),
                      ),
                    ],
                    const SizedBox(height: 28),
                    Text(
                      es
                          ? 'Historial de disponibilidad'
                          : 'Availability history',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    ref
                        .watch(availabilityEventsProvider(assetId))
                        .when(
                          loading: () => const LinearProgressIndicator(),
                          error: (error, _) => FleetError(
                            error: error,
                            onRetry: () => ref.invalidate(
                              availabilityEventsProvider(assetId),
                            ),
                          ),
                          data: (events) => Column(
                            children: [
                              if (events.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  child: Text(
                                    es
                                        ? 'Los cambios y sus motivos aparecerán aquí.'
                                        : 'Changes and their reasons will appear here.',
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                              ...events.map(
                                (event) => FleetEventTile(
                                  event: event,
                                  availability: true,
                                ),
                              ),
                            ],
                          ),
                        ),
                  ],
                ),
              );
            },
          ),
    );
  }
}

class AvailabilityEditSheet extends ConsumerStatefulWidget {
  const AvailabilityEditSheet({super.key, required this.asset});
  final FleetAsset asset;
  @override
  ConsumerState<AvailabilityEditSheet> createState() =>
      _AvailabilityEditSheetState();
}

class _AvailabilityEditSheetState extends ConsumerState<AvailabilityEditSheet> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController();
  final _operationId = const Uuid().v4();
  OperatingState? _state;
  bool _saving = false;
  Object? _error;
  @override
  void initState() {
    super.initState();
    _state = widget.asset.state == OperatingState.unknown
        ? null
        : widget.asset.state;
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(fleetRepositoryProvider)
          .changeAvailability(
            asset: widget.asset,
            operationId: _operationId,
            state: _state!,
            reason: _reason.text,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final es = fleetSpanish(context);
    final blocked =
        _state == OperatingState.available && widget.asset.urgentFaults > 0;
    return PopScope(
      canPop: !_saving,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            20 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    es ? 'Actualizar disponibilidad' : 'Update availability',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(widget.asset.name),
                  const SizedBox(height: 20),
                  AppDropdownField<OperatingState>(
                    initialValue: _state,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: es ? 'Estado' : 'State',
                    ),
                    items: OperatingState.values
                        .where((s) => s != OperatingState.unknown)
                        .map(
                          (s) => DropdownMenuItem(
                            value: s,
                            child: Text(s.label(es)),
                          ),
                        )
                        .toList(),
                    onChanged: _saving
                        ? null
                        : (state) => setState(() => _state = state),
                    validator: (value) => value == null
                        ? (es ? 'Selecciona un estado' : 'Choose a state')
                        : null,
                  ),
                  if (blocked)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        es
                            ? 'Resuelve o descarta las fallas urgentes primero.'
                            : 'Resolve or dismiss urgent faults first.',
                        style: const TextStyle(color: AppColors.warning),
                      ),
                    ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _reason,
                    enabled: !_saving,
                    maxLines: 3,
                    maxLength: 2000,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: es
                          ? 'Motivo / verificación'
                          : 'Reason / verification',
                      alignLabelWithHint: true,
                    ),
                    validator: (value) => (value?.trim().length ?? 0) < 3
                        ? (es ? 'Explica el cambio' : 'Explain this change')
                        : null,
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        fleetErrorMessage(_error!, es),
                        style: const TextStyle(color: AppColors.warning),
                      ),
                    ),
                  FilledButton(
                    onPressed: _saving || blocked ? null : _save,
                    child: Text(
                      _saving
                          ? (es ? 'Guardando…' : 'Saving…')
                          : (es ? 'Guardar estado' : 'Save state'),
                    ),
                  ),
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.pop(context, false),
                    child: Text(es ? 'Cancelar' : 'Cancel'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
