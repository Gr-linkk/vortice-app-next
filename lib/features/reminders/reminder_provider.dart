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

  ReminderWithAsset({
    required this.reminder,
    required this.assetName,
    required this.currentHours,
    this.checklistTemplateId,
  });

  double get hoursRemaining => reminder.dueAtHours - currentHours;

  String get urgency {
    if (hoursRemaining <= 0) return 'overdue';
    if (hoursRemaining <= 10) return 'dueSoon';
    if (hoursRemaining <= 50) return 'upcoming';
    return 'later';
  }
}

// ── Fetch all reminders with asset info ────────────────────────────────────

final remindersProvider = FutureProvider<List<ReminderWithAsset>>((ref) async {
  final remote = await supabase
      .from(AppConstants.tServiceReminders)
      .select('*, assets!inner(name), asset_engines(current_hours)')
      .eq('acknowledged', false)
      .order('due_at_hours');

  final reminders = (remote as List).map((e) {
    final json = e as Map<String, dynamic>;
    final assetData = json['assets'] as Map<String, dynamic>?;
    final engineData = json['asset_engines'] as Map<String, dynamic>?;

    final reminderJson = Map<String, dynamic>.from(json)
      ..remove('assets')
      ..remove('asset_engines');

    return ReminderWithAsset(
      reminder: ServiceReminder.fromJson(reminderJson),
      assetName: assetData?['name'] as String? ?? 'Unknown Asset',
      currentHours: (engineData?['current_hours'] as num?)?.toDouble() ?? 0,
    );
  }).toList();

  // Fetch checklist_template_id for each reminder via asset_service_intervals
  final enriched = await Future.wait(reminders.map((r) async {
    try {
      final rows = await supabase
          .from(AppConstants.tAssetServiceIntervals)
          .select('checklist_template_id')
          .eq('asset_id', r.reminder.assetId)
          .eq('interval_hours', r.reminder.intervalHours)
          .limit(1);
      final templateId = rows.isNotEmpty
          ? (rows.first as Map<String, dynamic>)['checklist_template_id']
              as String?
          : null;
      return ReminderWithAsset(
        reminder: r.reminder,
        assetName: r.assetName,
        currentHours: r.currentHours,
        checklistTemplateId: templateId,
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
          .update({'acknowledged': true})
          .eq('id', id);
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
