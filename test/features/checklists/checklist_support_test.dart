import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/checklists/checklist_support.dart';
import 'package:vortice_app/models/checklist_template.dart';
import 'package:vortice_app/sync/sync_status.dart';

void main() {
  group('checklist draft keys', () {
    test('builds stable draft and photo cache keys from run key', () {
      expect(checklistDraftKey('wo-1'), 'checklist_draft_wo-1');
      expect(checklistPhotoCacheKey('wo-1'), 'checklist_photo_cache_wo-1');
    });
  });

  group('checklistRunKey', () {
    test('uses work order id when present', () {
      expect(
        checklistRunKey(workOrderId: 'wo-1', assetId: 'asset-1'),
        'wo-1',
      );
    });

    test('falls back to asset prefix when no work order', () {
      expect(
        checklistRunKey(workOrderId: null, assetId: 'asset-1'),
        'asset_asset-1',
      );
    });
  });

  group('requiresAttentionDetail', () {
    test('returns false when monitor/action items have notes or photos', () {
      expect(
        requiresAttentionDetail(
          {'item-1': 'monitor'},
          {'item-1': 'needs follow-up'},
          {},
          {},
        ),
        isFalse,
      );
      expect(
        requiresAttentionDetail(
          {'item-1': 'action'},
          {},
          {
            'item-1': Uint8List.fromList([1, 2, 3])
          },
          {},
        ),
        isFalse,
      );
      expect(
        requiresAttentionDetail(
          {'item-1': 'alert'},
          {},
          {},
          {'item-1': 'https://example.com/photo.jpg'},
        ),
        isFalse,
      );
    });

    test('returns true when monitor/action items lack note and photo', () {
      expect(
        requiresAttentionDetail(
          {'item-1': 'monitor', 'item-2': 'pass'},
          {},
          {},
          {},
        ),
        isTrue,
      );
      expect(
        requiresAttentionDetail(
          {'item-1': 'action'},
          {'item-1': '   '},
          {},
          {},
        ),
        isTrue,
      );
    });

    test('ignores pass and n/a responses', () {
      expect(
        requiresAttentionDetail(
          {'item-1': 'pass', 'item-2': 'n/a'},
          {},
          {},
          {},
        ),
        isFalse,
      );
    });
  });

  group('formatChecklistDateTime', () {
    test('formats local date and time with zero padding', () {
      final formatted = formatChecklistDateTime(
        DateTime(2026, 6, 11, 9, 5),
      );
      expect(formatted, '2026-06-11 09:05');
    });
  });

  group('compareTemplatesByServiceHours', () {
    test('sorts by interval hours then name', () {
      final low = ChecklistTemplate(
        id: 'a',
        name: 'B Template',
        category: 'general',
        intervalHours: 100,
      );
      final high = ChecklistTemplate(
        id: 'b',
        name: 'A Template',
        category: 'general',
        intervalHours: 250,
      );
      final noHours = ChecklistTemplate(
        id: 'c',
        name: 'No Hours',
        category: 'general',
      );

      final sorted = [high, noHours, low]..sort(compareTemplatesByServiceHours);

      expect(sorted.map((t) => t.id), ['a', 'b', 'c']);
    });
  });

  group('syncStatusChipLabel', () {
    test('maps pending and failed statuses to labels', () {
      expect(
          syncStatusChipLabel(SyncStatusValues.pendingCreate), 'Pending sync');
      expect(
          syncStatusChipLabel(SyncStatusValues.pendingUpdate), 'Pending sync');
      expect(
          syncStatusChipLabel(SyncStatusValues.pendingDelete), 'Pending sync');
      expect(syncStatusChipLabel(SyncStatusValues.syncing), 'Pending sync');
      expect(syncStatusChipLabel(SyncStatusValues.failed), 'Sync failed');
      expect(syncStatusChipLabel(SyncStatusValues.conflict), 'Conflict');
      expect(syncStatusChipLabel(SyncStatusValues.synced), isNull);
      expect(syncStatusChipLabel(null), isNull);
    });
  });

  group('isVisibleChecklistSyncStatus', () {
    test('hides synced status only', () {
      expect(isVisibleChecklistSyncStatus(SyncStatusValues.synced), isFalse);
      expect(isVisibleChecklistSyncStatus(SyncStatusValues.failed), isTrue);
    });
  });

  group('checklist sync banner messages', () {
    test('summarizes row-level security errors', () {
      expect(
        checklistSyncBannerMessage(
          hasConflict: false,
          lastError:
              'PostgrestException(message: new row violates row-level security policy for table "checklist_responses", code: 42501)',
        ),
        'Sync blocked by server permissions. Retry after access is fixed.',
      );
    });

    test('keeps conflict message ahead of stored error', () {
      expect(
        checklistSyncBannerMessage(
          hasConflict: true,
          lastError: 'TimeoutException after 0:00:04.000000',
        ),
        'Checklist has sync conflicts.',
      );
    });

    test('uses pending message when no error exists', () {
      expect(
        checklistSyncBannerMessage(hasConflict: false, lastError: null),
        'Saved locally. Sync pending.',
      );
    });
  });

  group('encodeChecklistDraft', () {
    test('serializes draft fields including base64 photos', () {
      final draft = encodeChecklistDraft(
        templateId: 'tpl-1',
        responses: {'item-1': 'pass'},
        notes: {'item-1': 'note'},
        photoUrls: {'item-1': 'https://example.com/p.jpg'},
        completedAt: DateTime.utc(2026, 6, 11, 12, 0),
        currentHours: 42.5,
        generalNotes: 'all good',
        photos: {
          'item-1': Uint8List.fromList([10, 20])
        },
      );

      expect(draft['templateId'], 'tpl-1');
      expect(draft['responses'], {'item-1': 'pass'});
      expect(draft['currentHours'], 42.5);
      expect(draft['photos'], isA<Map<String, String?>>());
    });
  });
}
