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
import 'dart:convert';
import 'package:vortice_app/core/account_storage.dart';
import '../maintenance_repository.dart';

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
  Future<PlanningData> load(String? assetId) async {
    final cache=AccountJsonCache(client.auth.currentUser?.id ?? 'signed_out',()=>client.auth.currentUser?.id);
    final params={if(assetId != null) 'p_asset':assetId};
    final key='maintenance_work_hub:${jsonEncode(params)}';
    Future<dynamic>? request;
    Future<dynamic> remote() => request ??= client.rpc('maintenance_work_hub',params:params).timeout(const Duration(seconds:6));
    // Store the permission-bearing lists separately so removal of a job or plan
    // invalidates stale details through AccountJsonCache's existing epoch rule.
    final jobs=await cache.readThrough('$key:jobs',() async => (await remote() as Map)['jobs'] ?? []);
    final plans=await cache.readThrough('$key:plans',() async => (await remote() as Map)['plans'] ?? []);
    return PlanningData.fromJson({'jobs':jobs,'plans':plans});
  }
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
      // Connected reads refresh permissions; cached tasks stay readable offline.
      final operations = await ref.watch(fieldOperationsProvider.future);
      final managedFuture = ref.watch(planningRepositoryProvider).load(assetId);
      final staff = profile.membershipManaged || [UserRole.owner, UserRole.employee].contains(profile.role);
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
        jobs: [for(final job in managed.jobs) PlanningJob(projectMaintenanceFieldWork(job.data,operations).data), ...serviceJobs],
        plans: managed.plans,
      );
    });
