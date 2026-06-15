import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/service_intervals/preventative_maintenance_completion.dart';
import 'package:vortice_app/models/work_order.dart';

void main() {
  group('PreventativeMaintenanceCompletion', () {
    test('updates matching reminder and closes completed work order', () async {
      final store = _FakePreventativeMaintenanceCompletionStore(
        workOrder: {
          'id': 'wo-1',
          'asset_id': 'asset-1',
          'engine_id': 'engine-1',
          'checklist_template_id': 'template-1',
          'hours_at_end': 125,
        },
        interval: {'id': 'interval-1', 'interval_hours': 250},
        reminders: [
          {
            'id': 'reminder-1',
            'service_interval_id': 'interval-1',
            'interval_hours': 250,
            'due_at_hours': 250,
            'acknowledged': true,
          },
        ],
      );
      final invalidatedAssets = <String>[];
      final completion = PreventativeMaintenanceCompletion(
        store: store,
        invalidateServiceIntervalsForAsset: invalidatedAssets.add,
      );

      await completion.satisfyIntervalFromCompletedWorkOrder('wo-1');

      expect(store.calls, [
        'workOrder:wo-1',
        'interval:asset-1:template-1',
        'reminders:asset-1',
        'updateReminder:reminder-1',
        'closeWorkOrder:wo-1',
      ]);
      expect(store.updatedReminderValues, {
        'engine_id': 'engine-1',
        'service_interval_id': 'interval-1',
        'interval_hours': 250,
        'due_at_hours': 375.0,
        'acknowledged': false,
        'threshold_50hr_sent': false,
        'threshold_10hr_sent': false,
        'threshold_due_sent': false,
      });
      expect(invalidatedAssets, ['asset-1']);
    });

    test('uses telemetry before engine current hours fallback', () async {
      final store = _FakePreventativeMaintenanceCompletionStore(
        workOrder: {
          'id': 'wo-1',
          'asset_id': 'asset-1',
          'engine_id': 'engine-1',
          'checklist_template_id': 'template-1',
        },
        interval: {'id': 'interval-1', 'interval_hours': 100},
        telemetryHours: 55,
        engineCurrentHoursValue: 70,
      );
      final completion = PreventativeMaintenanceCompletion(store: store);

      await completion.satisfyIntervalFromCompletedWorkOrder('wo-1');

      expect(
          store.calls,
          containsAllInOrder([
            'telemetry:engine-1',
            'reminders:asset-1',
            'insertReminder',
            'closeWorkOrder:wo-1',
          ]));
      expect(store.calls, isNot(contains('engine:engine-1')));
      expect(store.insertedReminderValues, containsPair('due_at_hours', 155.0));
    });

    test('uses explicit completion hours before work order and engine sources',
        () async {
      final store = _FakePreventativeMaintenanceCompletionStore(
        workOrder: {
          'id': 'wo-1',
          'asset_id': 'asset-1',
          'engine_id': 'engine-1',
          'checklist_template_id': 'template-1',
          'hours_at_end': 900,
          'hours_at_start': 800,
        },
        interval: {'id': 'interval-1', 'interval_hours': 250},
        telemetryHours: 700,
        engineCurrentHoursValue: 600,
      );
      final completion = PreventativeMaintenanceCompletion(store: store);

      await completion.satisfyIntervalFromCompletedWorkOrder(
        'wo-1',
        completionHours: 125,
      );

      expect(store.calls, [
        'workOrder:wo-1',
        'interval:asset-1:template-1',
        'reminders:asset-1',
        'insertReminder',
        'closeWorkOrder:wo-1',
      ]);
      expect(store.insertedReminderValues, containsPair('due_at_hours', 375.0));
    });

    test('falls back to work order end hours when no explicit hours are given',
        () async {
      final store = _FakePreventativeMaintenanceCompletionStore(
        workOrder: {
          'id': 'wo-1',
          'asset_id': 'asset-1',
          'engine_id': 'engine-1',
          'checklist_template_id': 'template-1',
          'hours_at_end': 125,
          'hours_at_start': 100,
        },
        interval: {'id': 'interval-1', 'interval_hours': 250},
      );
      final completion = PreventativeMaintenanceCompletion(store: store);

      await completion.satisfyIntervalFromCompletedWorkOrder('wo-1');

      expect(store.insertedReminderValues, containsPair('due_at_hours', 375.0));
      expect(store.calls, isNot(contains('telemetry:engine-1')));
      expect(store.calls, isNot(contains('engine:engine-1')));
    });

    test('swallows store errors like the previous guarded controller workflow',
        () async {
      final store = _FakePreventativeMaintenanceCompletionStore(
        workOrderError: StateError('network gremlin'),
      );
      final completion = PreventativeMaintenanceCompletion(store: store);

      await expectLater(
        completion.satisfyIntervalFromCompletedWorkOrder('wo-1'),
        completes,
      );

      expect(store.calls, ['workOrder:wo-1']);
    });

    test('no-ops when no completion hours can be found', () async {
      final store = _FakePreventativeMaintenanceCompletionStore(
        workOrder: {
          'id': 'wo-1',
          'asset_id': 'asset-1',
          'engine_id': 'engine-1',
          'checklist_template_id': 'template-1',
        },
        interval: {'id': 'interval-1', 'interval_hours': 100},
      );
      final completion = PreventativeMaintenanceCompletion(store: store);

      await completion.satisfyIntervalFromCompletedWorkOrder('wo-1');

      expect(store.calls, [
        'workOrder:wo-1',
        'interval:asset-1:template-1',
        'telemetry:engine-1',
        'engine:engine-1',
      ]);
      expect(store.insertedReminderValues, isNull);
      expect(store.updatedReminderValues, isNull);
      expect(store.closedWorkOrderUpdate, isNull);
    });
  });
}

