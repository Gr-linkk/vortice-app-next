import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/checklists/checklist_submission_orchestrator.dart';
import 'package:vortice_app/features/checklists/saved_checklist_history_writer.dart';
import 'package:vortice_app/features/checklists/saved_checklists_repository.dart';
import 'package:vortice_app/models/checklist_item.dart';
import 'package:vortice_app/models/checklist_template.dart';

void main() {
  group('MaintenanceChecklistSubmission', () {
    test(
      'records inspection history without inferring service completion',
      () async {
        final events = <String>[];
        final repository = _RecordingSavedChecklistsRepository(events);
        final submission = MaintenanceChecklistSubmission(
          submitResponses:
              ({
                required workOrderId,
                required completedBy,
                required responses,
                notes,
                photoUrls,
                holdForSyncReason,
              }) async {
                events.add('responses');
              },
          hasChecklistSubmitError: () => false,
          historyWriter: SavedChecklistHistoryWriter(repository),
        );

        await submission.submit(
          workOrderId: 'wo-1',
          assetId: 'asset-1',
          clientId: 'client-1',
          template: _template(),
          loadItems: () async {
            events.add('load-items');
            return [_item()];
          },
          completedBy: 'staff-1',
          submittedByRole: 'technician',
          submittedAt: DateTime.utc(2026, 5, 8, 12),
          responses: {'item-1': 'pass'},
          notes: {'item-1': 'ok'},
          photoUrls: {'item-1': 'photo-url'},
          currentHours: 123,
          generalNotes: 'done',
          holdForSyncReason: null,
        );

        expect(events, ['responses', 'load-items', 'history']);
        expect(
          repository.calls.single,
          containsPair('sourceType', 'work_order'),
        );
        expect(repository.calls.single, containsPair('workOrderId', 'wo-1'));
      },
    );

    test('preserves the reported meter in inspection history', () async {
      final events = <String>[];
      final repository = _RecordingSavedChecklistsRepository(events);
      final submission = MaintenanceChecklistSubmission(
        submitResponses:
            ({
              required workOrderId,
              required completedBy,
              required responses,
              notes,
              photoUrls,
              holdForSyncReason,
            }) async {
              events.add('responses');
            },
        hasChecklistSubmitError: () => false,
        historyWriter: SavedChecklistHistoryWriter(repository),
      );

      await submission.submit(
        workOrderId: 'wo-1',
        assetId: 'asset-1',
        clientId: 'client-1',
        template: _template(),
        loadItems: () async => [_item()],
        completedBy: 'staff-1',
        submittedByRole: 'technician',
        submittedAt: DateTime.utc(2026, 5, 8, 12),
        responses: {'item-1': 'pass'},
        notes: const {},
        photoUrls: const {},
        currentHours: 123,
        generalNotes: null,
        holdForSyncReason: null,
      );

      expect(repository.calls.single, containsPair('currentHours', 123.0));
      expect(events, ['responses', 'history']);
    });

    test('does not write history when response submit fails', () async {
      final events = <String>[];
      final repository = _RecordingSavedChecklistsRepository(events);
      final submission = MaintenanceChecklistSubmission(
        submitResponses:
            ({
              required workOrderId,
              required completedBy,
              required responses,
              notes,
              photoUrls,
              holdForSyncReason,
            }) async {
              events.add('responses');
            },
        hasChecklistSubmitError: () => true,
        historyWriter: SavedChecklistHistoryWriter(repository),
      );

      await submission.submit(
        workOrderId: 'wo-1',
        assetId: 'asset-1',
        clientId: 'client-1',
        template: _template(),
        loadItems: () async {
          events.add('load-items');
          return [_item()];
        },
        completedBy: 'staff-1',
        submittedByRole: 'technician',
        submittedAt: DateTime.utc(2026, 5, 8, 12),
        responses: {'item-1': 'pass'},
        notes: const {},
        photoUrls: const {},
        currentHours: null,
        generalNotes: null,
        holdForSyncReason: 'offline',
      );

      expect(events, ['responses']);
      expect(repository.calls, isEmpty);
    });
  });

  group('ClientChecklistSubmission', () {
    test(
      'writes saved checklist history without PM completion or work order response writes',
      () async {
        final events = <String>[];
        final repository = _RecordingSavedChecklistsRepository(events);
        final submission = ClientChecklistSubmission(
          historyWriter: SavedChecklistHistoryWriter(repository),
        );

        await submission.submit(
          assetId: 'asset-1',
          clientId: 'client-1',
          submittedBy: 'client-user-1',
          submittedByRole: 'clientMechanic',
          template: _template(),
          items: [_item()],
          responses: {'item-1': 'pass'},
          notes: {'item-1': 'ok'},
          photoUrls: const {},
          submittedAt: DateTime.utc(2026, 5, 8, 14),
          currentHours: 789,
          generalNotes: 'client note',
        );

        expect(events, ['history']);
        expect(repository.calls.single, containsPair('sourceType', 'client'));
        expect(
          repository.calls.single,
          containsPair('checklistType', 'maintenance'),
        );
        expect(repository.calls.single, containsPair('workOrderId', null));
        expect(repository.calls.single['extraHeader'], {
          'client_submitted': true,
        });
      },
    );
  });

  group('OperationsChecklistSubmission', () {
    test('creates run and responses before saved operations history', () async {
      final events = <String>[];
      final repository = _RecordingSavedChecklistsRepository(events);
      final submission = OperationsChecklistSubmission(
        createRun:
            ({
              required assetId,
              required operatorId,
              required templateId,
              required runType,
              required completedAt,
            }) async {
              events.add('run:$assetId:$templateId:$operatorId');
              return const OperationsChecklistRunRecord(
                id: 'run-1',
                clientId: 'run-client',
              );
            },
        insertResponses:
            ({required runId, required responses, required notes}) async {
              events.add('responses:$runId');
            },
        historyWriter: SavedChecklistHistoryWriter(repository),
      );

      await submission.submit(
        assetId: 'asset-1',
        assetClientId: null,
        operatorId: 'operator-1',
        submittedByRole: 'operator',
        runType: 'pre_departure',
        template: _template(),
        items: [_item()],
        responses: {'item-1': 'monitor'},
        notes: {'item-1': 'watch'},
        submittedAt: DateTime.utc(2026, 5, 8, 13),
        currentHours: 456,
        generalNotes: 'ops note',
      );

      expect(events, [
        'run:asset-1:template-1:operator-1',
        'responses:run-1',
        'history',
      ]);
      expect(repository.calls.single, containsPair('sourceType', 'operator'));
      expect(repository.calls.single, containsPair('clientId', 'run-client'));
      expect(repository.calls.single['extraHeader'], {
        'run_id': 'run-1',
        'run_type': 'pre_departure',
      });
    });
  });
}

