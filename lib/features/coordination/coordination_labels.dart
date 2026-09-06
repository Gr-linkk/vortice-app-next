import 'package:intl/intl.dart';

const historyCategories = {
  'asset': ('Asset & location', 'Activo y ubicación'),
  'usage': ('Meter readings', 'Lecturas de horas'),
  'inspection': ('Inspections', 'Inspecciones'),
  'fault': ('Faults', 'Fallas'),
  'availability': ('Availability', 'Disponibilidad'),
  'work': ('Work', 'Trabajo'),
  'service': ('Service reports', 'Informes de servicio'),
  'parts': ('Parts & internal costs', 'Piezas y costos internos'),
  'discussion': ('Discussion & handover', 'Conversación y relevo'),
};
const attentionCategories = {
  'unavailable': ('Unavailable assets', 'Activos no disponibles'),
  'urgent_faults': ('Urgent faults', 'Fallas urgentes'),
  'overdue_service': ('Service overdue', 'Servicio vencido'),
  'overdue_work': ('Work overdue', 'Trabajo vencido'),
  'review': ('Awaiting review', 'Pendiente de revisión'),
  'waiting_parts': ('Waiting for parts', 'Esperando piezas'),
  'waiting_people': ('Waiting for people', 'Esperando personal'),
  'blocked_other': ('Other blocked work', 'Otros trabajos bloqueados'),
  'approaching_service': ('Service within 50 h', 'Servicio dentro de 50 h'),
  'upcoming_work': ('Work due within 7 days', 'Trabajo dentro de 7 días'),
  'plan_setup': ('Plan setup needed', 'Configurar mantenimiento'),
  'unassessed': ('Availability unknown', 'Disponibilidad desconocida'),
};
const blockedCategories = {
  'parts': ('Parts', 'Piezas'),
  'people': ('People', 'Personal'),
  'external': ('External dependency', 'Dependencia externa'),
  'other': ('Other', 'Otro'),
};
const isolationStates = {
  'unknown': ('Not confirmed', 'Sin confirmar'),
  'isolated': ('Isolated', 'Aislado'),
  'not_isolated': ('Not isolated', 'Sin aislar'),
  'not_required': ('Isolation not required', 'No requiere aislamiento'),
};
const historyKinds = {
  'asset_recorded': ('Asset recorded', 'Activo registrado'),
  'asset_changed': ('Asset details changed', 'Datos del activo cambiados'),
  'component_recorded': ('Component recorded', 'Componente registrado'),
  'component_changed': (
    'Component details changed',
    'Datos del componente cambiados',
  ),
  'meter_updated': ('Meter updated', 'Medidor actualizado'),
  'plan_recorded': ('Service plan recorded', 'Plan de servicio registrado'),
  'plan_changed': ('Service plan changed', 'Plan de servicio cambiado'),
  'plan_removed': ('Service plan removed', 'Plan de servicio eliminado'),
  'hours_logged': ('Hours logged', 'Horas registradas'),
  'reading_removed': ('Reading removed', 'Lectura eliminada'),
  'reading_corrected': ('Reading corrected', 'Lectura corregida'),
  'job_recorded': ('Job recorded', 'Trabajo registrado'),
  'job_changed': ('Job changed', 'Trabajo cambiado'),
  'job_removed': ('Job removed', 'Trabajo eliminado'),
  'maintenance_created': ('Job created', 'Trabajo creado'),
  'maintenance_assign': ('Work assigned', 'Trabajo asignado'),
  'maintenance_start': (
    'Work started / resumed',
    'Trabajo iniciado / reanudado',
  ),
  'maintenance_pause': ('Labour paused', 'Tiempo de trabajo pausado'),
  'maintenance_block': ('Work blocked', 'Trabajo bloqueado'),
  'maintenance_add_part': ('Part added', 'Pieza añadida'),
  'maintenance_save_report': ('Report draft saved', 'Borrador guardado'),
  'maintenance_submit': (
    'Report submitted for review',
    'Informe enviado para revisión',
  ),
  'maintenance_return': (
    'Work returned for correction',
    'Trabajo devuelto para corrección',
  ),
  'maintenance_reopen': ('Work reopened', 'Trabajo reabierto'),
  'maintenance_approve': (
    'Work approved and closed',
    'Trabajo aprobado y cerrado',
  ),
  'part_recorded': ('Part recorded', 'Pieza registrada'),
  'part_removed': ('Part removed', 'Pieza eliminada'),
  'part_changed': ('Part changed', 'Pieza cambiada'),
  'report_recorded': (
    'Service report recorded',
    'Informe de servicio registrado',
  ),
  'report_changed': ('Service report changed', 'Informe de servicio cambiado'),
  'report_removed': ('Service report removed', 'Informe de servicio eliminado'),
  'inspection_submitted': ('Inspection submitted', 'Inspección enviada'),
  'inspection_changed': ('Inspection changed', 'Inspección cambiada'),
  'inspection_removed': ('Inspection removed', 'Inspección eliminada'),
  'operator_run_recorded': (
    'Operator inspection recorded',
    'Inspección del operador registrada',
  ),
  'availability_changed': ('Availability changed', 'Disponibilidad cambiada'),
  'fault_reported': ('Fault reported', 'Falla reportada'),
  'fault_acknowledge': ('Fault acknowledged', 'Falla reconocida'),
  'fault_assign': ('Fault assigned', 'Falla asignada'),
  'fault_start': ('Fault work started', 'Reparación iniciada'),
  'fault_submit': ('Fault ready for review', 'Falla lista para revisión'),
  'fault_resolve': ('Fault resolved', 'Falla resuelta'),
  'fault_dismiss': ('Fault dismissed', 'Falla descartada'),
  'fault_reopen': ('Fault reopened', 'Falla reabierta'),
  'fault_return': (
    'Fault returned for correction',
    'Falla devuelta para corrección',
  ),
  'fault_link': ('Fault linked to work', 'Falla vinculada a un trabajo'),
  'report_photo_added': ('Report photo added', 'Foto del informe añadida'),
  'report_photo_changed': ('Report photo changed', 'Foto del informe cambiada'),
  'report_photo_removed': (
    'Report photo removed',
    'Foto del informe eliminada',
  ),
  'comment': ('Note posted', 'Nota publicada'),
  'handover': ('Shift handover posted', 'Relevo de turno publicado'),
  'handover_acknowledged': ('Handover acknowledged', 'Relevo confirmado'),
};
String historyKindLabel(String? key, bool es) => historyKinds.containsKey(key)
    ? coordinationLabel(historyKinds, key!, es)
    : (es ? 'Evento de mantenimiento' : 'Maintenance event');
