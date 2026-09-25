import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/features/maintenance/maintenance_models.dart';
import 'package:vortice_app/models/profile.dart';
import 'fault_action_sheet.dart';
import 'fleet_models.dart';
import 'fleet_policy.dart';
import 'fleet_providers.dart';
import 'fleet_widgets.dart';

/// One workflow entry, with uncommon fault decisions kept in a labelled menu.
class FaultNextStep extends ConsumerWidget {
  const FaultNextStep({
    super.key,
    required this.fault,
    required this.profile,
    required this.es,
    required this.french,
  });
  final FleetFault fault;
  final Profile? profile;
  final bool es;
  final bool french;

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
      label = fleetText(
        context,
        'Review asset availability',
        'Revisar disponibilidad',
        'Vérifier la disponibilité',
      );
      next = () => context.push('/fleet/assets/${fault.assetId}');
    } else if (review) {
      label = FaultAction.resolve.label(es, french: french);
      next = () => _act(context, ref, FaultAction.resolve);
    } else if (canOpen) {
      label = fleetText(
        context,
        'Open work order',
        'Abrir orden de trabajo',
        'Ouvrir le bon de travail',
      );
      next = openJob;
    } else if (canPlan) {
      label = fleetText(
        context,
        'Create work order',
        'Crear orden de trabajo',
        'Créer un bon de travail',
      );
      next = () async {
        await context.push(
          '/maintenance/new?faultId=${Uri.encodeComponent(fault.id)}',
        );
        if (context.mounted) {
          refreshFleet(ref, faultId: fault.id, assetId: fault.assetId);
        }
      };
    } else if (legacy != null) {
      label = legacy.label(es, french: french);
      next = () => _act(context, ref, legacy);
    } else {
      label = null;
      next = null;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          fleetText(context, 'Next step', 'Siguiente paso', 'Prochaine étape'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          availability
              ? fleetText(
                  context,
                  'Check whether the asset can return to service.',
                  'Revisa si el equipo puede volver a operar.',
                  'Vérifiez si l’équipement peut être remis en service.',
                )
              : review
              ? fleetText(
                  context,
                  'Confirm the repair fixed this fault. Review asset availability afterwards.',
                  'Confirma que la reparación resolvió esta falla. La disponibilidad se revisa después.',
                  'Confirmez que la réparation a corrigé cette défaillance. Vérifiez ensuite la disponibilité de l’équipement.',
                )
              : fault.workOrderId != null
              ? fleetText(
                  context,
                  'Linked work order: ${maintenanceStatus(fault.workOrderStatus ?? "", es, french: fleetFrench(context))}. Repair work is recorded there.',
                  'Orden vinculada: ${maintenanceStatus(fault.workOrderStatus ?? "", es, french: fleetFrench(context))}. La reparación se registra allí.',
                  'Bon de travail associé : ${maintenanceStatus(fault.workOrderStatus ?? "", es, french: fleetFrench(context))}. Les travaux de réparation y sont consignés.',
                )
              : canPlan
              ? fleetText(
                  context,
                  'Create or link a work order to assign and carry out the repair.',
                  'Crea una orden o vincula una existente para asignar y realizar la reparación.',
                  'Créez ou associez un bon de travail pour attribuer et effectuer la réparation.',
                )
              : fleetText(
                  context,
                  'The manager coordinates the repair and its review.',
                  'El responsable coordina la reparación y su revisión.',
                  'La personne responsable coordonne la réparation et sa révision.',
                ),
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
            child: Text(
              fleetText(
                context,
                'Open work order',
                'Abrir orden de trabajo',
                'Ouvrir le bon de travail',
              ),
            ),
          ),
        ],
        if (menu.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: PopupMenuButton<FaultAction>(
              tooltip: fleetText(
                context,
                'More actions',
                'Más acciones',
                'Plus d’actions',
              ),
              onSelected: (action) => _act(context, ref, action),
              itemBuilder: (_) => menu
                  .map(
                    (action) => PopupMenuItem(
                      value: action,
                      child: Text(action.label(es, french: french)),
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
                    Flexible(
                      child: Text(
                        fleetText(
                          context,
                          'More actions',
                          'Más acciones',
                          'Plus d’actions',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
