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
  String label(bool es, {bool french = false}) => switch (this) {
    acknowledge =>
      french
          ? 'Prendre en charge le signalement'
          : es
          ? 'Aceptar reporte'
          : 'Acknowledge',
    start =>
      french
          ? 'Commencer la réparation'
          : es
          ? 'Iniciar reparación'
          : 'Start repair',
    submit =>
      french
          ? 'Envoyer pour révision'
          : es
          ? 'Enviar a revisión'
          : 'Submit for review',
    resolve =>
      french
          ? 'Vérifier et résoudre'
          : es
          ? 'Verificar y resolver'
          : 'Verify & resolve',
    dismiss =>
      french
          ? 'Écarter avec motif'
          : es
          ? 'Descartar con motivo'
          : 'Dismiss with reason',
    reopen =>
      french
          ? 'Rouvrir le signalement'
          : es
          ? 'Reabrir falla'
          : 'Reopen fault',
    assign =>
      french
          ? 'Attribuer la réparation'
          : es
          ? 'Asignar responsable'
          : 'Assign repair',
    note =>
      french
          ? 'Ajouter une note de suivi'
          : es
          ? 'Añadir nota'
          : 'Add progress note',
    createWorkOrder =>
      french
          ? 'Créer un bon de travail'
          : es
          ? 'Crear orden de reparación'
          : 'Create repair work order',
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
