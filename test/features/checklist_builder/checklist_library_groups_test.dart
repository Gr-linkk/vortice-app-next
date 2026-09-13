import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/core/list_label_order.dart';
import 'package:vortice_app/features/checklist_builder/checklist_library_groups.dart';

void main() {
  test(
    'natural ordering keeps numbered equipment and service intervals usable',
    () {
      final labels = [
        'Truck 10',
        'Truck 2',
        '1000-hour',
        '500-hour',
        '250-hour',
        'Truck 1',
      ];
      labels.sort(compareListLabels);
      expect(labels, [
        '250-hour',
        '500-hour',
        '1000-hour',
        'Truck 1',
        'Truck 2',
        'Truck 10',
      ]);
    },
  );

  test(
    'draft and published lists retain scope IDs, purpose and numeric order',
    () {
      final catalog = <String, dynamic>{
        'assets': [
          {'id': 'a', 'name': 'Dredge'},
          {'id': 'b', 'name': 'Dredge'},
        ],
        'asset_types': [],
      };
      final rows = <Map<String, dynamic>>[
        {
          'id': 'general',
          'name': 'General',
          'checklist_type': 'operator_daily',
        },
        {
          'id': '1000',
          'draft': {
            'scope_asset_id': 'a',
            'name': '1000-hour',
            'checklist_type': 'pm',
          },
        },
        {
          'id': '250',
          'scope_asset_id': 'a',
          'name': '250-hour',
          'checklist_type': 'pm',
        },
        {
          'id': 'other',
          'scope_asset_id': 'b',
          'name': '250-hour',
          'checklist_type': 'pm',
        },
        {
          'id': 'daily',
          'scope_asset_id': 'a',
          'name': 'Daily checks',
          'checklist_type': 'operator_daily',
        },
      ];
      final groups = groupChecklistLibrary(rows, catalog, false);
      expect(groups.keys, ['asset:a', 'asset:b', 'general']);
      expect(groups['asset:a']!.map((r) => r['id']), ['daily', '250', '1000']);
      expect(
        groups.values.expand((g) => g).map((r) => r['id']).toSet(),
        rows.map((r) => r['id']).toSet(),
      );
      expect(
        rows.first['id'],
        'general',
        reason: 'Do not reorder the provider snapshot',
      );
      expect(checklistGroupLabel('general', catalog, true), 'Listas generales');
    },
  );
}
