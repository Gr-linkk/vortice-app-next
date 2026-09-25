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
const _historyCategoryFr = {
  'asset': 'Équipement et emplacement',
  'usage': 'Relevés du compteur',
  'inspection': 'Inspections',
  'fault': 'Défaillances',
  'availability': 'Disponibilité',
  'work': 'Travail',
  'service': 'Rapports d’intervention',
  'parts': 'Pièces et coûts internes',
  'discussion': 'Discussion et passation',
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
const _attentionCategoryFr = {
  'unavailable': 'Équipements indisponibles',
  'urgent_faults': 'Défaillances urgentes',
  'overdue_service': 'Entretien en retard',
  'overdue_work': 'Travail en retard',
  'review': 'En attente de révision',
  'waiting_parts': 'En attente de pièces',
  'waiting_people': 'En attente de personnel',
  'blocked_other': 'Autres travaux bloqués',
  'approaching_service': 'Entretien dans moins de 50 h',
  'upcoming_work': 'Travail prévu dans 7 jours',
  'plan_setup': 'Plan d’entretien à configurer',
  'unassessed': 'Disponibilité inconnue',
};
const blockedCategories = {
  'parts': ('Parts', 'Piezas'),
  'people': ('People', 'Personal'),
  'external': ('External dependency', 'Dependencia externa'),
  'other': ('Other', 'Otro'),
};
const _blockedCategoryFr = {
  'parts': 'Pièces',
  'people': 'Personnel',
  'external': 'Dépendance externe',
  'other': 'Autre',
};
const isolationStates = {
  'unknown': ('Not confirmed', 'Sin confirmar'),
  'isolated': ('Isolated', 'Aislado'),
  'not_isolated': ('Not isolated', 'Sin aislar'),
  'not_required': ('Isolation not required', 'No requiere aislamiento'),
};
const _isolationStateFr = {
  'unknown': 'Non confirmé',
  'isolated': 'Isolé',
  'not_isolated': 'Non isolé',
  'not_required': 'Isolation non requise',
};
const historyKinds = {
  'custody_transferred': ('Custody transferred', 'Custodia transferida'),
  'inspection_required': ('Inspection registered', 'Inspección registrada'),
  'renewal_submit': ('Renewal submitted', 'Renovación enviada'),
  'renewal_approve': ('Renewal approved', 'Renovación aprobada'),
  'renewal_return': ('Renewal returned', 'Renovación devuelta'),
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
const _historyKindFr = {
  'custody_transferred': 'Garde transférée',
  'inspection_required': 'Inspection consignée',
  'renewal_submit': 'Renouvellement soumis',
  'renewal_approve': 'Renouvellement approuvé',
  'renewal_return': 'Renouvellement retourné',
  'asset_recorded': 'Équipement consigné',
  'asset_changed': 'Détails de l’équipement modifiés',
  'component_recorded': 'Composant consigné',
  'component_changed': 'Détails du composant modifiés',
  'meter_updated': 'Compteur mis à jour',
  'plan_recorded': 'Plan d’entretien consigné',
  'plan_changed': 'Plan d’entretien modifié',
  'plan_removed': 'Plan d’entretien supprimé',
  'hours_logged': 'Heures consignées',
  'reading_removed': 'Relevé supprimé',
  'reading_corrected': 'Relevé corrigé',
  'job_recorded': 'Travail consigné',
  'job_changed': 'Travail modifié',
  'job_removed': 'Travail supprimé',
  'maintenance_created': 'Bon de travail créé',
  'maintenance_assign': 'Travail attribué',
  'maintenance_start': 'Travail commencé ou repris',
  'maintenance_pause': 'Temps de travail suspendu',
  'maintenance_block': 'Travail bloqué',
  'maintenance_add_part': 'Pièce ajoutée',
  'maintenance_save_report': 'Brouillon du rapport enregistré',
  'maintenance_submit': 'Rapport soumis pour révision',
  'maintenance_return': 'Travail retourné pour correction',
  'maintenance_reopen': 'Travail rouvert',
  'maintenance_approve': 'Travail approuvé et fermé',
  'part_recorded': 'Pièce consignée',
  'part_removed': 'Pièce retirée',
  'part_changed': 'Pièce modifiée',
  'report_recorded': 'Rapport d’intervention consigné',
  'report_changed': 'Rapport d’intervention modifié',
  'report_removed': 'Rapport d’intervention supprimé',
  'inspection_submitted': 'Inspection soumise',
  'inspection_changed': 'Inspection modifiée',
  'inspection_removed': 'Inspection supprimée',
  'operator_run_recorded': 'Inspection de l’opérateur consignée',
  'availability_changed': 'Disponibilité modifiée',
  'fault_reported': 'Défaillance signalée',
  'fault_acknowledge': 'Défaillance reconnue',
  'fault_assign': 'Défaillance attribuée',
  'fault_start': 'Travail sur la défaillance commencé',
  'fault_submit': 'Défaillance prête pour révision',
  'fault_resolve': 'Défaillance résolue',
  'fault_dismiss': 'Défaillance rejetée',
  'fault_reopen': 'Défaillance rouverte',
  'fault_return': 'Défaillance retournée pour correction',
  'fault_link': 'Défaillance liée au bon de travail',
  'report_photo_added': 'Photo ajoutée au rapport',
  'report_photo_changed': 'Photo du rapport modifiée',
  'report_photo_removed': 'Photo du rapport supprimée',
  'comment': 'Note publiée',
  'handover': 'Passation de quart publiée',
  'handover_acknowledged': 'Passation confirmée',
};
String historyKindLabel(String? key, bool es, {bool french = false}) => french
    ? _historyKindFr[key] ?? 'Événement d’entretien'
    : historyKinds.containsKey(key)
    ? coordinationLabel(historyKinds, key!, es)
    : (es ? 'Evento de mantenimiento' : 'Maintenance event');
String coordinationLabel(
  Map<String, (String, String)> labels,
  String key,
  bool es, {
  bool french = false,
}) {
  final value = labels[key];
  if (french) {
    final table = identical(labels, historyCategories)
        ? _historyCategoryFr
        : identical(labels, attentionCategories)
        ? _attentionCategoryFr
        : identical(labels, blockedCategories)
        ? _blockedCategoryFr
        : identical(labels, isolationStates)
        ? _isolationStateFr
        : null;
    if (table != null) return table[key] ?? key.replaceAll('_', ' ');
  }
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
String historyDetailText(
  Map<String, dynamic> data,
  bool es, {
  bool french = false,
}) {
  final lines = <String>[];
  const frenchLabels = <String, String>{
    'original_recorded_at': 'Date d’enregistrement initiale',
    'location': 'Emplacement',
    'previous_location': 'Emplacement précédent',
    'previous_name': 'Nom précédent',
    'make': 'Marque',
    'model': 'Modèle',
    'serial_number': 'Numéro de série',
    'component': 'Composant',
    'hours': 'Heures',
    'previous_hours': 'Heures précédentes',
    'interval_hours': 'Intervalle d’entretien (h)',
    'last_service_hours': 'Dernier entretien (h)',
    'next_due_hours': 'Prochain entretien (h)',
    'status': 'État',
    'previous_status': 'État précédent',
    'scheduled_date': 'Date planifiée',
    'assignee': 'Attribué à',
    'part_number': 'Numéro de pièce',
    'quantity': 'Quantité',
    'previous_quantity': 'Quantité précédente',
    'unit_cost': 'Coût unitaire',
    'total_cost': 'Coût interne total',
    'parts_cost': 'Coût des pièces',
    'hourly_cost': 'Coût horaire interne',
    'labour_hours': 'Heures de travail',
    'diagnosis': 'Diagnostic',
    'repair': 'Réparation',
    'notes': 'Notes',
    'signed_at': 'Signé',
    'completed_at': 'Terminé',
    'trip_hours': 'Heures de déplacement',
    'fuel_added': 'Carburant ajouté',
    'photo_count': 'Photos',
    'checklist_type': 'Type d’inspection',
    'checklist_count': 'Éléments de la liste de contrôle',
    'evidence_count': 'Photos justificatives',
    'next_steps': 'Prochain quart / travail restant',
  };
  for (final entry in _details.entries) {
    final value = data[entry.key];
    if (value != null && value.toString().isNotEmpty) {
      lines.add(
        '${french
            ? frenchLabels[entry.key] ?? entry.value.$1
            : es
            ? entry.value.$2
            : entry.value.$1}: ${_historyValue(entry.key, value, es, data['cost_currency'] as String? ?? 'USD')}',
      );
    }
  }
  if (data['isolation'] != null) {
    lines.add(
      '${french
          ? 'Isolement'
          : es
          ? 'Aislamiento'
          : 'Isolation'}: ${coordinationLabel(isolationStates, data['isolation'].toString(), es, french: french)}',
    );
  }
  if (data['blocked_category'] != null) {
    lines.add(
      '${french
          ? 'En attente de'
          : es
          ? 'Esperando'
          : 'Waiting for'}: ${coordinationLabel(blockedCategories, data['blocked_category'].toString(), es, french: french)}',
    );
  }
  if (data['active'] != null) {
    lines.add(
      '${french
          ? 'Plan actif'
          : es
          ? 'Plan activo'
          : 'Active plan'}: ${data['active'] == true ? (french
                ? 'Oui'
                : es
                ? 'Sí'
                : 'Yes') : 'Non'}',
    );
  }
  if (data['parts'] is List) {
    for (final part in data['parts'] as List) {
      if (part is Map) {
        lines.add(
          '${french
              ? 'Pièce'
              : es
              ? 'Pieza'
              : 'Part'}: ${part['description'] ?? ''} · ${part['part_number'] ?? ''} · ${part['quantity'] ?? 0} × ${_historyValue('unit_cost', part['unit_cost'] ?? 0, es, data['cost_currency'] as String? ?? 'USD')}',
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

String _historyValue(String key, Object value, bool es, String currency) {
  const costs = {'unit_cost', 'total_cost', 'parts_cost', 'hourly_cost'};
  final number = value is num ? value : num.tryParse(value.toString());
  if (number != null &&
      number.isFinite &&
      (costs.contains(key) || key == 'labour_hours')) {
    final formatted = NumberFormat('0.00', es ? 'es' : 'en').format(number);
    return costs.contains(key) ? '$formatted $currency' : formatted;
  }
  return value.toString();
}
