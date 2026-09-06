import 'package:vortice_app/models/profile.dart';
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

String maintenanceStatus(String value, bool es) => switch (value) {
  'draft' => es ? 'Sin asignar' : 'Unassigned',
  'assigned' => es ? 'Asignado' : 'Assigned',
  'in_progress' => es ? 'En curso' : 'In progress',
  'on_hold' => es ? 'Bloqueado' : 'Blocked',
  'pending_review' => es ? 'Pendiente de revisión' : 'Awaiting review',
  'closed' => es ? 'Completado' : 'Completed',
  _ => value,
};

String maintenancePriority(String value, bool es) => switch (value) {
  'low' => es ? 'Baja' : 'Low',
  'high' => es ? 'Alta' : 'High',
  'urgent' => es ? 'Urgente' : 'Urgent',
  _ => 'Normal',
};
String maintenanceEvent(String value, bool es) => switch (value) {
  'created' => es ? 'Trabajo creado' : 'Job created',
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
String maintenanceDate(String? value, bool es) {
  final date = DateTime.tryParse(value ?? '');
  if (date == null) return '—';
  final format = DateFormat.yMMMd(es ? 'es' : 'en');
  if (value!.contains('T')) format.add_Hm();
  return format.format(date.toLocal());
}

class MaintenanceJob {
  MaintenanceJob(this.data);
  final Map<String, dynamic> data;
  String get id => data['id'] as String;
  String get assetId => data['asset_id'] as String;
  String get assetName => data['asset_name'] as String? ?? '';
  String get title => data['title'] as String? ?? '';
  String get status => data['status'] as String? ?? 'draft';
  String get priority => data['priority'] as String? ?? 'normal';
  String? get dueDate => data['due_date'] as String?;
  int get revision => (data['revision'] as num?)?.toInt() ?? 0;
  bool get canManage => data['can_manage'] == true;
  bool get canWork => data['can_work'] == true;
  bool get canEdit =>
      canWork && (status == 'in_progress' || status == 'on_hold');
  bool get isService => data['service_interval_id'] != null;
  List<Map<String, dynamic>> get labour => maintenanceRows(data['labour']);
  List<Map<String, dynamic>> get parts => maintenanceRows(data['parts']);
  List<Map<String, dynamic>> get checklist =>
      maintenanceRows(data['checklist_snapshot']);
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

String maintenanceApprovalDescription(MaintenanceJob job, bool es) {
  if (job.isService && job.data['service_applied_at'] != null) {
    return es
        ? 'Cierra este trabajo reabierto. El servicio ya completado y las próximas horas de servicio no cambian.'
        : 'Closes this reopened job. Its previously completed service and next service due stay unchanged.';
  }
  if (job.isService) {
    return es
        ? 'Completa el trabajo y actualiza únicamente su plan de servicio vinculado.'
        : 'Completes this job and updates only its linked service plan.';
  }
  return es
      ? 'Completa esta reparación. La disponibilidad del equipo y la resolución de fallas se revisan por separado.'
      : 'Completes this repair. Asset availability and fault resolution are reviewed separately.';
}
