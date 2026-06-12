import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/operator/operator_checklist_support.dart';
import 'package:vortice_app/models/checklist_template.dart';

ChecklistTemplate _template(String id) => ChecklistTemplate(
      id: id,
      name: 'Pre-departure',
      category: 'operations',
    );

void main() {
  group('encodeOperatorChecklistDraft', () {
    test('serializes asset, template, and base64 photos', () {
      final draft = encodeOperatorChecklistDraft(
        asset: {'id': 'asset-1', 'name': 'Tug'},
        template: _template('tpl-1'),
        responses: {'item-1': 'pass'},
        notes: const {},
        completedAt: DateTime.utc(2026, 6, 3, 12),
        currentHours: 10,
        generalNotes: 'ready',
        photos: {'item-1': Uint8List.fromList([7])},
      );

      expect(draft['assetId'], 'asset-1');
      expect(draft['templateId'], 'tpl-1');
      expect(draft['photos'], isA<Map<String, String?>>());
    });
  });

  group('decodeOperatorChecklistDraft', () {
    test('restores draft state from persisted json', () {
      final encoded = encodeOperatorChecklistDraft(
        asset: {'id': 'asset-1', 'name': 'Tug', 'client_id': 'client-1'},
        template: _template('tpl-1'),
        responses: {'item-1': 'monitor'},
        notes: {'item-1': 'watch'},
        completedAt: DateTime.utc(2026, 6, 3),
        currentHours: 12,
        generalNotes: null,
        photos: const {},
      );

      final restored = decodeOperatorChecklistDraft(
        encoded,
        fallbackCompletedAt: DateTime.utc(2026, 1, 1),
        assets: [
          {'id': 'asset-1', 'name': 'Tug'},
        ],
        templates: [_template('tpl-1')],
      );

      expect(restored.asset?['id'], 'asset-1');
      expect(restored.template?.id, 'tpl-1');
      expect(restored.responses, {'item-1': 'monitor'});
      expect(restored.notes, {'item-1': 'watch'});
    });
  });

  group('resolveOperatorInitialAsset', () {
    test('uses initial asset id when no current selection', () {
      final asset = resolveOperatorInitialAsset(
        currentAsset: null,
        initialAssetId: 'asset-2',
        assets: [
          {'id': 'asset-2', 'name': 'Barge'},
        ],
      );

      expect(asset?['name'], 'Barge');
    });
  });

  group('operatorSubmitSuccessMessage', () {
    test('warns when photos were not submitted', () {
      expect(
        operatorSubmitSuccessMessage(hasPhotos: true),
        operatorPhotoNotSubmittedMessage,
      );
      expect(
        operatorSubmitSuccessMessage(hasPhotos: false),
        'Checklist submitted',
      );
    });
  });
}
