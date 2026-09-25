import 'package:vortice_app/features/checklists/checklist_snapshot_items.dart';
import 'package:vortice_app/models/profile.dart';
import 'package:vortice_app/models/work_order.dart';
import 'package:intl/intl.dart';

List<Map<String, dynamic>> maintenanceRows(dynamic value) =>
    (value as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

bool isMaintenanceManager(UserRole? role) =>
    role == UserRole.owner ||
    role == UserRole.client ||
    role == UserRole.clientAdmin;
bool canUseMaintenance(UserRole? role) =>
    isMaintenanceManager(role) ||
    role == UserRole.employee ||
    role == UserRole.clientMechanic;

String maintenanceLifecycle(
  String value, {
  bool? booked,
  bool returned = false,
}) {
  if (value == 'closed' || value == 'invoiced') return 'completed';
  if (value == 'pending_review') return value;
  if (returned) return 'returned';
  if ((value == 'draft' || value == 'assigned') && booked == true) {
    return 'scheduled';
  }
  if (value == 'assigned' && booked == false) return 'unscheduled';
  return value;
}

String maintenanceStatus(
  String value,
  bool es, {
  bool french = false,
  bool? booked,
  bool returned = false,
}) => switch (maintenanceLifecycle(value, booked: booked, returned: returned)) {
  'draft' =>
    french
        ? 'Non attribué'
        : es
        ? 'Sin asignar'
        : 'Unassigned',
  'assigned' =>
    french
        ? 'Attribué'
        : es
        ? 'Asignado'
        : 'Assigned',
  'scheduled' =>
    french
        ? 'Planifié'
        : es
        ? 'Programado'
        : 'Scheduled',
  'unscheduled' =>
    french
        ? 'Non planifié'
        : es
        ? 'Sin programar'
        : 'Unscheduled',
  'returned' =>
    french
        ? 'Retourné'
        : es
        ? 'Devuelto'
        : 'Returned',
  'in_progress' =>
    french
        ? 'En cours'
        : es
        ? 'En curso'
        : 'In progress',
  'on_hold' =>
    french
        ? 'Bloqué'
        : es
        ? 'Bloqueado'
        : 'Blocked',
  'pending_review' =>
    french
        ? 'En attente de révision'
        : es
        ? 'Pendiente de revisión'
        : 'Awaiting review',
  'completed' =>
    french
        ? 'Terminé'
        : es
        ? 'Completado'
        : 'Completed',
  _ => value,
};

String maintenancePriority(String value, bool es, {bool french = false}) =>
    switch (value) {
      'low' =>
        french
            ? 'Basse'
            : es
            ? 'Baja'
            : 'Low',
      'high' =>
        french
            ? 'Élevée'
            : es
            ? 'Alta'
            : 'High',
      'urgent' =>
        french
            ? 'Urgente'
            : es
            ? 'Urgente'
            : 'Urgent',
      _ => french ? 'Normale' : 'Normal',
    };
const _maintenanceEventsFr = <String, String>{
  'created': 'Bon de travail créé',
  'edit_details': 'Portée du travail mise à jour',
  'scope_previous': 'Portée précédente consignée',
  'schedule': 'Planification mise à jour',
  'schedule_previous': 'Ancienne planification consignée',
  'assign': 'Attribution mise à jour',
  'start': 'Travail commencé',
  'pause': 'Temps de travail suspendu',
  'block': 'Travail bloqué',
  'save_report': 'Brouillon enregistré',
  'submit': 'Soumis pour révision',
  'add_part': 'Pièce consignée',
  'remove_part': 'Pièce retirée',
  'approve': 'Travail approuvé',
  'return': 'Retourné pour correction',
  'reopen': 'Travail rouvert',
};
String maintenanceEvent(String value, bool es, {bool french = false}) {
  if (french) return _maintenanceEventsFr[value] ?? 'Travail mis à jour';
  return switch (value) {
    'created' => es ? 'Orden creada' : 'Work order created',
    'edit_details' => es ? 'Alcance actualizado' : 'Work order scope updated',
    'scope_previous' =>
      es ? 'Alcance anterior registrado' : 'Previous scope recorded',
    'schedule' => es ? 'Planificación actualizada' : 'Schedule updated',
    'schedule_previous' =>
      es ? 'Planificación anterior registrada' : 'Previous schedule recorded',
    'assign' => es ? 'Responsable actualizado' : 'Assignment updated',
    'start' => es ? 'Trabajo iniciado' : 'Labour started',
    'pause' => es ? 'Trabajo pausado' : 'Labour paused',
    'block' => es ? 'Trabajo bloqueado' : 'Work blocked',
    'save_report' => es ? 'Borrador guardado' : 'Draft saved',
    'submit' => es ? 'Enviado a revisión' : 'Submitted for review',
    'add_part' => es ? 'Repuesto registrado' : 'Part recorded',
    'remove_part' => es ? 'Repuesto retirado' : 'Part removed',
    'approve' => es ? 'Trabajo aprobado' : 'Work approved',
    'return' => es ? 'Devuelto para cambios' : 'Returned for changes',
    'reopen' => es ? 'Trabajo reabierto' : 'Job reopened',
    _ => es ? 'Trabajo actualizado' : 'Job updated',
  };
}

String maintenanceDate(String? value, bool es, {bool french = false}) {
  final date = DateTime.tryParse(value ?? '');
  if (date == null) return '—';
  final format = DateFormat.yMMMd(
    french
        ? 'fr_CA'
        : es
        ? 'es'
        : 'en',
  );
  if (value!.contains('T')) format.add_Hm();
  return format.format(date.toLocal());
}

class MaintenanceJob {
  MaintenanceJob(this.data);
  final Map<String, dynamic> data;
  String get id => data['id'] as String;
  String get costCurrency => data['cost_currency'] as String? ?? 'USD';
  String get assetId => data['asset_id'] as String;
  String get assetName => data['asset_name'] as String? ?? '';
  String get title => data['title'] as String? ?? '';
  String get status => data['status'] as String? ?? 'draft';
  bool get completed => status == 'closed' || status == 'invoiced';
  bool get returned =>
      !completed && status != 'pending_review' && data['returned_at'] != null;
  bool get hasBooking =>
      DateTime.tryParse(data['planned_start'] as String? ?? '') != null ||
      DateTime.tryParse(data['service_date'] as String? ?? '') != null;
  String get lifecycle =>
      maintenanceLifecycle(status, booked: hasBooking, returned: returned);
  String lifecycleLabel(bool es, {bool french = false}) =>
      maintenanceStatus(lifecycle, es, french: french);
  String get priority => data['priority'] as String? ?? 'normal';
  String? get dueDate => data['due_date'] as String?;
  int get revision => (data['revision'] as num?)?.toInt() ?? 0;
  bool get canManage => data['can_manage'] == true;
  bool get canWork => data['can_work'] == true;
  bool get canEdit =>
      canWork && (status == 'in_progress' || status == 'on_hold');
  bool get isService => data['service_interval_id'] != null;
  WorkOrderJobType get workType => WorkOrderJobType.fromValue(
    data['job_type'] as String? ?? (isService ? 'preventative' : 'repair'),
  );
  bool get canPrepare =>
      canManage &&
      canWork &&
      ['draft', 'assigned'].contains(status) &&
      data['started_at'] == null &&
      labour.isEmpty;
  String get expectedMaterials => data['expected_materials'] as String? ?? '';
  List<Map<String, dynamic>> get labour => maintenanceRows(data['labour']);
  List<Map<String, dynamic>> get parts => maintenanceRows(data['parts']);
  List<Map<String, dynamic>> get checklist => checklistSnapshotItems(
    data['checklist_snapshot'],
    data['checklist_template_id'] as String?,
  );
  Map<String, dynamic> get answers =>
      Map<String, dynamic>.from(data['checklist_answers'] as Map? ?? {});
  Map<String, dynamic> get report =>
      Map<String, dynamic>.from(data['report'] as Map? ?? {});
  List<String> get evidence =>
      (data['evidence_paths'] as List? ?? []).cast<String>();
  bool get hasRunningLabour =>
      labour.any((session) => session['stopped_at'] == null);
  double get completedLabourHours => labour.fold(0, (sum, session) {
    final start = DateTime.tryParse(session['started_at'] as String? ?? '');
    final stop = DateTime.tryParse(session['stopped_at'] as String? ?? '');
    return sum +
        (start == null || stop == null
            ? 0
            : stop.difference(start).inMicroseconds / 3600000000);
  });
  double get labourCost =>
      completedLabourHours * ((data['hourly_cost'] as num?)?.toDouble() ?? 0);
  double get partsCost => parts.fold(
    0,
    (sum, p) =>
        sum +
        (p['quantity'] as num).toDouble() * (p['unit_cost'] as num).toDouble(),
  );
}

String maintenanceApprovalDescription(
  MaintenanceJob job,
  bool es, {
  bool french = false,
}) {
  if (job.isService && job.data['service_applied_at'] != null) {
    return french
        ? 'Ferme ce travail rouvert. L’entretien déjà effectué et la prochaine échéance restent inchangés.'
        : es
        ? 'Cierra este trabajo reabierto. El servicio ya completado y las próximas horas de servicio no cambian.'
        : 'Closes this reopened job. Its previously completed service and next service due stay unchanged.';
  }
  if (job.isService &&
      (job.data['covered_plan_ids'] as List? ?? []).isNotEmpty) {
    final names = (job.data['covered_plan_names'] as List? ?? []).join(', ');
    return french
        ? 'Termine ce travail et le plan associé, notamment : $names.'
        : es
        ? 'Completa este trabajo y su plan, incluidos: $names.'
        : 'Completes this job and its plan, including: $names.';
  }
  if (job.isService) {
    return french
        ? 'Termine le travail et met à jour uniquement le plan d’entretien associé.'
        : es
        ? 'Completa el trabajo y actualiza únicamente su plan de servicio vinculado.'
        : 'Completes this job and updates only its linked service plan.';
  }
  return french
      ? 'Termine ce bon de travail. La disponibilité de l’équipement et la résolution des défaillances sont vérifiées séparément.'
      : es
      ? 'Completa esta orden de trabajo. La disponibilidad del equipo y la resolución de fallas se revisan por separado.'
      : 'Completes this work order. Asset availability and fault resolution are reviewed separately.';
}
