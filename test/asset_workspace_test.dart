import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/assets/asset_workspace.dart';

void main() {
  final page = <String, dynamic>{
    'items': [
      {
        'id': 'one',
        'categories': ['overdue_work', 'overdue_service', 'plan_setup'],
      },
      {
        'id': 'two',
        'categories': ['inspection_expired', 'inspection_pending'],
      },
      {'id': 'three', 'categories': []},
    ],
  };
  test(
    'combined indicators count assets once and match the destination filter',
    () {
      expect(
        filterWorkspaceAssets(page, 'overdue_service').map((r) => r['id']),
        ['one'],
      );
      expect(filterWorkspaceAssets(page, 'attention').length, 2);
      expect(
        filterWorkspaceAssets(page, 'inspection_expired').map((r) => r['id']),
        ['two'],
      );
      expect(filterWorkspaceAssets(page, 'all').length, 3);
    },
  );
  test(
    'Home keeps the three highest nonempty priorities with canonical Assets links',
    () {
      expect(topWorkspacePriorities(page), [
        'inspection_expired',
        'inspection_pending',
        'overdue_service',
      ]);
      for (final key in topWorkspacePriorities(page)) {
        final uri = Uri.parse(assetWorkspaceDestination(key));
        expect(uri.path, '/assets');
        expect(uri.queryParameters['filter'], key);
        expect(
          filterWorkspaceAssets(
            page,
            uri.queryParameters['filter']!,
          ).isNotEmpty,
          isTrue,
        );
      }
    },
  );
}
