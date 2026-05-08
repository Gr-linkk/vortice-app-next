import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/assets/asset_workflow_summary.dart';
import 'package:vortice_app/features/service_intervals/service_interval_provider.dart';
import 'package:vortice_app/models/asset_service_interval.dart';
import 'package:vortice_app/models/saved_checklist.dart';
import 'package:vortice_app/models/service_request.dart';

void main() {
  group('Asset workflow summary helpers', () {
    test('selects the latest checklist by submitted date', () {
      final summary = latestChecklistSummary([
        _savedChecklist(
          id: 'older',
          templateName: '250h Service',
          submittedAt: DateTime.utc(2026, 5, 1),
        ),
        _savedChecklist(
          id: 'newer',
          templateName: '500h Service',
          submittedAt: DateTime.utc(2026, 5, 3),
        ),
      ]);

      expect(summary?.name, '500h Service');
      expect(summary?.submittedAt, DateTime.utc(2026, 5, 3));
    });

    test('returns null when no checklist history exists', () {
      expect(latestChecklistSummary([]), isNull);
    });

    test('summarizes due and overdue PM intervals only', () {
      final summary = duePmSummary([
        _intervalSummary(
          id: 'overdue',
          label: '250h Service',
          currentHours: 275,
          nextDueHours: 250,
        ),
        _intervalSummary(
          id: 'due-now',
          label: null,
          intervalHours: 500,
          currentHours: 500,
          nextDueHours: 500,
        ),
        _intervalSummary(
          id: 'future',
          label: '1000h Service',
          currentHours: 700,
          nextDueHours: 1000,
        ),
        _intervalSummary(
          id: 'unknown-hours',
          label: 'No meter',
          currentHours: null,
          nextDueHours: 1500,
        ),
      ]);

      expect(summary.visible, isTrue);
      expect(summary.dueOrOverdueCount, 2);
      expect(summary.labels, ['250h Service', '500h Service']);
    });

    test('counts only new service requests for the requested asset', () {
      final requests = [
        _serviceRequest(id: 'new-a', assetId: 'asset-a'),
        _serviceRequest(
          id: 'resolved-a',
          assetId: 'asset-a',
          status: ServiceRequestStatus.resolved,
        ),
        _serviceRequest(id: 'new-b', assetId: 'asset-b'),
        _serviceRequest(id: 'general', assetId: null),
      ];

      expect(countNewServiceRequestsForAsset(requests, 'asset-a'), 1);
    });
  });
}

SavedChecklist _savedChecklist({
  required String id,
  required String templateName,
  required DateTime submittedAt,
}) {
  return SavedChecklist(
    id: id,
    assetId: 'asset-a',
    clientId: 'client-a',
    templateName: templateName,
    checklistType: SavedChecklistType.maintenance,
    sourceType: 'staff',
    submittedAt: submittedAt,
    snapshot: const {},
  );
}

ServiceIntervalSummary _intervalSummary({
  required String id,
  required String? label,
  double intervalHours = 250,
  required double? currentHours,
  required double? nextDueHours,
}) {
  return ServiceIntervalSummary(
    interval: AssetServiceInterval(
      id: id,
      assetId: 'asset-a',
      intervalHours: intervalHours,
      label: label,
    ),
    currentHours: currentHours,
    nextDueHours: nextDueHours,
    sortIndex: 0,
  );
}

ServiceRequest _serviceRequest({
  required String id,
  required String? assetId,
  ServiceRequestStatus status = ServiceRequestStatus.newRequest,
}) {
  return ServiceRequest(
    id: id,
    clientId: 'client-a',
    assetId: assetId,
    title: 'Request',
    description: 'Needs attention',
    urgency: ServiceRequestUrgency.normal,
    status: status,
  );
}
