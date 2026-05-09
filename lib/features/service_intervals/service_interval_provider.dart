import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/models/asset_service_interval.dart';
import 'package:vortice_app/models/work_order.dart';

// ── Fetch intervals for a specific asset ─────────────────────────────────────

final serviceIntervalsProvider =
    FutureProvider.family<List<AssetServiceInterval>, String>(
        (ref, assetId) async {
  final data = await supabase
      .from(AppConstants.tAssetServiceIntervals)
      .select()
      .eq('asset_id', assetId)
      .order('interval_hours');
  return (data as List).map((e) {
    final row = Map<String, dynamic>.from(e as Map<String, dynamic>);
    if (row.containsKey('interval_label')) {
      row['label'] = row['interval_label'];
    }
    if (row.containsKey('is_active')) {
      row['enabled'] = row['is_active'];
    }
    return AssetServiceInterval.fromJson(row);
  }).toList();
});

double? _hoursFromWorkOrder(Map<String, dynamic>? row) {
  if (row == null) return null;
  return (row['hours_at_end'] as num?)?.toDouble() ??
      (row['hours_at_start'] as num?)?.toDouble();
}

Future<double?> _latestKnownHours(String assetId) async {
  final workOrders = await supabase
      .from(AppConstants.tWorkOrders)
      .select('hours_at_start, hours_at_end, updated_at, created_at')
      .eq('asset_id', assetId)
      .order('updated_at', ascending: false)
      .order('created_at', ascending: false)
      .limit(25);

  for (final row in (workOrders as List).cast<Map<String, dynamic>>()) {
    final hours = _hoursFromWorkOrder(row);
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

class ServiceIntervalSummary {
  final AssetServiceInterval interval;
  final double? currentHours;
  final double? nextDueHours;
  final String? activeWorkOrderId;
  final int sortIndex;

  const ServiceIntervalSummary({
    required this.interval,
    this.currentHours,
    this.nextDueHours,
    this.activeWorkOrderId,
    required this.sortIndex,
  });

  double? get lastServiceHours =>
      nextDueHours == null ? null : nextDueHours! - interval.intervalHours;

  double? get hoursRemaining => nextDueHours == null || currentHours == null
      ? null
      : nextDueHours! - currentHours!;
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
  List<_ServiceReminderRecord> reminders, {
  int? previousIntervalHours,
}) {
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
        reminder.intervalHours ==
            (previousIntervalHours ?? interval.intervalHours.toInt())) {
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
      .map(_ServiceReminderRecord.fromRow)
      .toList();

  final workOrdersRows = await supabase
      .from(AppConstants.tWorkOrders)
      .select('id, title, status, checklist_template_id, job_type')
      .eq('asset_id', assetId)
      .eq('job_type', WorkOrderJobType.preventative.dbValue)
      .order('created_at', ascending: false);

  final activeWorkOrders =
      (workOrdersRows as List).cast<Map<String, dynamic>>().where((row) {
    final status = row['status'] as String?;
    return status != WorkOrderStatus.closed.dbValue &&
        status != WorkOrderStatus.invoiced.dbValue;
  }).toList();

  final summaries = intervals.asMap().entries.map((entry) {
    final index = entry.key;
    final interval = entry.value;
    final reminder = _pickReminderForInterval(interval, reminders);
    final nextDueHours = reminder?.dueAtHours;
    final fallbackTitle =
        interval.label ?? '${interval.intervalHours.toInt()}h Service';

    final activeWorkOrder = activeWorkOrders.where((row) {
      final templateId = row['checklist_template_id'] as String?;
      final title = row['title'] as String?;
      if (interval.checklistTemplateId != null) {
        return templateId == interval.checklistTemplateId;
      }
      return title == fallbackTitle;
    }).firstOrNull;

    return ServiceIntervalSummary(
      interval: interval,
      currentHours: currentHours,
      nextDueHours: nextDueHours,
      activeWorkOrderId: activeWorkOrder?['id'] as String?,
      sortIndex: index,
    );
  }).toList();

  summaries.sort((a, b) {
    final hoursCompare = a.interval.intervalHours.compareTo(
      b.interval.intervalHours,
    );
    if (hoursCompare != 0) return hoursCompare;

    final aLabel = a.interval.label ?? '';
    final bLabel = b.interval.label ?? '';
    final labelCompare = aLabel.compareTo(bLabel);
    if (labelCompare != 0) return labelCompare;

    return a.sortIndex.compareTo(b.sortIndex);
  });

  return summaries;
});

// ── CRUD controller ───────────────────────────────────────────────────────────

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

    final existing = _pickReminderForInterval(
      AssetServiceInterval(
        id: intervalId,
        assetId: assetId,
        intervalHours: intervalHours.toDouble(),
      ),
      (existingRows as List)
          .cast<Map<String, dynamic>>()
          .map(_ServiceReminderRecord.fromRow)
          .toList(),
      previousIntervalHours: previousIntervalHours,
    );
    final previousHours = previousIntervalHours ?? intervalHours;
    final previousDueHours = existing?.dueAtHours;
    final lastServiceHours = previousDueHours == null
        ? currentHours
        : previousDueHours - previousHours.toDouble();
    final nextDueHours =
        explicitNextDueHours ?? (lastServiceHours + intervalHours.toDouble());

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
        final matchingReminder = _pickReminderForInterval(
          AssetServiceInterval(
            id: id,
            assetId: assetId,
            intervalHours: intervalHours.toDouble(),
          ),
          (reminderRows as List)
              .cast<Map<String, dynamic>>()
              .map(_ServiceReminderRecord.fromRow)
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
