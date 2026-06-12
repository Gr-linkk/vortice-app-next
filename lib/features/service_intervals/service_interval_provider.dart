import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/features/service_intervals/service_interval_support.dart';
import 'package:vortice_app/models/asset_service_interval.dart';
import 'package:vortice_app/models/work_order.dart';

export 'package:vortice_app/features/service_intervals/service_interval_support.dart'
    show ServiceIntervalSummary;

final serviceIntervalsProvider =
    FutureProvider.family<List<AssetServiceInterval>, String>(
        (ref, assetId) async {
  final data = await supabase
      .from(AppConstants.tAssetServiceIntervals)
      .select()
      .eq('asset_id', assetId)
      .order('interval_hours');
  return (data as List).map((e) {
    return AssetServiceInterval.fromJson(
      normalizeServiceIntervalRow(Map<String, dynamic>.from(e as Map)),
    );
  }).toList();
});

Future<double?> _latestKnownHours(String assetId) async {
  final workOrders = await supabase
      .from(AppConstants.tWorkOrders)
      .select('hours_at_start, hours_at_end, updated_at, created_at')
      .eq('asset_id', assetId)
      .order('updated_at', ascending: false)
      .order('created_at', ascending: false)
      .limit(25);

  for (final row in (workOrders as List).cast<Map<String, dynamic>>()) {
    final hours = hoursFromWorkOrderRow(row);
    if (hours != null) return hours;
  }

  final engines = await supabase
      .from(AppConstants.tAssetEngines)
      .select('current_hours')
      .eq('asset_id', assetId)
      .order('label')
      .limit(1);
  final primaryEngine =
      (engines as List).cast<Map<String, dynamic>>().firstOrNull;
  return (primaryEngine?['current_hours'] as num?)?.toDouble();
}

final serviceIntervalSummariesProvider =
    FutureProvider.family<List<ServiceIntervalSummary>, String>(
        (ref, assetId) async {
  final intervals = await ref.watch(serviceIntervalsProvider(assetId).future);
  final currentHours = await _latestKnownHours(assetId);

  final remindersRows = await supabase
      .from(AppConstants.tServiceReminders)
      .select(
          'id, service_interval_id, interval_hours, due_at_hours, acknowledged')
      .eq('asset_id', assetId);
  final reminders = (remindersRows as List)
      .cast<Map<String, dynamic>>()
      .map(ServiceReminderRecord.fromRow)
      .toList();

  final workOrdersRows = await supabase
      .from(AppConstants.tWorkOrders)
      .select('id, title, status, checklist_template_id, job_type')
      .eq('asset_id', assetId)
      .eq('job_type', WorkOrderJobType.preventative.dbValue)
      .order('created_at', ascending: false);

  final activeWorkOrders =
      (workOrdersRows as List).cast<Map<String, dynamic>>().where((row) {
    return isActivePreventativeWorkOrderStatus(row['status'] as String?);
  }).toList();

  final summaries = intervals.asMap().entries.map((entry) {
    final index = entry.key;
    final interval = entry.value;
    final reminder = pickReminderForInterval(interval, reminders);
    final activeWorkOrder = matchActiveWorkOrderForInterval(
      interval: interval,
      activeWorkOrders: activeWorkOrders,
    );

    return ServiceIntervalSummary(
      interval: interval,
      currentHours: currentHours,
      nextDueHours: reminder?.dueAtHours,
      activeWorkOrderId: activeWorkOrder?['id'] as String?,
      sortIndex: index,
    );
  }).toList();

  summaries.sort(compareServiceIntervalSummaries);
  return summaries;
});

