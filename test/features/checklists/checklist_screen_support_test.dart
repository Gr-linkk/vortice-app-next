import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/checklists/checklist_attachment_support.dart';
import 'package:vortice_app/features/checklists/checklist_screen_support.dart';
import 'package:vortice_app/features/checklists/work_order_checklist_snapshot_repository.dart';
import 'package:vortice_app/models/checklist_item.dart';
import 'package:vortice_app/models/checklist_response.dart';
import 'package:vortice_app/models/checklist_template.dart';
import 'package:vortice_app/sync/sync_status.dart';

ChecklistTemplate _template({required String id, String name = 'PM'}) {
  return ChecklistTemplate(
    id: id,
    name: name,
    category: 'maintenance',
  );
}

WorkOrderChecklistSnapshot _snapshot({
  required String templateId,
  List<ChecklistItem> items = const [],
}) {
  return WorkOrderChecklistSnapshot(
    workOrderId: 'wo-1',
    templateId: templateId,
    templateVersion: 2,
    templateName: '250 HR',
    templateDescription: null,
    checklistType: 'pm',
    assetTypeId: 'type-a',
    intervalHours: 250,
    intervalLabel: '250 HR',
    items: items,
  );
}

void main() {
  group('savedResponsesFromWorkOrder', () {
    test('maps saved responses and skips pending local photos', () {
      final saved = savedResponsesFromWorkOrder([
        const ChecklistResponse(
          id: 'r-1',
          workOrderId: 'wo-1',
          checklistItemId: 'item-1',
          completed: true,
          notes: 'looks good',
          photoUrl: 'https://example.com/a.jpg',
        ),
        const ChecklistResponse(
          id: 'r-2',
          workOrderId: 'wo-1',
          checklistItemId: 'item-2',
          responseStatus: 'monitor',
          photoUrl: 'https://example.com/b.jpg',
          syncStatus: SyncStatusValues.pendingUpdate,
          lastError: 'upload failed',
        ),
      ]);

      expect(saved.responses, {
        'item-1': 'pass',
        'item-2': 'monitor',
      });
      expect(saved.notes, {'item-1': 'looks good'});
      expect(saved.photoUrls, {'item-1': 'https://example.com/a.jpg'});
    });
  });

  group('decodeChecklistDraftJson', () {
    test('restores draft fields and local photos', () {
      final restored = decodeChecklistDraftJson(
        {
          'templateId': 'tpl-1',
          'responses': {'item-1': 'pass'},
          'notes': {'item-1': 'note'},
          'photoUrls': {'item-1': 'https://example.com/old.jpg'},
          'photos': {
            'item-1': base64Encode([1, 2, 3])
          },
          'completedAt': '2026-06-03T10:00:00.000',
          'currentHours': 42,
          'generalNotes': 'draft',
        },
        fallbackCompletedAt: DateTime.utc(2026, 1, 1),
      );

      expect(restored.templateId, 'tpl-1');
      expect(restored.responses, {'item-1': 'pass'});
      expect(restored.photoUrls, isEmpty);
      expect(restored.photos['item-1'], [
        Uint8List.fromList([1, 2, 3])
      ]);
      expect(restored.restoredDraftPhotos, isTrue);
      expect(restored.completedAt, DateTime.parse('2026-06-03T10:00:00.000'));
    });
  });

  group('resolveChecklistTemplateSelection', () {
    test('prefers snapshot template when bound', () {
      final snapshot = _snapshot(templateId: 'snap-1');
      final selection = resolveChecklistTemplateSelection(
        currentSelected: null,
        currentDraftTemplateId: null,
        currentShowPicker: true,
        snapshot: snapshot,
        boundTemplateId: 'snap-1',
        templates: [_template(id: 'snap-1')],
      );

      expect(selection.selected?.id, 'snap-1');
      expect(selection.showPicker, isFalse);
    });

    test('falls back to bound template from catalog', () {
      final template = _template(id: 'tpl-2');
      final selection = resolveChecklistTemplateSelection(
        currentSelected: null,
        currentDraftTemplateId: null,
        currentShowPicker: true,
        snapshot: null,
        boundTemplateId: 'tpl-2',
        templates: [template],
      );

      expect(selection.selected, template);
      expect(selection.draftTemplateId, 'tpl-2');
    });
  });

  group('buildChecklistMetadataCaption', () {
    test('joins interval, version, and item count', () {
      final caption = buildChecklistMetadataCaption(
        snapshot: _snapshot(
          templateId: 'tpl-1',
          items: [
            const ChecklistItem(
              id: 'item-1',
              templateId: 'tpl-1',
              descriptionEn: 'Inspect filter',
              sortOrder: 1,
            ),
          ],
        ),
        snapshotItems: const [
          ChecklistItem(
            id: 'item-1',
            templateId: 'tpl-1',
            descriptionEn: 'Inspect filter',
            sortOrder: 1,
          ),
        ],
      );

      expect(caption, '250 HR • 250h • v2 • 1 items');
    });
  });

  group('uploadPendingChecklistPhotos', () {
    test('keeps existing urls when upload fails', () async {
      final failedBytes = Uint8List.fromList([9]);
      final result = await uploadPendingChecklistPhotos(
        photos: {
          'item-1': [failedBytes]
        },
        existingUrls: photoUrlListsFromLegacyMap(
          {'item-1': 'https://example.com/existing.jpg'},
        ),
        upload: (_, __) async => throw Exception('offline'),
      );

      expect(
        checklistPhotoUrlsForItem(result.urls, 'item-1'),
        ['https://example.com/existing.jpg'],
      );
      expect(result.remainingPhotos['item-1'], [failedBytes]);
      expect(result.deferredReason, contains('offline'));
    });

    test('appends uploaded urls without replacing existing ones', () async {
      final uploadedBytes = Uint8List.fromList([9]);
      final result = await uploadPendingChecklistPhotos(
        photos: {
          'item-1': [uploadedBytes]
        },
        existingUrls: {
          'item-1': ['https://example.com/existing.jpg']
        },
        upload: (_, __) async => 'https://example.com/new.jpg',
      );

      expect(
        checklistPhotoUrlsForItem(result.urls, 'item-1'),
        [
          'https://example.com/existing.jpg',
          'https://example.com/new.jpg',
        ],
      );
      expect(result.remainingPhotos, isEmpty);
    });

    test('keeps only failed bytes after partial upload failure', () async {
      final uploadedBytes = Uint8List.fromList([1]);
      final failedBytes = Uint8List.fromList([2]);
      var call = 0;

      final result = await uploadPendingChecklistPhotos(
        photos: {
          'item-1': [uploadedBytes, failedBytes]
        },
        existingUrls: const {},
        upload: (_, __) async {
          call += 1;
          if (call == 2) throw Exception('offline');
          return 'https://example.com/uploaded.jpg';
        },
      );

      expect(
        checklistPhotoUrlsForItem(result.urls, 'item-1'),
        ['https://example.com/uploaded.jpg'],
      );
      expect(result.remainingPhotos['item-1'], [failedBytes]);
      expect(hasDeferredChecklistPhotoUpload(result.deferredReason), isTrue);
      expect(hasDeferredChecklistPhotoUpload('  '), isFalse);
    });
  });

  group('photo cache codec', () {
    test('round-trips encoded photos', () {
      final encoded = encodePhotoCache({
        'item-1': [
          Uint8List.fromList([4, 5])
        ],
      });
      final decoded = decodePhotoCacheJson(jsonEncode(encoded));
      expect(decoded['item-1'], [
        Uint8List.fromList([4, 5])
      ]);
    });
  });
}
