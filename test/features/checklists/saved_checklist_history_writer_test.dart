import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/checklists/saved_checklist_history_writer.dart';
import 'package:vortice_app/features/checklists/saved_checklists_repository.dart';
import 'package:vortice_app/models/checklist_item.dart';
import 'package:vortice_app/models/checklist_template.dart';

void main() {
  group('SavedChecklistHistoryWriter', () {
    test('records maintenance work order history with canonical metadata',
        () async {
      final repository = _RecordingSavedChecklistsRepository();
      final writer = SavedChecklistHistoryWriter(repository);
      final submittedAt = DateTime.utc(2026, 5, 8, 12, 30);

      await writer.recordMaintenanceWorkOrderHistory(
        assetId: 'asset-1',
        clientId: 'client-1',
        workOrderId: 'wo-1',
        template: _template(checklistType: 'pm'),
        items: [_item()],
        responses: {'item-1': 'pass'},
        notes: {'item-1': 'looks good'},
        photoUrls: {'item-1': 'https://example.test/photo.jpg'},
        completedBy: 'staff-1',
        submittedByRole: 'technician',
        submittedAt: submittedAt,
        currentHours: 123.4,
        generalNotes: 'done',
      );

      expect(repository.calls, hasLength(1));
      expect(repository.calls.single, containsPair('sourceType', 'work_order'));
      expect(repository.calls.single,
          containsPair('checklistType', 'maintenance'));
      expect(repository.calls.single, containsPair('workOrderId', 'wo-1'));
      expect(
        repository.calls.single['extraHeader'],
        equals({'work_order_id': 'wo-1'}),
      );
      expect(repository.calls.single, containsPair('submittedAt', submittedAt));
      expect(repository.calls.single, containsPair('currentHours', 123.4));
    });

    test('records operations run history with canonical metadata', () async {
      final repository = _RecordingSavedChecklistsRepository();
      final writer = SavedChecklistHistoryWriter(repository);
      final submittedAt = DateTime.utc(2026, 5, 8, 13);

      await writer.recordOperationsRunHistory(
        assetId: 'asset-2',
        clientId: 'client-2',
        runId: 'run-1',
        runType: 'daily',
        template: _template(checklistType: 'operator_daily'),
        items: [_item()],
        responses: {'item-1': 'monitor'},
        notes: {'item-1': 'watch'},
        completedBy: 'operator-1',
        submittedByRole: 'operator',
        submittedAt: submittedAt,
        currentHours: null,
        generalNotes: null,
      );

      expect(repository.calls, hasLength(1));
      expect(repository.calls.single, containsPair('sourceType', 'operator'));
      expect(
          repository.calls.single, containsPair('checklistType', 'operations'));
      expect(repository.calls.single,
          containsPair('photoUrls', const <String, String?>{}));
      expect(
        repository.calls.single['extraHeader'],
        equals({'run_id': 'run-1', 'run_type': 'daily'}),
      );
      expect(repository.calls.single, containsPair('submittedAt', submittedAt));
    });
  });
}

ChecklistTemplate _template({required String checklistType}) =>
    ChecklistTemplate(
      id: 'template-1',
      checklistType: checklistType,
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
    String? submittedByRole,
    DateTime? submittedAt,
    double? currentHours,
    String? generalNotes,
    String? workOrderId,
    String? assignmentId,
    Map<String, dynamic>? extraHeader,
  }) async {
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
