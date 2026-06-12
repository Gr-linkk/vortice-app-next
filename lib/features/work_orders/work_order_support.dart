import 'package:vortice_app/models/profile.dart';
import 'package:vortice_app/models/work_order.dart';

const unnamedTechLabel = 'Unnamed tech';

bool shouldBypassWorkOrderAssignmentFilter(UserRole? role) =>
    role == null || role == UserRole.owner || role == UserRole.employee;

List<WorkOrder> filterWorkOrdersForAssignee({
  required List<WorkOrder> orders,
  required Set<String> assignedIds,
  required String profileId,
}) {
  if (assignedIds.isNotEmpty) {
    return orders.where((order) => assignedIds.contains(order.id)).toList();
  }
  return orders.where((order) => order.assignedTo == profileId).toList();
}

String? formatProfileName(
  Object? value, {
  String? fallback = unnamedTechLabel,
}) {
  final name = value is String ? value.trim() : '';
  if (name.isNotEmpty) return name;
  return fallback;
}

DateTime? parseDateTime(Object? value) {
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

class EngineHoursSnapshot {
  final double? hours;
  final String? workOrderId;
  final String? title;

  const EngineHoursSnapshot({
    required this.hours,
    this.workOrderId,
    this.title,
  });
}

EngineHoursSnapshot parseLatestEngineHours(List<Map<String, dynamic>> rows) {
  for (final row in rows) {
    if (row['hours_at_end'] == null && row['hours_at_start'] == null) {
      continue;
    }
    return EngineHoursSnapshot(
      hours: (row['hours_at_end'] as num?)?.toDouble() ??
          (row['hours_at_start'] as num?)?.toDouble(),
      workOrderId: row['id'] as String?,
      title: row['title'] as String?,
    );
  }
  return const EngineHoursSnapshot(hours: null);
}
