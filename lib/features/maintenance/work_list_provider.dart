import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/app_navigation.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/work_orders/work_order_provider.dart';
import 'package:vortice_app/models/profile.dart';
import 'package:vortice_app/models/work_order.dart';
import 'maintenance_models.dart';
import 'maintenance_repository.dart';

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
  });
  final String id, title, assetName, status, route;
  final bool assignedToMe, service;
  final DateTime? date;
  final String? priority, dueDate;
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
      if (!canUseMaintenance(profile?.role)) return [];
      final jobsFuture = ref.watch(maintenanceJobsProvider(assetId).future);
      // Client service-order detail routes are intentionally unavailable.
      // Their maintenance and published report access remains unchanged.
      final staff =
          profile!.role == UserRole.owner || profile.role == UserRole.employee;
      final ordersFuture = staff
          ? ref.watch(workOrdersProvider.future)
          : Future.value(<WorkOrder>[]);
      final (jobs, orders) = await (jobsFuture, ordersFuture).wait;
      final managedIds = jobs.map((job) => job.id).toSet();
      final entries = [
        for (final job in jobs)
          WorkListEntry(
            id: job.id,
            title: job.title,
            assetName: job.assetName,
            status: job.status,
            route: '/maintenance/jobs/${job.id}',
            assignedToMe: job.data['assigned_to'] == profile.id,
            service: false,
            date: DateTime.tryParse(job.data['created_at']?.toString() ?? ''),
            priority: job.priority,
            dueDate: job.dueDate,
          ),
      ];
      entries.addAll(
        await Future.wait([
          for (final order in orders)
            if (!managedIds.contains(order.id) &&
                (assetId == null || order.assetId == assetId))
              () async {
                final nameFuture = ref.watch(
                  assetNameProvider(order.assetId).future,
                );
                final assignedFuture = ref.watch(
                  currentUserAssignedToWorkOrderProvider(order.id).future,
                );
                final (name, assigned) = await (
                  nameFuture,
                  assignedFuture,
                ).wait;
                return WorkListEntry(
                  id: order.id,
                  title: order.title,
                  assetName: name ?? '',
                  status: order.status.dbValue,
                  route:
                      '${roleRoutePrefix(profile.role)}/work-orders/${order.id}',
                  assignedToMe: assigned,
                  service: true,
                  date: order.createdAt,
                );
              }(),
        ]),
      );
      final epoch = DateTime.fromMillisecondsSinceEpoch(0);
      entries.sort((a, b) {
        final dates = (b.date ?? epoch).compareTo(a.date ?? epoch);
        return dates == 0 ? a.id.compareTo(b.id) : dates;
      });
      return entries;
    });
