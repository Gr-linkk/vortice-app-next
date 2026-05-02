import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/db/database.dart';
import 'package:vortice_app/models/work_order.dart';
import 'package:vortice_app/models/work_order_assignment.dart';

final workOrdersProvider = FutureProvider<List<WorkOrder>>((ref) async {
  final db = ref.watch(databaseProvider);
  final dao = db.workOrdersDao;

  final remote = await supabase
      .from(AppConstants.tWorkOrders)
      .select()
      .order('created_at', ascending: false);

  final orders = (remote as List)
      .map((e) => WorkOrder.fromJson(e as Map<String, dynamic>))
      .toList();

  for (final wo in orders) {
    await dao.upsert(WorkOrdersTableCompanion(
      id: Value(wo.id),
      assetId: Value(wo.assetId),
      engineId: Value(wo.engineId),
      clientId: Value(wo.clientId),
      assignedTo: Value(wo.assignedTo),
      createdBy: Value(wo.createdBy),
      checklistTemplateId: Value(wo.checklistTemplateId),
      checklistTemplateVersion: Value(wo.checklistTemplateVersion),
      jobType: Value(wo.jobType.dbValue),
      title: Value(wo.title),
      description: Value(wo.description),
      status: Value(wo.status.dbValue),
      scheduledDate: Value(wo.scheduledDate),
      startedAt: Value(wo.startedAt),
      completedAt: Value(wo.completedAt),
      hoursAtStart: Value(wo.hoursAtStart),
      hoursAtEnd: Value(wo.hoursAtEnd),
      labourHours: Value(wo.labourHours),
      billableRate: Value(wo.billableRate),
      wageRate: Value(wo.wageRate),
      notesInternal: Value(wo.notesInternal),
      onHoldReason: Value(wo.onHoldReason),
      createdAt: Value(wo.createdAt),
      updatedAt: Value(wo.updatedAt),
    ));
  }

  return orders;
});

final workOrderByIdProvider =
    FutureProvider.family<WorkOrder?, String>((ref, id) async {
  final data = await supabase
      .from(AppConstants.tWorkOrders)
      .select()
      .eq('id', id)
      .maybeSingle();

  if (data == null) return null;
  return WorkOrder.fromJson(data);
});

class WorkOrderController extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;
  WorkOrderController(this._ref) : super(const AsyncData(null));

  Future<bool> createWorkOrder(
    Map<String, dynamic> data, {
    List<String> assignedProfileIds = const [],
  }) async {
    state = const AsyncLoading();
    bool success = false;
    state = await AsyncValue.guard(() async {
      final workOrder = await supabase
          .from(AppConstants.tWorkOrders)
          .insert(data)
          .select('id')
          .single();

      final workOrderId = workOrder['id'] as String;

      if (assignedProfileIds.isNotEmpty) {
        await supabase.from(AppConstants.tWorkOrderAssignments).insert(
              assignedProfileIds
                  .map(
                    (profileId) => {
                      'work_order_id': workOrderId,
                      'profile_id': profileId,
                      'role': 'tech',
                    },
                  )
                  .toList(),
            );
      }

      _ref.invalidate(workOrdersProvider);
      _ref.invalidate(workOrderByIdProvider(workOrderId));
      _ref.invalidate(workOrderAssignmentsProvider(workOrderId));
      _ref.invalidate(workOrderAssignmentNamesProvider(workOrderId));
      success = true;
    });
    return success;
  }

  Future<bool> updateStatus(String id, WorkOrderStatus status) async {
    state = const AsyncLoading();
    bool success = false;
    state = await AsyncValue.guard(() async {
      await supabase.from(AppConstants.tWorkOrders).update({
        'status': status.dbValue,
        if (status == WorkOrderStatus.closed)
          'completed_at': DateTime.now().toIso8601String(),
      }).eq('id', id);
      _ref.invalidate(workOrdersProvider);
      _ref.invalidate(workOrderByIdProvider(id));
      success = true;
    });
    return success;
  }

  Future<bool> updateWorkOrder(
    String id,
    Map<String, dynamic> data, {
    List<String>? assignedProfileIds,
  }) async {
    state = const AsyncLoading();
    bool success = false;
    state = await AsyncValue.guard(() async {
      await supabase.from(AppConstants.tWorkOrders).update(data).eq('id', id);

      if (assignedProfileIds != null) {
        await supabase
            .from(AppConstants.tWorkOrderAssignments)
            .delete()
            .eq('work_order_id', id);

        if (assignedProfileIds.isNotEmpty) {
          await supabase.from(AppConstants.tWorkOrderAssignments).insert(
                assignedProfileIds
                    .map(
                      (profileId) => {
                        'work_order_id': id,
                        'profile_id': profileId,
                        'role': 'tech',
                      },
                    )
                    .toList(),
              );
        }
      }

      _ref.invalidate(workOrdersProvider);
      _ref.invalidate(workOrderByIdProvider(id));
      _ref.invalidate(workOrderAssignmentsProvider(id));
      _ref.invalidate(workOrderAssignmentNamesProvider(id));
      success = true;
    });
    return success;
  }

  Future<bool> assignTo(String workOrderId, String userId) async {
    state = const AsyncLoading();
    bool success = false;
    state = await AsyncValue.guard(() async {
      await supabase.from(AppConstants.tWorkOrders).update({
        'assigned_to': userId,
        'status': WorkOrderStatus.assigned.dbValue,
      }).eq('id', workOrderId);
      _ref.invalidate(workOrdersProvider);
      _ref.invalidate(workOrderByIdProvider(workOrderId));
      success = true;
    });
    return success;
  }

  Future<bool> reopenStatus(String id) async {
    state = const AsyncLoading();
    bool success = false;
    state = await AsyncValue.guard(() async {
      await supabase.from(AppConstants.tWorkOrders).update({
        'status': WorkOrderStatus.inProgress.dbValue,
        'completed_at': null,
      }).eq('id', id);
      _ref.invalidate(workOrdersProvider);
      _ref.invalidate(workOrderByIdProvider(id));
      success = true;
    });
    return success;
  }
}