class _FakePreventativeMaintenanceCompletionStore
    implements PreventativeMaintenanceCompletionStore {
  _FakePreventativeMaintenanceCompletionStore({
    this.workOrder,
    this.interval,
    this.telemetryHours,
    this.engineCurrentHoursValue,
    this.workOrderError,
    List<Map<String, dynamic>>? reminders,
  }) : reminders = reminders ?? const [];

  final Map<String, dynamic>? workOrder;
  final Map<String, dynamic>? interval;
  final double? telemetryHours;
  final double? engineCurrentHoursValue;
  final Object? workOrderError;
  final List<Map<String, dynamic>> reminders;

  final calls = <String>[];
  Map<String, dynamic>? updatedReminderValues;
  Map<String, dynamic>? insertedReminderValues;
  Map<String, dynamic>? closedWorkOrderUpdate;

  @override
  Future<Map<String, dynamic>?> workOrderById(String workOrderId) async {
    calls.add('workOrder:$workOrderId');
    final error = workOrderError;
    if (error != null) throw error;
    return workOrder;
  }

  @override
  Future<Map<String, dynamic>?> matchingInterval({
    required String assetId,
    required String checklistTemplateId,
  }) async {
    calls.add('interval:$assetId:$checklistTemplateId');
    return interval;
  }

  @override
  Future<double?> latestTelemetryHours(String engineId) async {
    calls.add('telemetry:$engineId');
    return telemetryHours;
  }

  @override
  Future<double?> engineCurrentHours(String engineId) async {
    calls.add('engine:$engineId');
    return engineCurrentHoursValue;
  }

  @override
  Future<List<Map<String, dynamic>>> remindersForAsset(String assetId) async {
    calls.add('reminders:$assetId');
    return reminders;
  }

  @override
  Future<void> updateReminder({
    required String reminderId,
    required Map<String, dynamic> values,
  }) async {
    calls.add('updateReminder:$reminderId');
    updatedReminderValues = values;
  }

  @override
  Future<void> insertReminder(Map<String, dynamic> values) async {
    calls.add('insertReminder');
    insertedReminderValues = values;
  }

  @override
  Future<void> closeWorkOrder(String workOrderId) async {
    calls.add('closeWorkOrder:$workOrderId');
    closedWorkOrderUpdate = {
      'status': WorkOrderStatus.closed.dbValue,
      'workOrderId': workOrderId,
    };
  }
}
