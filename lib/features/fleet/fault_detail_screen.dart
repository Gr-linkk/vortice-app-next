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
        title: Text(
          fleetText(
            context,
            'Fault tracking',
            'Seguimiento de falla',
            'Suivi des défaillances',
          ),
        ),
        actions: [
          IconButton(
            tooltip: fleetText(context, 'Refresh', 'Actualizar', 'Actualiser'),
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
              title: fleetText(
                context,
                'Fault unavailable',
                'Falla no disponible',
                'Défaillance indisponible',
              ),
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
                        Icon(
                          Icons.precision_manufacturing_outlined,
                          color: context.appColors.primaryLight,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            fault.assetName,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: context.appColors.primaryLight,
                                ),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          color: context.appColors.primaryLight,
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
                        label: fleetText(
                          context,
                          'Urgent',
                          'Urgente',
                          'Urgent',
                        ),
                        color: context.appColors.error,
                        icon: Icons.priority_high,
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                _Info(
                  label: fleetText(
                    context,
                    'Assigned to',
                    'Responsable',
                    'Attribuée à',
                  ),
                  value:
                      fault.assigneeName ??
                      fleetText(
                        context,
                        'Unassigned',
                        'Sin asignar',
                        'Non attribuée',
                      ),
                ),
                _Info(
                  label: fleetText(
                    context,
                    'Reported by',
                    'Reportado por',
                    'Signalée par',
                  ),
                  value: fault.reporterName ?? '—',
                ),
                _Info(
                  label: fleetText(
                    context,
                    'Reported',
                    'Fecha del reporte',
                    'Date du signalement',
                  ),
                  value: fleetDate(context, fault.createdAt),
                ),
                if (fault.resolutionNote != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    fleetText(
                      context,
                      'Review outcome',
                      'Resultado de revisión',
                      'Résultat de la révision',
                    ),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(fault.resolutionNote!),
                  const SizedBox(height: 12),
                ],
                const SizedBox(height: 24),
                FaultNextStep(
                  fault: fault,
                  profile: profile,
                  es: es,
                  french: fleetFrench(context),
                ),
                CoordinationEntry(
                  compact: true,
                  assetId: fault.assetId,
                  kind: 'fault',
                  subjectId: fault.id,
                ),
                const SizedBox(height: 24),
                Text(
                  fleetText(context, 'Activity', 'Historial', 'Activité'),
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
          style: TextStyle(
            color: context.appColors.textSecondary,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 3),
        Text(value),
      ],
    ),
  );
}
