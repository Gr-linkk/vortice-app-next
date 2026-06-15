import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/features/service_intervals/service_interval_provider.dart';
import 'package:vortice_app/models/asset_service_interval.dart';
import 'package:vortice_app/models/work_order.dart';

final preventativeMaintenanceCompletionProvider =
    Provider<PreventativeMaintenanceCompletion>((ref) {
  return PreventativeMaintenanceCompletion(
    store: SupabasePreventativeMaintenanceCompletionStore(),
    invalidateServiceIntervalsForAsset: (assetId) {
      ref.invalidate(serviceIntervalsProvider(assetId));
      ref.invalidate(serviceIntervalSummariesProvider(assetId));
    },
  );
});

abstract class PreventativeMaintenanceCompletionStore {
  Future<Map<String, dynamic>?> workOrderById(String workOrderId);

  Future<Map<String, dynamic>?> matchingInterval({
    required String assetId,
    required String checklistTemplateId,
  });

  Future<double?> latestTelemetryHours(String engineId);

  Future<double?> engineCurrentHours(String engineId);

  Future<List<Map<String, dynamic>>> remindersForAsset(String assetId);

  Future<void> updateReminder({
    required String reminderId,
    required Map<String, dynamic> values,
  });

  Future<void> insertReminder(Map<String, dynamic> values);

  Future<void> closeWorkOrder(String workOrderId);
}

class SupabasePreventativeMaintenanceCompletionStore
    implements PreventativeMaintenanceCompletionStore {
  @override
  Future<Map<String, dynamic>?> workOrderById(String workOrderId) async {
    return await supabase
        .from(AppConstants.tWorkOrders)
        .select(
            'id, asset_id, engine_id, checklist_template_id, hours_at_start, hours_at_end')
        .eq('id', workOrderId)
        .maybeSingle();
  }

  @override
  Future<Map<String, dynamic>?> matchingInterval({
    required String assetId,
    required String checklistTemplateId,
  }) async {
    final intervalRows = await supabase
        .from(AppConstants.tAssetServiceIntervals)
        .select('id, interval_hours')
        .eq('asset_id', assetId)
        .eq('checklist_template_id', checklistTemplateId)
        .limit(1);
    return (intervalRows as List).cast<Map<String, dynamic>>().firstOrNull;
  }

  @override
  Future<double?> latestTelemetryHours(String engineId) async {
    final telemetry = await supabase
        .from(AppConstants.tTelemetryReadings)
        .select('engine_hours')
        .eq('engine_id', engineId)
        .order('ts', ascending: false)
        .limit(1)
        .maybeSingle();
    return (telemetry?['engine_hours'] as num?)?.toDouble();
  }

  @override
  Future<double?> engineCurrentHours(String engineId) async {
    final engine = await supabase
        .from(AppConstants.tAssetEngines)
        .select('current_hours')
        .eq('id', engineId)
        .maybeSingle();
    return (engine?['current_hours'] as num?)?.toDouble();
  }

  @override
  Future<List<Map<String, dynamic>>> remindersForAsset(String assetId) async {
    final reminderRows = await supabase
        .from(AppConstants.tServiceReminders)
        .select(
            'id, service_interval_id, interval_hours, due_at_hours, acknowledged')
        .eq('asset_id', assetId);
    return (reminderRows as List).cast<Map<String, dynamic>>().toList();
  }

  @override
  Future<void> updateReminder({
    required String reminderId,
    required Map<String, dynamic> values,
  }) async {
    await supabase
        .from(AppConstants.tServiceReminders)
        .update(values)
        .eq('id', reminderId)
        .timeout(const Duration(seconds: 4));
  }

  @override
  Future<void> insertReminder(Map<String, dynamic> values) async {
    await supabase
        .from(AppConstants.tServiceReminders)
        .insert(values)
        .timeout(const Duration(seconds: 4));
  }

  @override
  Future<void> closeWorkOrder(String workOrderId) async {
    await supabase
        .from(AppConstants.tWorkOrders)
        .update({
          'status': WorkOrderStatus.closed.dbValue,
          'completed_at': DateTime.now().toIso8601String(),
        })
        .eq('id', workOrderId)
        .timeout(const Duration(seconds: 4));
  }
}

class PreventativeMaintenanceCompletion {
  const PreventativeMaintenanceCompletion({
    required PreventativeMaintenanceCompletionStore store,
    void Function(String assetId)? invalidateServiceIntervalsForAsset,
  })  : _store = store,
        _invalidateServiceIntervalsForAsset =
            invalidateServiceIntervalsForAsset;

  final PreventativeMaintenanceCompletionStore _store;
  final void Function(String assetId)? _invalidateServiceIntervalsForAsset;

