import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vortice_app/features/auth/auth_provider.dart';

import 'package:vortice_app/models/work_order.dart';
import 'maintenance_models.dart';
import 'planning/planning_repository.dart';

/// Discovery only: each entry keeps its own permissions and execution route.
class WorkListEntry {
  const WorkListEntry({
    required this.id,
    required this.title,
    required this.assetName,
    required this.status,
    required this.route,
    required this.assignedToMe,
    required this.service,
    this.date,
    this.priority,
    this.dueDate,
    this.workType,
    this.hasBooking,
    this.returned = false,
    this.ownEquipment = true,
  });
  final String id, title, assetName, status, route;
  final bool assignedToMe, service;
  final DateTime? date;
  final String? priority, dueDate;
  final WorkOrderJobType? workType;
  final bool? hasBooking;
  final bool returned;
  final bool ownEquipment;
  String lifecycleLabel(bool es, {bool french = false}) => maintenanceStatus(
    status,
    es,
    french: french,
    booked: hasBooking,
    returned: returned,
  );
  bool get completed => status == 'closed' || status == 'invoiced';

  bool matches(String filter, String query) =>
      (filter == 'mine'
          ? assignedToMe && !completed
          : filter == 'open'
          ? !completed
          : filter == 'closed'
          ? completed
          : status == filter) &&
      '$title $assetName'.toLowerCase().contains(query);
}

final workListProvider = FutureProvider.autoDispose
    .family<List<WorkListEntry>, String?>((ref, assetId) async {
      final profile = await ref.watch(profileProvider.future);
      if (profile == null ||
          !profile.membershipManaged && !canUseMaintenance(profile.role)) {
        return [];
      }
      final page = await ref.watch(
        displayedMaintenancePlanningProvider(assetId).future,
      );
      final entries = [
        for (final job in page.jobs)
          WorkListEntry(
            id: job.id,
            title: job.title,
            assetName: job.assetName,
            status: job.status,
            route: job.route,
            assignedToMe:
                job.data['assigned_to_me'] == true ||
                job.assignee == profile.id,
            service: job.providerService,
            date: DateTime.tryParse(job.data['created_at']?.toString() ?? ''),
            priority: job.priority,
            dueDate: job.dueDate,
            workType: job.workType,
            hasBooking: job.hasBooking,
            returned: job.returned,
            ownEquipment: job.ownEquipment,
          ),
      ];
      final epoch = DateTime.fromMillisecondsSinceEpoch(0);
      entries.sort((a, b) {
        final dates = (b.date ?? epoch).compareTo(a.date ?? epoch);
        return dates == 0 ? a.id.compareTo(b.id) : dates;
      });
      return entries;
    });
