import 'package:vortice_app/models/asset_service_interval.dart';
import 'package:vortice_app/models/work_order.dart';

class ServiceIntervalSummary {
  final AssetServiceInterval interval;
  final double? currentHours;
  final double? nextDueHours;
  final String? activeWorkOrderId;
  final int sortIndex;

  const ServiceIntervalSummary({
    required this.interval,
    this.currentHours,
    this.nextDueHours,
    this.activeWorkOrderId,
    required this.sortIndex,
  });

  double? get lastServiceHours =>
      nextDueHours == null ? null : nextDueHours! - interval.intervalHours;

  double? get hoursRemaining => nextDueHours == null || currentHours == null
      ? null
      : nextDueHours! - currentHours!;
}

class ServiceReminderRecord {
  final String id;
  final String? serviceIntervalId;
  final int intervalHours;
  final double? dueAtHours;
  final bool acknowledged;

  const ServiceReminderRecord({
    required this.id,
    required this.serviceIntervalId,
    required this.intervalHours,
    required this.dueAtHours,
    required this.acknowledged,
  });

  factory ServiceReminderRecord.fromRow(Map<String, dynamic> row) {
    return ServiceReminderRecord(
      id: row['id'] as String,
      serviceIntervalId: row['service_interval_id'] as String?,
      intervalHours: ((row['interval_hours'] as num?)?.toDouble() ?? 0).toInt(),
      dueAtHours: (row['due_at_hours'] as num?)?.toDouble(),
      acknowledged: row['acknowledged'] as bool? ?? false,
    );
  }
}

bool shouldPreferServiceReminder(
  ServiceReminderRecord? current,
  ServiceReminderRecord candidate,
) {
  if (current == null) return true;
  if (current.acknowledged && !candidate.acknowledged) return true;
  if (current.acknowledged == candidate.acknowledged &&
      (candidate.dueAtHours ?? double.negativeInfinity) >
          (current.dueAtHours ?? double.negativeInfinity)) {
    return true;
  }
  return false;
}

ServiceReminderRecord? pickReminderForInterval(
  AssetServiceInterval interval,
  List<ServiceReminderRecord> reminders, {
  int? previousIntervalHours,
}) {
  ServiceReminderRecord? linkedReminder;
  ServiceReminderRecord? legacyReminder;

  for (final reminder in reminders) {
    if (reminder.serviceIntervalId == interval.id) {
      if (shouldPreferServiceReminder(linkedReminder, reminder)) {
        linkedReminder = reminder;
      }
      continue;
    }

    if (reminder.serviceIntervalId == null &&
        reminder.intervalHours ==
            (previousIntervalHours ?? interval.intervalHours.toInt())) {
      if (shouldPreferServiceReminder(legacyReminder, reminder)) {
        legacyReminder = reminder;
      }
    }
  }

  return linkedReminder ?? legacyReminder;
}

bool isActivePreventativeWorkOrderStatus(String? status) =>
    status != WorkOrderStatus.closed.dbValue &&
    status != WorkOrderStatus.invoiced.dbValue;

String intervalFallbackWorkOrderTitle(AssetServiceInterval interval) =>
    interval.label ?? '${interval.intervalHours.toInt()}h Service';

bool workOrderMatchesServiceInterval({
  required AssetServiceInterval interval,
  required Map<String, dynamic> workOrder,
}) {
  final templateId = workOrder['checklist_template_id'] as String?;
  final title = workOrder['title'] as String?;
  if (interval.checklistTemplateId != null) {
    return templateId == interval.checklistTemplateId;
  }
  return title == intervalFallbackWorkOrderTitle(interval);
}

Map<String, dynamic>? matchActiveWorkOrderForInterval({
  required AssetServiceInterval interval,
  required List<Map<String, dynamic>> activeWorkOrders,
}) {
  for (final workOrder in activeWorkOrders) {
    if (workOrderMatchesServiceInterval(
      interval: interval,
      workOrder: workOrder,
    )) {
      return workOrder;
    }
  }
  return null;
}

int compareServiceIntervalSummaries(
  ServiceIntervalSummary a,
  ServiceIntervalSummary b,
) {
  final hoursCompare = a.interval.intervalHours.compareTo(
    b.interval.intervalHours,
  );
  if (hoursCompare != 0) return hoursCompare;

  final aLabel = a.interval.label ?? '';
  final bLabel = b.interval.label ?? '';
  final labelCompare = aLabel.compareTo(bLabel);
  if (labelCompare != 0) return labelCompare;

  return a.sortIndex.compareTo(b.sortIndex);
}

double? hoursFromWorkOrderRow(Map<String, dynamic>? row) {
  if (row == null) return null;
  return (row['hours_at_end'] as num?)?.toDouble() ??
      (row['hours_at_start'] as num?)?.toDouble();
}

double computeNextDueHours({
  required double? previousDueHours,
  required int previousIntervalHours,
  required double currentHours,
  required int intervalHours,
  double? explicitNextDueHours,
}) {
  if (explicitNextDueHours != null) return explicitNextDueHours;
  final lastServiceHours = previousDueHours == null
      ? currentHours
      : previousDueHours - previousIntervalHours.toDouble();
  return lastServiceHours + intervalHours.toDouble();
}

Map<String, dynamic> normalizeServiceIntervalRow(Map<String, dynamic> row) {
  final normalized = Map<String, dynamic>.from(row);
  if (normalized.containsKey('interval_label')) {
    normalized['label'] = normalized['interval_label'];
  }
  if (normalized.containsKey('is_active')) {
    normalized['enabled'] = normalized['is_active'];
  }
  return normalized;
}
