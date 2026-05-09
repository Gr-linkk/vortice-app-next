import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/models/service_reminder.dart';

// ── Reminder with joined asset name ────────────────────────────────────────

class ReminderWithAsset {
  final ServiceReminder reminder;
  final String assetName;
  final double currentHours;
  final String? checklistTemplateId;
  final String? serviceIntervalId;

  ReminderWithAsset({
    required this.reminder,
    required this.assetName,
    required this.currentHours,
    this.checklistTemplateId,
    this.serviceIntervalId,
  });

  double get hoursRemaining => reminder.dueAtHours - currentHours;

  String get urgency {
    if (hoursRemaining <= 0) return 'overdue';
    if (hoursRemaining <= 10) return 'dueSoon';
    if (hoursRemaining <= 50) return 'upcoming';
    return 'later';
  }

  bool get shouldShowOnClientMaintenanceDashboard => urgency != 'later';
}

// ── Fetch all reminders with asset info ────────────────────────────────────

final remindersProvider = FutureProvider<List<ReminderWithAsset>>((ref) async {
  final remote = await supabase
      .from(AppConstants.tServiceReminders)
      .select('*, assets!inner(name), asset_engines(current_hours)')
      .eq('acknowledged', false)
      .order('due_at_hours');

  final remoteRows = (remote as List).cast<Map<String, dynamic>>();
  final reminderTemplateIds = {
    for (final row in remoteRows)
      row['id'] as String: row['template_id'] as String?,
  };

  final reminders = remoteRows.map((json) {
    final assetData = json['assets'] as Map<String, dynamic>?;
    final engineData = json['asset_engines'] as Map<String, dynamic>?;

    final reminderJson = Map<String, dynamic>.from(json)
      ..remove('assets')
      ..remove('asset_engines');

    return ReminderWithAsset(
      reminder: ServiceReminder.fromJson(reminderJson),
      assetName: assetData?['name'] as String? ?? 'Unknown Asset',
      currentHours: (engineData?['current_hours'] as num?)?.toDouble() ?? 0,
      serviceIntervalId: json['service_interval_id'] as String?,
    );
  }).toList();

  // Fetch checklist_template_id for each reminder via asset_service_intervals.
  // Prefer the explicit service_interval link when present; fall back to the
  // older asset + interval_hours lookup for legacy rows.
  final enriched = await Future.wait(reminders.map((r) async {
    try {
      final serviceIntervalId = r.serviceIntervalId;
      String? templateId = reminderTemplateIds[r.reminder.id];

      if (templateId == null) {
        final rows = serviceIntervalId != null
            ? await supabase
                .from(AppConstants.tAssetServiceIntervals)
                .select('checklist_template_id')
                .eq('id', serviceIntervalId)
                .limit(1)
            : await supabase
                .from(AppConstants.tAssetServiceIntervals)
                .select('checklist_template_id')
                .eq('asset_id', r.reminder.assetId)
                .eq('interval_hours', r.reminder.intervalHours)
                .limit(1);
        templateId = rows.isNotEmpty
            ? rows.first['checklist_template_id'] as String?
            : null;
      }

      return ReminderWithAsset(
        reminder: r.reminder,
        assetName: r.assetName,
        currentHours: r.currentHours,
        checklistTemplateId: templateId,
        serviceIntervalId: r.serviceIntervalId,
      );
    } catch (_) {
      return r;
    }
  }));

  return enriched;
});

// ── Overdue/due-soon count for dashboard badge ─────────────────────────────

final reminderUrgentCountProvider = FutureProvider<int>((ref) async {
  final reminders = await ref.watch(remindersProvider.future);
  return reminders
      .where((r) => r.urgency == 'overdue' || r.urgency == 'dueSoon')
      .length;
});

// ── Reminder controller ────────────────────────────────────────────────────

class ReminderController extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;
  ReminderController(this._ref) : super(const AsyncData(null));

  Future<bool> acknowledgeReminder(String id) async {
    state = const AsyncLoading();
    bool success = false;
    state = await AsyncValue.guard(() async {
      await supabase
          .from(AppConstants.tServiceReminders)
          .update({'acknowledged': true}).eq('id', id);
      _ref.invalidate(remindersProvider);
      _ref.invalidate(reminderUrgentCountProvider);
      success = true;
    });
    return success;
  }
}

final reminderControllerProvider =
    StateNotifierProvider<ReminderController, AsyncValue<void>>((ref) {
  return ReminderController(ref);
});