class ServiceIntervalController extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;
  String? lastError;

  ServiceIntervalController(this._ref) : super(const AsyncData(null));

  Future<void> _ensureReminder({
    required String assetId,
    required String intervalId,
    required int intervalHours,
    int? previousIntervalHours,
    double? explicitNextDueHours,
  }) async {
    final engines = await supabase
        .from(AppConstants.tAssetEngines)
        .select('id, current_hours')
        .eq('asset_id', assetId)
        .order('label');
    final primaryEngine =
        (engines as List).cast<Map<String, dynamic>>().firstOrNull;
    final engineId = primaryEngine?['id'] as String?;
    final currentHours = await _latestKnownHours(assetId) ??
        (primaryEngine?['current_hours'] as num?)?.toDouble() ??
        0;

    final existingRows = await supabase
        .from(AppConstants.tServiceReminders)
        .select(
            'id, service_interval_id, due_at_hours, interval_hours, acknowledged')
        .eq('asset_id', assetId);

    final existing = pickReminderForInterval(
      AssetServiceInterval(
        id: intervalId,
        assetId: assetId,
        intervalHours: intervalHours.toDouble(),
      ),
      (existingRows as List)
          .cast<Map<String, dynamic>>()
          .map(ServiceReminderRecord.fromRow)
          .toList(),
      previousIntervalHours: previousIntervalHours,
    );
    final previousHours = previousIntervalHours ?? intervalHours;
    final nextDueHours = computeNextDueHours(
      previousDueHours: existing?.dueAtHours,
      previousIntervalHours: previousHours,
      currentHours: currentHours,
      intervalHours: intervalHours,
      explicitNextDueHours: explicitNextDueHours,
    );

    if (existing != null) {
      await supabase.from(AppConstants.tServiceReminders).update({
        'engine_id': engineId,
        'service_interval_id': intervalId,
        'interval_hours': intervalHours,
        'due_at_hours': nextDueHours,
        'acknowledged': false,
        'threshold_50hr_sent': false,
        'threshold_10hr_sent': false,
        'threshold_due_sent': false,
      }).eq('id', existing.id);
      return;
    }

    await supabase.from(AppConstants.tServiceReminders).insert({
      'asset_id': assetId,
      'engine_id': engineId,
      'service_interval_id': intervalId,
      'interval_hours': intervalHours,
      'due_at_hours': nextDueHours,
      'acknowledged': false,
    });
  }

  Future<bool> createInterval({
    required String assetId,
    required int intervalHours,
    String? checklistTemplateId,
    String? label,
    double? nextDueHours,
  }) async {
    state = const AsyncLoading();
    lastError = null;
    bool success = false;
    state = await AsyncValue.guard(() async {
      try {
        final insertedInterval = await supabase
            .from(AppConstants.tAssetServiceIntervals)
            .insert({
              'asset_id': assetId,
              'interval_hours': intervalHours,
              if (label != null && label.trim().isNotEmpty)
                'interval_label': label.trim(),
              if (checklistTemplateId != null)
                'checklist_template_id': checklistTemplateId,
              'is_active': true,
            })
            .select('id')
            .single();
        await _ensureReminder(
          assetId: assetId,
          intervalId: insertedInterval['id'] as String,
          intervalHours: intervalHours,
          explicitNextDueHours: nextDueHours,
        );
        _ref.invalidate(serviceIntervalsProvider(assetId));
        _ref.invalidate(serviceIntervalSummariesProvider(assetId));
        success = true;
      } catch (e) {
        lastError = e.toString();
        rethrow;
      }
    });
    return success;
  }

  Future<bool> updateInterval(
    String id, {
    required String assetId,
    int? intervalHours,
    String? checklistTemplateId,
    bool clearChecklistTemplate = false,
    String? label,
    bool? enabled,
    double? nextDueHours,
  }) async {
    state = const AsyncLoading();
    lastError = null;
    bool success = false;
    state = await AsyncValue.guard(() async {
      try {
        final existing = await supabase
            .from(AppConstants.tAssetServiceIntervals)
            .select('interval_hours')
            .eq('id', id)
            .maybeSingle();
        final previousIntervalHours =
            ((existing?['interval_hours'] as num?)?.toDouble() ??
                    intervalHours?.toDouble() ??
                    0)
                .toInt();

        await supabase
            .from(AppConstants.tAssetServiceIntervals)
            .update({
              if (intervalHours != null) 'interval_hours': intervalHours,
              if (clearChecklistTemplate || checklistTemplateId != null)
                'checklist_template_id':
                    clearChecklistTemplate ? null : checklistTemplateId,
              if (label != null)
                'interval_label': label.trim().isEmpty ? null : label.trim(),
              if (enabled != null) 'is_active': enabled,
            })
            .eq('id', id)
            .timeout(const Duration(seconds: 4));
        await _ensureReminder(
          assetId: assetId,
          intervalId: id,
          intervalHours: intervalHours ?? previousIntervalHours,
          previousIntervalHours: previousIntervalHours,
          explicitNextDueHours: nextDueHours,
        );
        _ref.invalidate(serviceIntervalsProvider(assetId));
        _ref.invalidate(serviceIntervalSummariesProvider(assetId));
        success = true;
      } catch (e) {
        lastError = e.toString();
        rethrow;
      }
    });
    return success;
  }

  Future<bool> deleteInterval(String id, String assetId) async {
    state = const AsyncLoading();
    lastError = null;
    bool success = false;
    state = await AsyncValue.guard(() async {
      try {
        final existing = await supabase
            .from(AppConstants.tAssetServiceIntervals)
            .select('interval_hours')
            .eq('id', id)
            .maybeSingle();
        final intervalHours =
            ((existing?['interval_hours'] as num?)?.toDouble() ?? 0).toInt();

        final reminderRows = await supabase
            .from(AppConstants.tServiceReminders)
            .select(
                'id, service_interval_id, interval_hours, due_at_hours, acknowledged')
            .eq('asset_id', assetId);
        final matchingReminder = pickReminderForInterval(
          AssetServiceInterval(
            id: id,
            assetId: assetId,
            intervalHours: intervalHours.toDouble(),
          ),
          (reminderRows as List)
              .cast<Map<String, dynamic>>()
              .map(ServiceReminderRecord.fromRow)
              .toList(),
        );

        await supabase
            .from(AppConstants.tAssetServiceIntervals)
            .delete()
            .eq('id', id)
            .timeout(const Duration(seconds: 4));
        if (matchingReminder != null) {
          await supabase
              .from(AppConstants.tServiceReminders)
              .delete()
              .eq('id', matchingReminder.id)
              .timeout(const Duration(seconds: 4));
        } else if (intervalHours > 0) {
          await supabase
              .from(AppConstants.tServiceReminders)
              .delete()
              .eq('asset_id', assetId)
              .eq('interval_hours', intervalHours)
              .timeout(const Duration(seconds: 4));
        }
        _ref.invalidate(serviceIntervalsProvider(assetId));
        _ref.invalidate(serviceIntervalSummariesProvider(assetId));
        success = true;
      } catch (e) {
        lastError = e.toString();
        rethrow;
      }
    });
    return success;
  }
}

final serviceIntervalControllerProvider =
    StateNotifierProvider<ServiceIntervalController, AsyncValue<void>>((ref) {
  return ServiceIntervalController(ref);
});
