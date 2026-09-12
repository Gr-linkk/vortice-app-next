import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/features/maintenance/maintenance_models.dart';
import 'package:vortice_app/models/profile.dart';
import 'fault_action_sheet.dart';
import 'fleet_models.dart';
import 'fleet_policy.dart';
import 'fleet_providers.dart';

/// One workflow entry, with uncommon fault decisions kept in a labelled menu.
class FaultNextStep extends ConsumerWidget {
  const FaultNextStep({
    super.key,
    required this.fault,
    required this.profile,
    required this.es,
  });
  final FleetFault fault;
  final Profile? profile;
  final bool es;

  Future<void> _act(
    BuildContext context,
    WidgetRef ref,
    FaultAction action,
  ) async {
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      useSafeArea: true,
      builder: (_) => FaultActionSheet(fault: fault, action: action),
    );
    if (context.mounted) {
      refreshFleet(ref, faultId: fault.id, assetId: fault.assetId);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manager = canManageFleet(profile?.role);
    final canOpen =
        fault.workOrderId != null &&
        (fault.canOpenWorkOrder ||
            (!fault.workOrderManaged &&
                [UserRole.owner, UserRole.employee].contains(profile?.role)));
    final canPlan =
        manager &&
        fault.canPlanRepair &&
        fault.workOrderId == null &&
        fault.status.isActive &&
        fault.status != FaultStatus.unknown;
    final actions =
        availableFaultActions(
              fault: fault,
              role: profile?.role,
              userId: profile?.id,
            )
            .where(
              (action) =>
                  !(fault.workOrderManaged &&
                      [
                        FaultAction.start,
                        FaultAction.submit,
                        FaultAction.assign,
                        FaultAction.createWorkOrder,
                      ].contains(action)),
            )
            .where(
              (action) =>
                  !(fault.workOrderManaged &&
                      action == FaultAction.reopen &&
                      fault.status == FaultStatus.pendingReview),
            )
            .where(
              (action) =>
                  !(fault.workOrderManaged &&
                      action == FaultAction.resolve &&
                      fault.workOrderStatus != 'closed'),
            )
            .where(
              (action) =>
                  !(canPlan &&
                      [
                        FaultAction.start,
                        FaultAction.assign,
                        FaultAction.createWorkOrder,
                      ].contains(action)),
            )
            .toList();
    final review = actions.contains(FaultAction.resolve);
    final availability =
        manager &&
        [FaultStatus.resolved, FaultStatus.dismissed].contains(fault.status);
    final legacy = !review && !canOpen && !canPlan && !availability
        ? actions
              .where(
                (a) => [
                  FaultAction.acknowledge,
                  FaultAction.start,
                  FaultAction.submit,
                  FaultAction.reopen,
                ].contains(a),
              )
              .firstOrNull
        : null;
    final menu = actions
        .where((a) => a != legacy && !(review && a == FaultAction.resolve))
        .toList();

    Future<void> openJob() async {
      final route = fault.workOrderManaged
          ? '/maintenance/jobs/${fault.workOrderId}'
          : '/${profile?.role == UserRole.owner ? 'owner' : 'employee'}/work-orders/${fault.workOrderId}';
      await context.push(route);
      if (context.mounted) {
        refreshFleet(ref, faultId: fault.id, assetId: fault.assetId);
      }
    }

    final String? label;
    final VoidCallback? next;
    if (availability) {
      label = es ? 'Revisar disponibilidad' : 'Review asset availability';
      next = () => context.push('/fleet/assets/${fault.assetId}');
    } else if (review) {
      label = FaultAction.resolve.label(es);
      next = () => _act(context, ref, FaultAction.resolve);
    } else if (canOpen) {
      label = es ? 'Abrir orden de trabajo' : 'Open work order';
      next = openJob;
    } else if (canPlan) {
      label = es ? 'Crear orden de trabajo' : 'Create work order';
      next = () async {
        await context.push(
          '/maintenance/new?faultId=${Uri.encodeComponent(fault.id)}',
        );
        if (context.mounted) {
          refreshFleet(ref, faultId: fault.id, assetId: fault.assetId);
        }
      };
    } else if (legacy != null) {
      label = legacy.label(es);
      next = () => _act(context, ref, legacy);
    } else {
      label = null;
      next = null;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          es ? 'Siguiente paso' : 'Next step',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          availability
              ? (es
                    ? 'Revisa si el equipo puede volver a operar.'
                    : 'Check whether the asset can return to service.')
              : review
              ? (es
                    ? 'Confirma que la reparación resolvió esta falla. La disponibilidad se revisa después.'
                    : 'Confirm the repair fixed this fault. Review asset availability afterwards.')
              : fault.workOrderId != null
              ? (es
                    ? 'Orden vinculada: ${maintenanceStatus(fault.workOrderStatus ?? "", es)}. La reparación se registra allí.'
                    : 'Linked work order: ${maintenanceStatus(fault.workOrderStatus ?? "", es)}. Repair work is recorded there.')
              : canPlan
              ? (es
                    ? 'Crea una orden o vincula una existente para asignar y realizar la reparación.'
                    : 'Create or link a work order to assign and carry out the repair.')
              : (es
                    ? 'El responsable coordina la reparación y su revisión.'
                    : 'The manager coordinates the repair and its review.'),
        ),
        if (label != null) ...[
          const SizedBox(height: 12),
          FilledButton(
            onPressed: next,
            child: Text(label, textAlign: TextAlign.center),
          ),
        ],
        if (canOpen && (review || availability)) ...[
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: openJob,
            child: Text(es ? 'Abrir orden de trabajo' : 'Open work order'),
          ),
        ],
        if (menu.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: PopupMenuButton<FaultAction>(
              tooltip: es ? 'Más acciones' : 'More actions',
              onSelected: (action) => _act(context, ref, action),
              itemBuilder: (_) => menu
                  .map(
                    (action) => PopupMenuItem(
                      value: action,
                      child: Text(action.label(es)),
                    ),
                  )
                  .toList(),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.more_horiz),
                    const SizedBox(width: 8),
                    Flexible(child: Text(es ? 'Más acciones' : 'More actions')),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
