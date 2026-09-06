part of 'maintenance_repository.dart';

MaintenanceJob projectMaintenanceFieldWork(
  Map<String, dynamic> server,
  List<FieldOperation> operations,
) {
  final row = jsonDecode(jsonEncode(server)) as Map<String, dynamic>;
  for (final operation in operations) {
    if (operation.subject != row['id'] || operation.status == 'cancelled') {
      continue;
    }
    if (!operation.synced) row['local_pending'] = true;
    if (operation.needsAttention) {
      row['local_conflict'] = true;
      break;
    }
    if (operation.kind != 'apply_maintenance_field_action') continue;
    final payload = operation.payload;
    final revision = (payload['p_revision'] as num).toInt();
    if (revision < (row['revision'] as num).toInt()) continue;
    if (revision != row['revision']) {
      row['local_conflict'] = true;
      break;
    }
    final data = payload['p_data'] as Map<String, dynamic>;
    switch (payload['p_action']) {
      case 'start':
        row['status'] = 'in_progress';
        row['labour'] = [
          ...?row['labour'] as List?,
          {
            'id': operation.id,
            'actor_id': data['_actor'],
            'started_at': payload['p_recorded_at'],
            'stopped_at': null,
          },
        ];
      case 'pause':
        row['labour'] = maintenanceRows(row['labour'])
            .map(
              (l) =>
                  l['stopped_at'] == null &&
                      (data['session_id'] == null ||
                          data['session_id'] == l['id'])
                  ? {...l, 'stopped_at': payload['p_recorded_at']}
                  : l,
            )
            .toList();
      case 'block':
        row['status'] = 'on_hold';
        row['on_hold_reason'] = data['note'];
      case 'save_report':
      case 'submit':
        row['report'] = {
          'diagnosis': data['diagnosis'],
          'repair': data['repair'],
          'notes': data['notes'],
        };
        row['checklist_answers'] = data['answers'];
        row['evidence_paths'] = data['evidence_paths'];
        row['hours_at_end'] = data['completion_hours'];
        if (payload['p_action'] == 'submit') row['status'] = 'pending_review';
      case 'add_part':
        row['parts'] = [
          ...?row['parts'] as List?,
          {
            ...data,
            'id': operation.id,
            'quantity': num.parse(data['quantity'].toString()),
            'unit_cost': num.parse(data['unit_cost'].toString()),
          },
        ];
      case 'remove_part':
        row['parts'] = maintenanceRows(
          row['parts'],
        ).where((p) => p['id'] != data['part_id']).toList();
    }
    row['revision'] = revision + 1;
  }
  return MaintenanceJob(row);
}
