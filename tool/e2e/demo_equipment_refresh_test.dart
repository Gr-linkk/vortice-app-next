// Explicit read-only acceptance of the persistent, user-requested demo setup.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/core/equipment_art_catalog.dart';
import 'package:vortice_app/core/equipment_illustration.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/features/checklists/checklist_provider.dart';
import 'package:vortice_app/models/checklist_template.dart';
import 'connected_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'demo truck artwork and Ellicott setup remain usable and scoped',
    (tester) async {
      await tester.runAsync(() async {
        final h = ConnectedHarness(tester, report: 'demo-equipment-refresh');
        await h.start();
        const truck = 'd0210000-0000-4000-8000-000000000010';
        const dredge = 'df8fd7a1-fc9f-5447-a6fd-c83a181df18c';
        const original = '2acd3f58-08fe-44f1-b4cb-41fc6dd439cb';
        try {
          for (final role in ['owner', 'supervisor', 'mechanic', 'operator']) {
            await h.step(
              '$role sees correct demo equipment and checklists',
              () async {
                await h.login('demo_fleet_$role@vortice.dev');
                await h.go('/client/dashboard');
                final assets = await supabase.from('assets').select().inFilter(
                  'id',
                  [truck, dredge, original],
                );
                expect(
                  assets.map((a) => a['id']),
                  unorderedEquals([truck, dredge]),
                );
                final truckRow = assets.singleWhere((a) => a['id'] == truck);
                expect(truckRow['model'], 'Hwy truck');
                expect(
                  equipmentArtFor(
                    assetTypeId: truckRow['asset_type_id'] as String,
                  ),
                  EquipmentArt.highwayTruck,
                );
                final templates = await supabase
                    .from('checklist_templates')
                    .select()
                    .eq('scope_asset_id', dredge);
                final copied = templates
                    .map(ChecklistTemplate.fromJson)
                    .toList();
                expect(copied, hasLength(role == 'operator' ? 1 : 5));
                var steps = 0;
                for (final t in copied) {
                  steps +=
                      (await supabase
                              .from('checklist_items')
                              .select('id')
                              .eq('template_id', t.id))
                          .length;
                }
                expect(steps, role == 'operator' ? 49 : 196);
                final engines = await supabase
                    .from('asset_engines')
                    .select('id,label')
                    .eq('asset_id', dredge);
                expect(engines, hasLength(3));
                if (role != 'operator') {
                  final context =
                      await supabase.rpc(
                            'maintenance_asset_context',
                            params: {'p_asset': dredge},
                          )
                          as Map;
                  final plans = context['plans'] as List;
                  expect(plans, hasLength(4));
                  expect(
                    plans.every(
                      (p) =>
                          copied.any((t) => t.id == p['checklist_template_id']),
                    ),
                    isTrue,
                  );
                }
                await h.go('/client/dashboard');
                if (role == 'owner') {
                  expect(find.text('Demo Hwy truck'), findsOneWidget);
                  final truckArt = tester
                      .widgetList<EquipmentIllustration>(
                        find.byType(EquipmentIllustration),
                      )
                      .where((w) => w.assetTypeId == truckRow['asset_type_id']);
                  expect(truckArt, isNotEmpty);
                  await h.screenshot('owner-home-truck-and-ellicott');
                  await h.tap(find.text('Demo Ellicott 460SL'));
                  await h.screenshot('owner-ellicott-details');
                  await h.go('/maintenance/assets/$dredge');
                  expect(find.text('Asset maintenance'), findsOneWidget);
                  await h.screenshot('owner-ellicott-maintenance');
                  final ladder = copied.singleWhere(
                    (t) => t.name.startsWith('Ellicott ladder lubrication'),
                  );
                  final sourceItems = await supabase
                      .from('checklist_items')
                      .select('id,definition')
                      .eq('template_id', ladder.id);
                  final source = sourceItems.first['definition'] as Map;
                  final page =
                      await supabase.rpc(
                            'checklist_source_page',
                            params: {
                              'p_template': ladder.id,
                              'p_item': sourceItems.first['id'],
                              'p_document': source['source_document_id'],
                              'p_page': source['source_page'],
                            },
                          )
                          as Map;
                  final bytes = await supabase.storage
                      .from('maintenance-documents')
                      .download(page['object_path'] as String);
                  expect(bytes.length, greaterThan(1000));
                }
                if (role == 'operator') {
                  final assignments = await supabase
                      .from('checklist_assignments')
                      .select('id,status')
                      .eq('asset_id', dredge);
                  expect(assignments, hasLength(1));
                  expect(assignments.single['status'], 'pending');
                  await h.screenshot('operator-ellicott-assignment');
                  await h.tap(
                    find.widgetWithText(ListTile, 'Demo Ellicott 460SL').last,
                  );
                  await h.screenshot('operator-ellicott-preop-entry');
                  expect(find.textContaining('Ellicott'), findsWidgets);
                  await h.tap(find.text('DEMO - Ellicott daily pre-operation'));
                  final shownItems = await h.container.read(
                    checklistItemsProvider(copied.single.id).future,
                  );
                  expect(shownItems, hasLength(49));
                  expect(shownItems.first.descriptionEn, 'Record engine hours');
                  await h.settle();
                  await h.screenshot('operator-ellicott-checklist-open');
                  expect(tester.takeException(), isNull);
                }
                expect(tester.takeException(), isNull);
              },
            );
          }
          await h.step(
            'service company cannot read private demo fleet setup',
            () async {
              await h.login('demo_service_owner@vortice.dev');
              expect(
                await supabase.from('assets').select('id').eq('id', dredge),
                isEmpty,
              );
              expect(
                await supabase
                    .from('checklist_templates')
                    .select('id')
                    .eq('scope_asset_id', dredge),
                isEmpty,
              );
              expect(
                await supabase
                    .from('maintenance_documents')
                    .select('id')
                    .eq('id', '109255ab-57a0-5ca3-8894-eeb7f1a5820e'),
                isEmpty,
              );
            },
          );
          expect(h.issues, isEmpty);
        } finally {
          await h.close();
        }
      });
    },
  );
}
