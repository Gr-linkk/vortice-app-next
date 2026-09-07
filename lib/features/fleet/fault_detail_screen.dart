import 'package:flutter/material.dart';
import 'package:vortice_app/features/coordination/coordination_entry.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/fleet/fleet_providers.dart';
import 'package:vortice_app/features/fleet/fleet_widgets.dart';
import 'fault_next_step.dart';

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
                if (fault.resolutionNote != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    es ? 'Resultado de revisión' : 'Review outcome',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(fault.resolutionNote!),
                  const SizedBox(height: 12),
                ],
                const SizedBox(height: 24),
                FaultNextStep(fault: fault, profile: profile, es: es),
                CoordinationEntry(
                  compact: true,
                  assetId: fault.assetId,
                  kind: 'fault',
                  subjectId: fault.id,
                ),
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