  Future<void> satisfyIntervalFromCompletedWorkOrder(
    String workOrderId, {
    double? completionHours,
  }) async {
    try {
      await _satisfyIntervalFromCompletedWorkOrder(
        workOrderId,
        completionHours: completionHours,
      );
    } catch (_) {
      // Preserve the old ServiceIntervalController AsyncValue.guard behavior:
      // PM completion failures are captured by the workflow and do not throw
      // back into checklist submission.
    }
  }

  Future<void> _satisfyIntervalFromCompletedWorkOrder(
    String workOrderId, {
    double? completionHours,
  }) async {
    final workOrder = await _store.workOrderById(workOrderId);
    if (workOrder == null) return;

    final assetId = workOrder['asset_id'] as String?;
    final checklistTemplateId = workOrder['checklist_template_id'] as String?;
    if (assetId == null || checklistTemplateId == null) return;

    final interval = await _store.matchingInterval(
      assetId: assetId,
      checklistTemplateId: checklistTemplateId,
    );
    if (interval == null) return;

    final intervalHours =
        ((interval['interval_hours'] as num?)?.toDouble() ?? 0).toInt();
    final engineId = workOrder['engine_id'] as String?;

    completionHours ??= (workOrder['hours_at_end'] as num?)?.toDouble();
    completionHours ??= (workOrder['hours_at_start'] as num?)?.toDouble();

    if (engineId != null) {
      completionHours ??= await _store.latestTelemetryHours(engineId);
    }

    if (engineId != null) {
      completionHours ??= await _store.engineCurrentHours(engineId);
    }

    if (completionHours == null) return;

    final reminder = _pickReminderForInterval(
      AssetServiceInterval(
        id: interval['id'] as String,
        assetId: assetId,
        intervalHours: intervalHours.toDouble(),
      ),
      (await _store.remindersForAsset(assetId))
          .map(_ServiceReminderRecord.fromRow)
          .toList(),
    );
    final nextDueHours = completionHours + intervalHours.toDouble();

    if (reminder != null) {
      await _store.updateReminder(
        reminderId: reminder.id,
        values: {
          'engine_id': engineId,
          'service_interval_id': interval['id'],
          'interval_hours': intervalHours,
          'due_at_hours': nextDueHours,
          'acknowledged': false,
          'threshold_50hr_sent': false,
          'threshold_10hr_sent': false,
          'threshold_due_sent': false,
        },
      );
    } else {
      await _store.insertReminder({
        'asset_id': assetId,
        'engine_id': engineId,
        'service_interval_id': interval['id'],
        'interval_hours': intervalHours,
        'due_at_hours': nextDueHours,
        'acknowledged': false,
      });
    }

    await _store.closeWorkOrder(workOrderId);

    _invalidateServiceIntervalsForAsset?.call(assetId);
  }
}

class _ServiceReminderRecord {
  final String id;
  final String? serviceIntervalId;
  final int intervalHours;
  final double? dueAtHours;
  final bool acknowledged;

  const _ServiceReminderRecord({
    required this.id,
    required this.serviceIntervalId,
    required this.intervalHours,
    required this.dueAtHours,
    required this.acknowledged,
  });

  factory _ServiceReminderRecord.fromRow(Map<String, dynamic> row) {
    return _ServiceReminderRecord(
      id: row['id'] as String,
      serviceIntervalId: row['service_interval_id'] as String?,
      intervalHours: ((row['interval_hours'] as num?)?.toDouble() ?? 0).toInt(),
      dueAtHours: (row['due_at_hours'] as num?)?.toDouble(),
      acknowledged: row['acknowledged'] as bool? ?? false,
    );
  }
}

_ServiceReminderRecord? _pickReminderForInterval(
  AssetServiceInterval interval,
  List<_ServiceReminderRecord> reminders,
) {
  _ServiceReminderRecord? linkedReminder;
  _ServiceReminderRecord? legacyReminder;

  for (final reminder in reminders) {
    if (reminder.serviceIntervalId == interval.id) {
      if (linkedReminder == null ||
          (linkedReminder.acknowledged && !reminder.acknowledged) ||
          ((linkedReminder.acknowledged == reminder.acknowledged) &&
              (reminder.dueAtHours ?? double.negativeInfinity) >
                  (linkedReminder.dueAtHours ?? double.negativeInfinity))) {
        linkedReminder = reminder;
      }
      continue;
    }

    if (reminder.serviceIntervalId == null &&
        reminder.intervalHours == interval.intervalHours.toInt()) {
      if (legacyReminder == null ||
          (legacyReminder.acknowledged && !reminder.acknowledged) ||
          ((legacyReminder.acknowledged == reminder.acknowledged) &&
              (reminder.dueAtHours ?? double.negativeInfinity) >
                  (legacyReminder.dueAtHours ?? double.negativeInfinity))) {
        legacyReminder = reminder;
      }
    }
  }

  return linkedReminder ?? legacyReminder;
}
