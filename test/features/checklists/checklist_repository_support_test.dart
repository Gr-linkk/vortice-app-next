import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/checklists/checklist_repository_support.dart';
import 'package:vortice_app/models/checklist_item.dart';
import 'package:vortice_app/models/checklist_response.dart';
import 'package:vortice_app/sync/sync_status.dart';

ChecklistItem _item(String description) => ChecklistItem(
      id: 'item-1',
      templateId: 'tpl-1',
      descriptionEn: description,
    );

ChecklistResponse _response({
  required String itemId,
  String syncStatus = SyncStatusValues.synced,
  String? notes,
}) =>
    ChecklistResponse(
      id: 'resp-$itemId',
      workOrderId: 'wo-1',
      checklistItemId: itemId,
      syncStatus: syncStatus,
      notes: notes,
    );

void main() {
  group('isAllowedChecklistItem', () {
    test('filters signature and sign-off checklist items', () {
      expect(isAllowedChecklistItem(_item('Inspect pump')), isTrue);
      expect(isAllowedChecklistItem(_item('Client signature required')), isFalse);
      expect(isAllowedChecklistItem(_item('Customer sign-off')), isFalse);
    });
  });

  group('mergeResponsesPreferUnsynced', () {
    test('keeps local unsynced responses over remote copies', () {
      final merged = mergeResponsesPreferUnsynced(
        remoteResponses: [
          _response(itemId: 'item-1', notes: 'remote'),
          _response(itemId: 'item-2', notes: 'remote-2'),
        ],
        localResponses: [
          _response(
            itemId: 'item-1',
            syncStatus: SyncStatusValues.pendingUpdate,
            notes: 'local',
          ),
        ],
      );

      final byItem = {for (final row in merged) row.checklistItemId: row.notes};
      expect(byItem['item-1'], 'local');
      expect(byItem['item-2'], 'remote-2');
    });
  });

  group('remoteChecklistResponsesSafeToUpsert', () {
    test('skips remote rows that still have local pending edits', () {
      final safe = remoteChecklistResponsesSafeToUpsert(
        remoteResponses: [
          _response(itemId: 'item-1'),
          _response(itemId: 'item-2'),
        ],
        localUnsyncedByItem: {
          'item-1': _response(
            itemId: 'item-1',
            syncStatus: SyncStatusValues.pendingUpdate,
          ),
        },
      ).map((response) => response.checklistItemId).toList();

      expect(safe, ['item-2']);
    });
  });

  group('buildChecklistResponse', () {
    test('marks pass responses completed and omits blank notes', () {
      final response = buildChecklistResponse(
        id: 'resp-1',
        workOrderId: 'wo-1',
        checklistItemId: 'item-1',
        completedBy: 'tech-1',
        status: 'pass',
        completedAt: DateTime.utc(2026, 6, 3),
        notes: '',
      );

      expect(response.completed, isTrue);
      expect(response.responseStatus, 'pass');
      expect(response.notes, isNull);
    });
  });

  group('checklistResponseToRemoteRow', () {
    test('includes optional notes and photo url only when present', () {
      final row = checklistResponseToRemoteRow(
        buildChecklistResponse(
          id: 'resp-1',
          workOrderId: 'wo-1',
          checklistItemId: 'item-1',
          completedBy: 'tech-1',
          status: 'monitor',
          completedAt: DateTime.utc(2026, 6, 3),
          notes: 'watch',
          photoUrl: 'https://example.com/p.jpg',
        ),
      );

      expect(row['notes'], 'watch');
      expect(row['photo_url'], 'https://example.com/p.jpg');
      expect(row['completed'], isFalse);
    });
  });
}