String coordinationLabel(
  Map<String, (String, String)> labels,
  String key,
  bool es,
) {
  final value = labels[key];
  return value == null
      ? key.replaceAll('_', ' ')
      : es
      ? value.$2
      : value.$1;
}

const _details = {
  'original_recorded_at': (
    'Original record date',
    'Fecha del registro original',
  ),
  'location': ('Location', 'Ubicación'),
  'previous_location': ('Previous location', 'Ubicación anterior'),
  'previous_name': ('Previous name', 'Nombre anterior'),
  'make': ('Make', 'Marca'),
  'model': ('Model', 'Modelo'),
  'serial_number': ('Serial number', 'Número de serie'),
  'component': ('Component', 'Componente'),
  'hours': ('Hours', 'Horas'),
  'previous_hours': ('Previous hours', 'Horas anteriores'),
  'interval_hours': ('Service interval (h)', 'Intervalo de servicio (h)'),
  'last_service_hours': ('Last service (h)', 'Último servicio (h)'),
  'next_due_hours': ('Next service (h)', 'Próximo servicio (h)'),
  'status': ('Status', 'Estado'),
  'previous_status': ('Previous status', 'Estado anterior'),
  'scheduled_date': ('Scheduled date', 'Fecha programada'),
  'assignee': ('Assigned to', 'Asignado a'),
  'part_number': ('Part number', 'Número de pieza'),
  'quantity': ('Quantity', 'Cantidad'),
  'previous_quantity': ('Previous quantity', 'Cantidad anterior'),
  'unit_cost': ('Unit cost', 'Costo unitario'),
  'total_cost': ('Internal total cost', 'Costo interno total'),
  'parts_cost': ('Parts cost', 'Costo de piezas'),
  'hourly_cost': ('Internal hourly cost', 'Costo interno por hora'),
  'labour_hours': ('Labour hours', 'Horas de trabajo'),
  'diagnosis': ('Diagnosis', 'Diagnóstico'),
  'repair': ('Repair', 'Reparación'),
  'notes': ('Notes', 'Notas'),
  'signed_at': ('Signed', 'Firmado'),
  'completed_at': ('Completed', 'Completado'),
  'trip_hours': ('Trip hours', 'Horas del viaje'),
  'fuel_added': ('Fuel added', 'Combustible añadido'),
  'photo_count': ('Photos', 'Fotos'),
  'checklist_type': ('Inspection type', 'Tipo de inspección'),
  'checklist_count': ('Checklist items', 'Elementos de inspección'),
  'evidence_count': ('Evidence photos', 'Fotos de evidencia'),
  'next_steps': (
    'Next shift / outstanding work',
    'Próximo turno / trabajo pendiente',
  ),
};
String historyDetailText(Map<String, dynamic> data, bool es) {
  final lines = <String>[];
  for (final entry in _details.entries) {
    final value = data[entry.key];
    if (value != null && value.toString().isNotEmpty) {
      lines.add(
        '${es ? entry.value.$2 : entry.value.$1}: ${_historyValue(entry.key, value, es)}',
      );
    }
  }
  if (data['isolation'] != null) {
    lines.add(
      '${es ? 'Aislamiento' : 'Isolation'}: ${coordinationLabel(isolationStates, data['isolation'].toString(), es)}',
    );
  }
  if (data['blocked_category'] != null) {
    lines.add(
      '${es ? 'Esperando' : 'Waiting for'}: ${coordinationLabel(blockedCategories, data['blocked_category'].toString(), es)}',
    );
  }
  if (data['active'] != null) {
    lines.add(
      '${es ? 'Plan activo' : 'Active plan'}: ${data['active'] == true ? (es ? 'Sí' : 'Yes') : (es ? 'No' : 'No')}',
    );
  }
  if (data['parts'] is List) {
    for (final part in data['parts'] as List) {
      if (part is Map) {
        lines.add(
          '${es ? 'Pieza' : 'Part'}: ${part['description'] ?? ''} · ${part['part_number'] ?? ''} · ${part['quantity'] ?? 0} × ${_historyValue('unit_cost', part['unit_cost'] ?? 0, es)}',
        );
      }
    }
  }
  if (data['visibility'] != null) {
    lines.add(
      data['visibility'] == 'shared'
          ? (es ? 'Compartida entre equipos' : 'Shared across teams')
          : (es ? 'Solo el equipo' : 'Team only'),
    );
  }
  if (data['ownership_changed'] == true) {
    lines.add(es ? 'Cambió la empresa del activo' : 'Asset company changed');
  }
  if (data['historical_snapshot'] == true) {
    lines.add(
      es
          ? 'Registro histórico: estado conservado al iniciar el historial.'
          : 'Historical snapshot: state preserved when history tracking began.',
    );
  }
  return lines.join('\n');
}

String _historyValue(String key, Object value, bool es) {
  const costs = {'unit_cost', 'total_cost', 'parts_cost', 'hourly_cost'};
  final number = value is num ? value : num.tryParse(value.toString());
  if (number != null &&
      number.isFinite &&
      (costs.contains(key) || key == 'labour_hours')) {
    final formatted = NumberFormat('0.00', es ? 'es' : 'en').format(number);
    return costs.contains(key) ? '$formatted USD' : formatted;
  }
  return value.toString();
}