final workOrderControllerProvider =
    StateNotifierProvider<WorkOrderController, AsyncValue<void>>((ref) {
  return WorkOrderController(ref);
});

// Load employees for tech assignment
final employeesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final data = await supabase
      .from('profiles')
      .select('id, full_name')
      .eq('role', 'employee');
  return (data as List).cast<Map<String, dynamic>>();
});

// Load engines for a specific asset
final assetEnginesProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, assetId) async {
  final data = await supabase
      .from('asset_engines')
      .select('id, label, kind')
      .eq('asset_id', assetId);
  return (data as List).cast<Map<String, dynamic>>();
});

// Fetch asset name by ID
final assetNameProvider =
    FutureProvider.family<String?, String>((ref, assetId) async {
  final data = await supabase
      .from(AppConstants.tAssets)
      .select('name')
      .eq('id', assetId)
      .maybeSingle();
  return data?['name'] as String?;
});

// Fetch profile full_name by ID
final profileNameProvider =
    FutureProvider.family<String?, String>((ref, profileId) async {
  final data = await supabase
      .from(AppConstants.tProfiles)
      .select('full_name')
      .eq('id', profileId)
      .maybeSingle();
  return data?['full_name'] as String?;
});

final workOrderAssignmentsProvider =
    FutureProvider.family<List<WorkOrderAssignment>, String>((ref, workOrderId) async {
  final data = await supabase
      .from(AppConstants.tWorkOrderAssignments)
      .select()
      .eq('work_order_id', workOrderId)
      .order('created_at');

  return (data as List)
      .map((row) => WorkOrderAssignment.fromJson(row as Map<String, dynamic>))
      .toList();
});

final workOrderAssignmentNamesProvider =
    FutureProvider.family<List<String>, String>((ref, workOrderId) async {
  final assignments = await ref.watch(workOrderAssignmentsProvider(workOrderId).future);
  if (assignments.isEmpty) return const [];

  final ids = assignments.map((a) => a.profileId).toList();
  final rows = await supabase
      .from(AppConstants.tProfiles)
      .select('id, full_name')
      .inFilter('id', ids);

  final namesById = {
    for (final row in (rows as List).cast<Map<String, dynamic>>())
      row['id'] as String: (row['full_name'] as String?)?.trim() ?? 'Unnamed tech',
  };

  return ids.map((id) => namesById[id] ?? 'Unnamed tech').toList();
});
