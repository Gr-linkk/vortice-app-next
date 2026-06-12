String employeeDisplayName(Map<String, dynamic> employee) {
  final name = (employee['full_name'] as String?)?.trim();
  return name != null && name.isNotEmpty ? name : 'Unnamed tech';
}

List<String> selectedTechnicianNames(
  List<Map<String, dynamic>> employees,
  List<String> assignedTechIds,
) {
  return employees
      .where((employee) => assignedTechIds.contains(employee['id'] as String))
      .map(employeeDisplayName)
      .toList();
}

String? primaryAssignedProfileId(List<String> assignedTechIds) =>
    assignedTechIds.isNotEmpty ? assignedTechIds.first : null;

Map<String, dynamic> buildUpdateWorkOrderPayload({
  required String title,
  required String description,
  required List<String> assignedTechIds,
  required DateTime? scheduledDate,
  required String hoursAtStartText,
  required String hoursAtEndText,
  required String labourHoursText,
  required String notesInternal,
  required String onHoldReason,
}) {
  return {
    'title': title.trim(),
    'description': description.trim().isNotEmpty ? description.trim() : null,
    'assigned_to': primaryAssignedProfileId(assignedTechIds),
    'scheduled_date': scheduledDate?.toIso8601String(),
    'hours_at_start': double.tryParse(hoursAtStartText.trim()),
    'hours_at_end': double.tryParse(hoursAtEndText.trim()),
    'labour_hours': double.tryParse(labourHoursText.trim()),
    'notes_internal':
        notesInternal.trim().isNotEmpty ? notesInternal.trim() : null,
    'on_hold_reason':
        onHoldReason.trim().isNotEmpty ? onHoldReason.trim() : null,
  };
}
