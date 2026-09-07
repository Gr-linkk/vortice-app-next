import 'package:vortice_app/core/retryable_rpc.dart';
import 'package:vortice_app/features/service_requests/service_request_provider.dart';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/features/work_orders/work_order_read_providers.dart';
import 'package:vortice_app/models/work_order.dart';

class WorkOrderController extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;
  WorkOrderController(this._ref) : super(const AsyncData(null));

  Future<String?> createWorkOrder(
    Map<String, dynamic> data, {
    List<String> assignedProfileIds = const [],
    String? serviceRequestId,
  }) async {
    state = const AsyncLoading();
    String? createdWorkOrderId;
    state = await AsyncValue.guard(() async {
      final workOrderId =
          await authenticatedRetryableRpc().call('save_provider_work_order', {
                'p_data': data,
                'p_assignees': assignedProfileIds,
                'p_request': serviceRequestId,
              })
              as String;
      final engineId = data['engine_id'] as String?;
      _ref.invalidate(clientServiceRequestsProvider);
      _ref.invalidate(staffServiceRequestsProvider);
      _ref.invalidate(newServiceRequestCountProvider);

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
    DateTime? expectedUpdatedAt,
  }) async {
    state = const AsyncLoading();
    bool success = false;
    state = await AsyncValue.guard(() async {
      final previous = await supabase
          .from(AppConstants.tWorkOrders)
          .select('engine_id,updated_at')
          .eq('id', id)
          .maybeSingle();
      if (assignedProfileIds != null) {
        await authenticatedRetryableRpc().call('save_provider_work_order', {
          'p_work_order': id,
          'p_data': data,
          'p_assignees': assignedProfileIds,
          'p_expected_updated_at':
              expectedUpdatedAt?.toUtc().toIso8601String() ??
              previous?['updated_at'],
        });
      } else {
        // A single replacement write remains atomic for the existing hours form.
        // Select the result so revoked access cannot masquerade as a saved edit.
        await supabase
            .from(AppConstants.tWorkOrders)
            .update(data)
            .eq('id', id)
            .select('id')
            .single()
            .timeout(const Duration(seconds: 10));
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
    return updateWorkOrder(
      workOrderId,
      {'assigned_to': userId},
      assignedProfileIds: [userId],
    );
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
