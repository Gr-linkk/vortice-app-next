import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/work_orders/work_order_provider.dart';
import 'package:vortice_app/models/profile.dart';
import 'package:vortice_app/models/work_order.dart';
import 'package:vortice_app/core/app_navigation.dart';
import 'package:vortice_app/sync/field_work_provider.dart';
import 'planning_models.dart';
import 'planning_service_repository.dart';

abstract class PlanningRepository {
  Future<PlanningData> load(String? assetId);
  Future<void> schedule(
    String jobId,
    int revision,
    String operationId,
    Map<String, dynamic> data,
  );
}

class SupabasePlanningRepository implements PlanningRepository {
  SupabasePlanningRepository(this.client);
  final SupabaseClient client;
  @override
  Future<PlanningData> load(String? assetId) async => PlanningData.fromJson(
    Map<String, dynamic>.from(
      await client
              .rpc(
                'maintenance_work_hub',
                params: {if (assetId != null) 'p_asset': assetId},
              )
              .timeout(const Duration(seconds: 15))
          as Map,
    ),
  );
  @override
  Future<void> schedule(
    String jobId,
    int revision,
    String operationId,
    Map<String, dynamic> data,
  ) async {
    await client
        .rpc(
          'schedule_maintenance_job',
          params: {
            'p_job': jobId,
            'p_revision': revision,
            'p_operation': operationId,
            'p_data': data,
          },
        )
        .timeout(const Duration(seconds: 15));
  }
}

final planningRepositoryProvider = Provider<PlanningRepository>((ref) {
  ref.watch(sessionProvider);
  return SupabasePlanningRepository(supabase);
});
final maintenancePlanningProvider = FutureProvider.autoDispose
    .family<PlanningData, String?>((ref, assetId) async {
      final profile = await ref.watch(profileProvider.future);
      if (profile == null) {
        return PlanningData(jobs: [], plans: []);
      }
      // Schedules are fresh online reads. Execution retains the existing account-owned queue.
      ref.watch(fieldOperationsProvider);
      final managedFuture = ref.watch(planningRepositoryProvider).load(assetId);
      final staff = [UserRole.owner, UserRole.employee].contains(profile.role);
      final ordersFuture = staff
          ? ref.watch(workOrdersProvider.future)
          : Future.value(<WorkOrder>[]);
      final (managed, orders) = await (managedFuture, ordersFuture).wait;
      final managedIds = managed.jobs.map((job) => job.id).toSet();
      final serviceOrders = [
        for (final order in orders)
          if (!managedIds.contains(order.id) &&
              (assetId == null || order.assetId == assetId))
            order,
      ];
      final serviceData = serviceOrders.isEmpty
          ? const PlanningServiceData()
          : await ref
                .watch(planningServiceRepositoryProvider)
                .load(serviceOrders, accountId: profile.id);
      final serviceJobs = [
        for (final order in serviceOrders)
          serviceData.project(order, profile.id, roleRoutePrefix(profile.role)),
      ];
      return PlanningData(
        jobs: [...managed.jobs, ...serviceJobs],
        plans: managed.plans,
      );
    });
