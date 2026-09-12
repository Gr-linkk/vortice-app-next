import 'package:vortice_app/core/meter_units.dart';
import '../maintenance_models.dart';

DateTime planningDay(DateTime value) =>
    DateTime(value.year, value.month, value.day);
DateTime planningWeek(DateTime value) =>
    DateTime(value.year, value.month, value.day - value.weekday + 1);

class PlanningJob extends MaintenanceJob {
  PlanningJob(super.data);
  DateTime? get start =>
      DateTime.tryParse(data['planned_start'] as String? ?? '')?.toLocal();
  int get minutes => (data['estimated_minutes'] as num?)?.toInt() ?? 0;
  DateTime? get end => start?.add(Duration(minutes: minutes));
  String? get assignee => data['assigned_to'] as String?;
  String get assigneeName => data['assignee_name'] as String? ?? '';
  Map<String, String> get workers => data['workers'] is Map
      ? Map<String, String>.from(data['workers'] as Map)
      : {if (assignee != null) assignee!: assigneeName};
  bool get providerService => data['provider_service'] == true;
  DateTime? get serviceDate =>
      DateTime.tryParse(data['service_date'] as String? ?? '');
  String get route => data['route'] as String? ?? '/maintenance/jobs/$id';
  bool get meterDue =>
      !completed &&
      data['cycle_approved_at'] == null &&
      data['due_meter'] is num &&
      data['current_meter'] is num &&
      (data['current_meter'] as num) >= (data['due_meter'] as num);
  String get componentName => data['component_name'] as String? ?? '';
  String get blockedCategory => data['blocked_category'] as String? ?? 'other';
  bool get unscheduled => start == null && serviceDate == null && activeBooking;
  bool matchesFilter(String filter, String? userId, DateTime now) =>
      switch (filter) {
        'mine' =>
          !completed &&
              userId != null &&
              (data['assigned_to_me'] == true || assignee == userId),
        'unassigned' => activeBooking && workers.isEmpty,
        'unscheduled' => unscheduled,
        'review' => status == 'pending_review',
        'returned' => returned,
        'completed' => completed,
        'overdue' => !completed && overdue(now),
        'parts' => status == 'on_hold' && blockedCategory == 'parts',
        'people' => status == 'on_hold' && blockedCategory == 'people',
        'blocked' =>
          status == 'on_hold' && !['parts', 'people'].contains(blockedCategory),
        _ => !completed,
      };
  bool matchesSearch(String query, bool es) =>
      '$title $assetName $componentName $assigneeName $status ${lifecycleLabel(es)} ${status == 'invoiced' ? (es ? 'Facturado' : 'Invoiced') : ''} ${workType.dbValue} ${workType.label(es)}'
          .toLowerCase()
          .contains(query.trim().toLowerCase());
  bool inPeriod(DateTime from, DateTime until) => (providerService
      ? serviceDate != null &&
            !serviceDate!.isBefore(from) &&
            serviceDate!.isBefore(until)
      : overlaps(from, until));
  bool get conflict => data['conflict'] == true;
  bool get schedulable => !providerService && canManage && activeBooking;
  bool get activeBooking =>
      !['closed', 'invoiced', 'pending_review'].contains(status);
  bool overdue(DateTime now) {
    if (completed) return false;
    if (meterDue) return true;
    final due = DateTime.tryParse(dueDate ?? '');
    return due != null && due.isBefore(planningDay(now));
  }

  bool overlaps(DateTime from, DateTime until) =>
      start != null && end!.isAfter(from) && start!.isBefore(until);
  double hoursBetween(DateTime from, DateTime until) {
    if (!overlaps(from, until)) return 0;
    final left = start!.isAfter(from) ? start! : from;
    final right = end!.isBefore(until) ? end! : until;
    return right.difference(left).inMinutes / 60;
  }
}

class PlanningPlan {
  PlanningPlan(this.data);
  final Map<String, dynamic> data;
  String get id => data['id'] as String;
  String get assetId => data['asset_id'] as String;
  String get assetName => data['asset_name'] as String? ?? '';
  String get title =>
      data['interval_label'] as String? ??
      formatMeter(
        data['interval_hours'] as num?,
        data['meter_unit'] as String?,
      );
  String? get component => data['component_name'] as String?;
  double? get remainingHours {
    final due = data['next_due_hours'], current = data['current_hours'];
    return due is num && current is num ? (due - current).toDouble() : null;
  }

  DateTime? get nextDate =>
      DateTime.tryParse(data['next_due_date']?.toString() ?? '');
  bool dueOn(DateTime today) =>
      (remainingHours != null && remainingHours! <= 0) ||
      (nextDate != null && !nextDate!.isAfter(planningDay(today)));
  bool get due => dueOn(DateTime.now());
  bool get needsSetup =>
      data['engine_id'] == null ||
      ((data['interval_hours'] as num? ?? 1) > 0 && remainingHours == null) ||
      (data['interval_months'] != null && nextDate == null);
  bool get hasJob => data['has_open_job'] == true;
  String? get openJobId => data['open_job_id'] as String?;
  bool get canManage => data['can_manage'] == true;
}

class PlanningData {
  PlanningData({required this.jobs, required this.plans});
  factory PlanningData.fromJson(Map<String, dynamic> json) => PlanningData(
    jobs: maintenanceRows(json['jobs']).map(PlanningJob.new).toList(),
    plans: maintenanceRows(json['plans']).map(PlanningPlan.new).toList(),
  );
  final List<PlanningJob> jobs;
  final List<PlanningPlan> plans;
}

List<PlanningJob> bookingConflicts(
  Iterable<PlanningJob> jobs, {
  required String jobId,
  required String assetId,
  required String? assignee,
  required DateTime? start,
  required int minutes,
}) {
  if (start == null) return [];
  return jobs
      .where(
        (job) =>
            job.id != jobId &&
            job.activeBooking &&
            (job.assetId == assetId ||
                (assignee != null && job.assignee == assignee)) &&
            job.overlaps(start, start.add(Duration(minutes: minutes))),
      )
      .toList();
}

int comparePlanningJobs(PlanningJob a, PlanningJob b) {
  const priorities = {'urgent': 0, 'high': 1, 'normal': 2, 'low': 3};
  final dates = (a.start ?? a.serviceDate ?? DateTime(9999)).compareTo(
    b.start ?? b.serviceDate ?? DateTime(9999),
  );
  if (dates != 0) return dates;
  final urgency = (priorities[a.priority] ?? 2).compareTo(
    priorities[b.priority] ?? 2,
  );
  if (urgency != 0) return urgency;
  final due = (a.dueDate ?? '9999').compareTo(b.dueDate ?? '9999');
  return due == 0 ? a.id.compareTo(b.id) : due;
}