ChecklistTemplate _template() => const ChecklistTemplate(
  id: 'template-1',
  checklistType: 'pm',
  name: 'Template',
  version: 2,
);

ChecklistItem _item() => const ChecklistItem(
  id: 'item-1',
  templateId: 'template-1',
  descriptionEn: 'Inspect thing',
  sortOrder: 1,
);

class _RecordingSavedChecklistsRepository extends SavedChecklistsRepository {
  _RecordingSavedChecklistsRepository(this.events);

  final List<String> events;
  final calls = <Map<String, Object?>>[];

  @override
  Future<void> createSavedChecklist({
    required String assetId,
    required String clientId,
    required ChecklistTemplate template,
    required List<ChecklistItem> items,
    required Map<String, String?> responses,
    required Map<String, String> notes,
    required Map<String, String?> photoUrls,
    required String sourceType,
    required String checklistType,
    required String completedBy,
    String? completedByName,
    String? submittedByRole,
    DateTime? submittedAt,
    double? currentHours,
    String? generalNotes,
    String? workOrderId,
    String? assignmentId,
    Map<String, dynamic>? extraHeader,
  }) async {
    events.add('history');
    calls.add({
      'assetId': assetId,
      'clientId': clientId,
      'template': template,
      'items': items,
      'responses': responses,
      'notes': notes,
      'photoUrls': photoUrls,
      'sourceType': sourceType,
      'checklistType': checklistType,
      'completedBy': completedBy,
      'submittedByRole': submittedByRole,
      'submittedAt': submittedAt,
      'currentHours': currentHours,
      'generalNotes': generalNotes,
      'workOrderId': workOrderId,
      'assignmentId': assignmentId,
      'extraHeader': extraHeader,
    });
  }
}
