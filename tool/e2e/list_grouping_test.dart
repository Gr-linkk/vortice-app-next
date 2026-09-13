// Read-only rendered acceptance: no assets, checklists or assignments are saved.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/core/list_group_heading.dart';
import 'package:vortice_app/features/assets/asset_type_field.dart';
import 'package:vortice_app/features/checklists/checklist_provider.dart';
import 'connected_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('grouped catalog, library and operator choices remain searchable', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final h = ConnectedHarness(tester, report: 'list-grouping');
      await h.start();
      try {
        await h.login('demo_fleet_owner@vortice.dev');
        await h.step(
          'catalog categories, cross-category search and selection',
          () async {
            await h.go('/assets/new');
            await h.tap(find.byKey(const ValueKey('asset-type-picker')));
            expect(find.byType(ListGroupHeading), findsWidgets);
            await h.screenshot('catalog-groups');
            await h.fill(
              find.byKey(const ValueKey('asset-type-search')),
              'truck',
            );
            await h.settle(15);
            expect(find.text('Heavy Equipment'), findsOneWidget);
            expect(find.text('Road Vehicles'), findsOneWidget);
            await h.screenshot('catalog-truck-search');
            await h.tap(find.text('Highway Truck'));
            expect(
              tester
                  .widget<AssetTypeField>(find.byType(AssetTypeField))
                  .selectedId,
              '00000000-0000-0000-0000-000000000022',
            );
          },
        );
        await h.step(
          'library keeps Ellicott procedures together and searches by equipment',
          () async {
            await h.go('/checklist-library');
            final search = find.byType(TextField).first;
            await h.fill(search, 'Demo Ellicott');
            expect(
              find.byKey(
                const ValueKey(
                  'checklist-group-asset:df8fd7a1-fc9f-5447-a6fd-c83a181df18c',
                ),
              ),
              findsOneWidget,
            );
            await h.reveal(find.text('Demo Ellicott 460SL'));
            await h.screenshot('library-ellicott-group');
            expect(
              tester
                  .widget<ListGroupHeading>(find.byType(ListGroupHeading).first)
                  .count,
              5,
            );
          },
        );
        await h.step(
          'operator equipment groups and specific/general checklist choices',
          () async {
            await h.login('demo_fleet_operator@vortice.dev');
            await h.go('/client/dashboard');
            await h.container.read(checklistTemplatesProvider.future);
            await h.go('/operator/checklist');
            expect(find.byType(ListGroupHeading), findsWidgets);
            await h.screenshot('operator-equipment-groups');
            await h.tap(find.text('Demo Ellicott 460SL'));
            await h.settle(15);
            await h.reveal(find.text('For this equipment'));
            await h.screenshot('operator-checklist-groups');
            expect(find.text('General checks'), findsOneWidget);
          },
        );
        await h.step(
          'narrow large text keeps category headings and choices readable',
          () async {
            await h.login('demo_fleet_owner@vortice.dev');
            tester.view.physicalSize = const Size(320, 844);
            tester.platformDispatcher.textScaleFactorTestValue = 2;
            await h.go('/assets/new');
            await h.tap(find.byKey(const ValueKey('asset-type-picker')));
            await h.fill(
              find.byKey(const ValueKey('asset-type-search')),
              'truck',
            );
            await h.settle(15);
            await h.screenshot('catalog-320-large-text');
            await h.tap(find.text('Highway Truck'));
            expect(tester.takeException(), isNull);
          },
        );
        expect(h.issues, isEmpty);
      } finally {
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        await h.close();
      }
    });
  });
}
