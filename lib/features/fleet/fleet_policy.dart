import 'package:vortice_app/features/fleet/fleet_models.dart';
import 'package:vortice_app/models/profile.dart';

enum FaultAction {
  acknowledge,
  start,
  submit,
  resolve,
  dismiss,
  reopen,
  assign,
  note,
  createWorkOrder;

  String get value => this == createWorkOrder ? 'create_work_order' : name;
  String label(bool es) => switch (this) {
    acknowledge => es ? 'Aceptar reporte' : 'Acknowledge',
    start => es ? 'Iniciar reparación' : 'Start repair',
    submit => es ? 'Enviar a revisión' : 'Submit for review',
    resolve => es ? 'Verificar y resolver' : 'Verify & resolve',
    dismiss => es ? 'Descartar con motivo' : 'Dismiss with reason',
    reopen => es ? 'Reabrir falla' : 'Reopen fault',
    assign => es ? 'Asignar responsable' : 'Assign repair',
    note => es ? 'Añadir nota' : 'Add progress note',
    createWorkOrder =>
      es ? 'Crear orden de reparación' : 'Create repair work order',
  };
}

bool canManageFleet(UserRole? role) =>
    role == UserRole.owner ||
    role == UserRole.client ||
    role == UserRole.clientAdmin;

/// UI affordances only. Fleet scope and every transition are enforced by RPCs.
List<FaultAction> availableFaultActions({
  required FleetFault fault,
  required UserRole? role,
  required String? userId,
}) {
  final manager = canManageFleet(role);
  final worker =
      manager ||
      (userId != null &&
          fault.assignedTo == userId &&
          (role == UserRole.clientMechanic || role == UserRole.employee));
  if (!manager && !worker) return const [];
  final status = fault.status;
  if (status == FaultStatus.unknown) return const [];
  if (!status.isActive) return manager ? [FaultAction.reopen] : const [];
  return [
    if (manager && status == FaultStatus.open) FaultAction.acknowledge,
    if (worker &&
        (status == FaultStatus.open || status == FaultStatus.acknowledged))
      FaultAction.start,
    if (worker && status == FaultStatus.inProgress) FaultAction.submit,
    if (manager && status == FaultStatus.pendingReview) FaultAction.resolve,
    if (manager && status == FaultStatus.pendingReview) FaultAction.reopen,
    if (worker) FaultAction.note,
    if (manager) FaultAction.assign,
    if (manager) FaultAction.dismiss,
    if (role == UserRole.owner && fault.workOrderId == null)
      FaultAction.createWorkOrder,
  ];
}
