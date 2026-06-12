import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/service_intervals/service_interval_support.dart';
import 'package:vortice_app/models/asset_service_interval.dart';
import 'package:vortice_app/models/work_order.dart';

AssetServiceInterval _interval({
  required String id,
  int hours = 250,
  String? templateId,
  String? label,
}) {
  return AssetServiceInterval(
    id: id,
    assetId: 'asset-1',
    intervalHours: hours.toDouble(),
    checklistTemplateId: templateId,
    label: label,
  );
}

ServiceReminderRecord _reminder({
  required String id,
  String? intervalId,
  int hours = 250,
  double? dueAtHours,
  bool acknowledged = false,
}) {
  return ServiceReminderRecord(
    id: id,
    serviceIntervalId: intervalId,
    intervalHours: hours,
    dueAtHours: dueAtHours,
    acknowledged: acknowledged,
  );
}

void main() {
  group('pickReminderForInterval', () {
    test('prefers linked reminder over legacy interval-hours match', () {
      final picked = pickReminderForInterval(
        _interval(id: 'interval-1'),
        [
          _reminder(id: 'legacy', intervalId: null, dueAtHours: 200),
          _reminder(id: 'linked', intervalId: 'interval-1', dueAtHours: 500),
        ],
      );

      expect(picked?.id, 'linked');
    });

    test('prefers unacknowledged reminder with later due hours', () {
      final picked = pickReminderForInterval(
        _interval(id: 'interval-1'),
        [
          _reminder(
            id: 'old',
            intervalId: 'interval-1',
            dueAtHours: 250,
            acknowledged: true,
          ),
          _reminder(
            id: 'new',
            intervalId: 'interval-1',
            dueAtHours: 500,
            acknowledged: false,
          ),
        ],
      );

      expect(picked?.id, 'new');
    });
  });

  group('matchActiveWorkOrderForInterval', () {
    test('matches by checklist template id when configured', () {
      final match = matchActiveWorkOrderForInterval(
        interval: _interval(id: 'interval-1', templateId: 'tpl-1'),
        activeWorkOrders: [
          {
            'id': 'wo-1',
            'title': 'Other',
            'checklist_template_id': 'tpl-2',
          },
          {
            'id': 'wo-2',
            'title': '250h Service',
            'checklist_template_id': 'tpl-1',
          },
        ],
      );

      expect(match?['id'], 'wo-2');
    });

    test('falls back to generated title when no template id', () {
      final match = matchActiveWorkOrderForInterval(
        interval: _interval(id: 'interval-1', hours: 500, label: '500 HR'),
        activeWorkOrders: [
          {'id': 'wo-1', 'title': '500 HR', 'checklist_template_id': null},
        ],
      );

      expect(match?['id'], 'wo-1');
    });
  });

  group('computeNextDueHours', () {
    test('rolls due hours forward from previous due baseline', () {
      expect(
        computeNextDueHours(
          previousDueHours: 500,
          previousIntervalHours: 250,
          currentHours: 300,
          intervalHours: 250,
        ),
        500,
      );
    });

    test('uses explicit override when provided', () {
      expect(
        computeNextDueHours(
          previousDueHours: 500,
          previousIntervalHours: 250,
          currentHours: 300,
          intervalHours: 250,
          explicitNextDueHours: 750,
        ),
        750,
      );
    });
  });

  group('isActivePreventativeWorkOrderStatus', () {
    test('treats closed and invoiced work orders as inactive', () {
      expect(
        isActivePreventativeWorkOrderStatus(WorkOrderStatus.closed.dbValue),
        isFalse,
      );
      expect(
        isActivePreventativeWorkOrderStatus(WorkOrderStatus.invoiced.dbValue),
        isFalse,
      );
      expect(
        isActivePreventativeWorkOrderStatus(WorkOrderStatus.inProgress.dbValue),
        isTrue,
      );
    });
  });
}
