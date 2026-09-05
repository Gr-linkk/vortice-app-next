import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/fleet/fault_action_sheet.dart';
import 'package:vortice_app/features/fleet/fleet_policy.dart';
import 'package:vortice_app/features/fleet/fleet_providers.dart';
import 'package:vortice_app/features/fleet/fleet_widgets.dart';
import 'package:vortice_app/models/profile.dart';

class FaultDetailScreen extends ConsumerWidget {
  const FaultDetailScreen({super.key, required this.faultId});
  final String faultId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final es = fleetSpanish(context);
    final profile = ref.watch(profileProvider).valueOrNull;
    final result = ref.watch(fleetFaultProvider(faultId));
    return Scaffold(
      appBar: AppBar(
        title: Text(es ? 'Seguimiento de falla' : 'Fault tracking'),
        actions: [
          IconButton(
            tooltip: es ? 'Actualizar' : 'Refresh',
            onPressed: () => refreshFleet(ref, faultId: faultId),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: result.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => FleetError(
          error: error,
          onRetry: () => refreshFleet(ref, faultId: faultId),
        ),
        data: (fault) {
          if (fault == null) {
            return FleetEmpty(
              title: es ? 'Falla no disponible' : 'Fault unavailable',
              message: es
                  ? 'No existe o no pertenece a tu flota.'
                  : 'It does not exist or is outside your fleet.',
            );
          }
          final actions = availableFaultActions(
            fault: fault,
            role: profile?.role,
            userId: profile?.id,
          );
          return RefreshIndicator(
            onRefresh: () async {
              refreshFleet(ref, faultId: fault.id, assetId: fault.assetId);
              await ref.read(fleetFaultProvider(faultId).future);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: [
                InkWell(
                  onTap: () => context.push('/fleet/assets/${fault.assetId}'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.precision_manufacturing_outlined,
                          color: AppColors.primaryLight,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            fault.assetName,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(color: AppColors.primaryLight),
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right,
                          color: AppColors.primaryLight,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  fault.description,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FaultStatusBadge(status: fault.status),
                    if (fault.urgent)
                      FleetBadge(
                        label: es ? 'Urgente' : 'Urgent',
                        color: AppColors.error,
                        icon: Icons.priority_high,
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                _Info(
                  label: es ? 'Responsable' : 'Assigned to',
                  value:
                      fault.assigneeName ?? (es ? 'Sin asignar' : 'Unassigned'),
                ),
                _Info(
                  label: es ? 'Reportado por' : 'Reported by',
                  value: fault.reporterName ?? '—',
                ),
                _Info(
                  label: es ? 'Fecha del reporte' : 'Reported',
                  value: fleetDate(context, fault.createdAt),
                ),
                if (fault.workOrderId != null) ...[
                  const SizedBox(height: 12),
                  Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      leading: const Icon(
                        Icons.build_outlined,
                        color: AppColors.primaryLight,
                      ),
                      title: Text(
                        es
                            ? 'Orden de reparación vinculada'
                            : 'Linked repair work order',
                      ),
                      subtitle: Text(_jobLabel(fault.workOrderStatus, es)),
                      trailing:
                          profile?.role == UserRole.owner ||
                              profile?.role == UserRole.employee
                          ? const Icon(Icons.open_in_new)
                          : null,
                      onTap:
                          profile?.role == UserRole.owner ||
                              profile?.role == UserRole.employee
                          ? () => context.push(
                              '/${profile?.role == UserRole.owner ? 'owner' : 'employee'}/work-orders/${fault.workOrderId}',
                            )
                          : null,
                    ),
                  ),
                ],
                if (fault.resolutionNote != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    es ? 'Resultado de revisión' : 'Review outcome',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(fault.resolutionNote!),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () =>
                        context.push('/fleet/assets/${fault.assetId}'),
                    icon: const Icon(Icons.fact_check_outlined),
                    label: Text(
                      es
                          ? 'Revisar disponibilidad'
                          : 'Review asset availability',
                    ),
                  ),
                ],
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text(
                    es ? 'Siguiente paso' : 'Next step',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  ...actions.map(
                    (action) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _FaultActionButton(
                        primary: action == actions.first,
                        onPressed: () async {
                          await showModalBottomSheet<bool>(
                            context: context,
                            isScrollControlled: true,
                            isDismissible: false,
                            enableDrag: false,
                            useSafeArea: true,
                            builder: (_) =>
                                FaultActionSheet(fault: fault, action: action),
                          );
                          if (context.mounted) {
                            refreshFleet(
                              ref,
                              faultId: fault.id,
                              assetId: fault.assetId,
                            );
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            action.label(es),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Text(
                  es ? 'Historial' : 'Activity',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                ref
                    .watch(faultEventsProvider(faultId))
                    .when(
                      loading: () => const LinearProgressIndicator(),
                      error: (error, _) => FleetError(
                        error: error,
                        onRetry: () =>
                            ref.invalidate(faultEventsProvider(faultId)),
                      ),
                      data: (events) => Column(
                        children: [
                          if (events.isEmpty)
                            Text(
                              es
                                  ? 'No hay actividad registrada.'
                                  : 'No activity recorded.',
                            ),
                          ...events.map(
                            (event) => FleetEventTile(event: event),
                          ),
                        ],
                      ),
                    ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _FaultActionButton extends StatelessWidget {
  const _FaultActionButton({
    required this.primary,
    required this.onPressed,
    required this.child,
  });
  final bool primary;
  final VoidCallback onPressed;
  final Widget child;
  @override
  Widget build(BuildContext context) => primary
      ? FilledButton(onPressed: onPressed, child: child)
      : OutlinedButton(onPressed: onPressed, child: child);
}

String _jobLabel(String? status, bool es) => switch (status) {
  'draft' => es ? 'Borrador' : 'Draft',
  'assigned' => es ? 'Asignada' : 'Assigned',
  'in_progress' => es ? 'En curso' : 'In progress',
  'on_hold' => es ? 'En espera' : 'On hold',
  'pending_review' => es ? 'Pendiente de revisión' : 'Awaiting review',
  'invoiced' => es ? 'Facturada' : 'Invoiced',
  'closed' =>
    es
        ? 'Cerrada; verificar la falla por separado'
        : 'Closed; verify the fault separately',
  _ => es ? 'Estado no disponible' : 'Status unavailable',
};

class _Info extends StatelessWidget {
  const _Info({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 3),
        Text(value),
      ],
    ),
  );
}
