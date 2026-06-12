import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/features/checklists/work_order_checklist_snapshot_repository.dart';
import 'package:vortice_app/features/work_orders/work_order_read_providers.dart';
import 'package:vortice_app/models/work_order.dart';

Future<void> trySyncChecklistSnapshot(
  String workOrderId,
  String? templateId,
) async {
  try {
    final payload =
        await workOrderChecklistSnapshotRepository.trySyncForWorkOrderTemplate(
      workOrderId: workOrderId,
      templateId: templateId,
    );
    final version = (payload?['template_version'] as num?)?.toInt();
    if (version != null) {
      await supabase
          .from(AppConstants.tWorkOrders)
          .update({'checklist_template_version': version}).eq(
        'id',
        workOrderId,
      );
    }
  } catch (_) {
    // Snapshot support is best-effort until every environment has the table.
  }
}

class WorkOrderController extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;
  WorkOrderController(this._ref) : super(const AsyncData(null));

  Future<String?> createWorkOrder(
    Map<String, dynamic> data, {
    List<String> assignedProfileIds = const [],
  }) async {
    state = const AsyncLoading();
    String? createdWorkOrderId;
    state = await AsyncValue.guard(() async {
      final workOrder = await supabase
          .from(AppConstants.tWorkOrders)
          .insert(data)
          .select('id')
          .single()
          .timeout(const Duration(seconds: 4));

      final workOrderId = workOrder['id'] as String;
      final engineId = data['engine_id'] as String?;
      final checklistTemplateId = data['checklist_template_id'] as String?;

      if (assignedProfileIds.isNotEmpty) {
        await supabase
            .from(AppConstants.tWorkOrderAssignments)
            .insert(
              assignedProfileIds
                  .map(
                    (profileId) => {
                      'work_order_id': workOrderId,
                      'profile_id': profileId,
                      'role': 'tech',
                    },
                  )
                  .toList(),
            )
            .timeout(const Duration(seconds: 4));
      }

      await trySyncChecklistSnapshot(workOrderId, checklistTemplateId);

      _ref.invalidate(workOrdersProvider);
      _ref.invalidate(workOrderByIdProvider(workOrderId));
      _ref.invalidate(workOrderAssignmentsProvider(workOrderId));
      _ref.invalidate(workOrderAssignmentNamesProvider(workOrderId));
      if (engineId != null) {
        _ref.invalidate(latestEngineHoursProvider(engineId));
      }
      createdWorkOrderId = workOrderId;
    });
    return createdWorkOrderId;
  }

  Future<bool> updateStatus(String id, WorkOrderStatus status) async {
    state = const AsyncLoading();
    bool success = false;
    state = await AsyncValue.guard(() async {
      await supabase
          .from(AppConstants.tWorkOrders)
          .update({
            'status': status.dbValue,
            if (status == WorkOrderStatus.closed)
              'completed_at': DateTime.now().toIso8601String(),
          })
          .eq('id', id)
          .timeout(const Duration(seconds: 4));

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
      final previous = await supabase
          .from(AppConstants.tWorkOrders)
          .select('engine_id')
          .eq('id', id)
          .maybeSingle();
      await supabase
          .from(AppConstants.tWorkOrders)
          .update(data)
          .eq('id', id)
          .timeout(const Duration(seconds: 4));

      final hasChecklistUpdate = data.containsKey('checklist_template_id');
      final nextChecklistTemplateId =
          hasChecklistUpdate ? data['checklist_template_id'] as String? : null;

      if (assignedProfileIds != null) {
        await supabase
            .from(AppConstants.tWorkOrderAssignments)
            .delete()
            .eq('work_order_id', id);

        if (assignedProfileIds.isNotEmpty) {
          await supabase
              .from(AppConstants.tWorkOrderAssignments)
              .insert(
                assignedProfileIds
                    .map(
                      (profileId) => {
                        'work_order_id': id,
                        'profile_id': profileId,
                        'role': 'tech',
                      },
                    )
                    .toList(),
              )
              .timeout(const Duration(seconds: 4));
        }
      }

      if (hasChecklistUpdate) {
        await trySyncChecklistSnapshot(id, nextChecklistTemplateId);
      }

      _ref.invalidate(workOrdersProvider);
      _ref.invalidate(workOrderByIdProvider(id));
      _ref.invalidate(workOrderAssignmentsProvider(id));
      _ref.invalidate(workOrderAssignmentNamesProvider(id));
      final previousEngineId = previous?['engine_id'] as String?;
      final nextEngineId = data['engine_id'] as String? ?? previousEngineId;
      if (previousEngineId != null) {
        _ref.invalidate(latestEngineHoursProvider(previousEngineId));
      }
      if (nextEngineId != null && nextEngineId != previousEngineId) {
        _ref.invalidate(latestEngineHoursProvider(nextEngineId));
      }
      success = true;
    });
    return success;
  }

  Future<bool> assignTo(String workOrderId, String userId) async {
    state = const AsyncLoading();
    bool success = false;
    state = await AsyncValue.guard(() async {
      await supabase
          .from(AppConstants.tWorkOrders)
          .update({
            'assigned_to': userId,
            'status': WorkOrderStatus.assigned.dbValue,
          })
          .eq('id', workOrderId)
          .timeout(const Duration(seconds: 4));
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
      await supabase
          .from(AppConstants.tWorkOrders)
          .update({
            'status': WorkOrderStatus.inProgress.dbValue,
            'completed_at': null,
          })
          .eq('id', id)
          .timeout(const Duration(seconds: 4));
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
