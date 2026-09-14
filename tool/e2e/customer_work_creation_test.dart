import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:vortice_app/core/app_dropdown_field.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/features/membership/organization_work_provider.dart';
import 'package:vortice_app/features/maintenance/work_focus.dart';
import 'connected_harness.dart';
import 'audit_output.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'calendar creates customer work with an edited date and attached checklist',
    (tester) async {
      await tester.runAsync(() async {
        final h = ConnectedHarness(tester, report: 'next008-creation');
        await h.start();
        final title = 'E2E-008-${const Uuid().v4()}';
        final manifest = File(auditOutputPath('NEXT-008-work.json'));
        manifest.writeAsStringSync(jsonEncode({'title': title}));
        try {
          await h.login('demo_service_owner@vortice.dev');
          final repo = h.container.read(organizationWorkRepositoryProvider);
          final data = await repo.customerCreationContext();
          final equipment = (data['equipment'] as List)
              .cast<Map<String, dynamic>>()
              .firstWhere((e) => (e['templates'] as List).isNotEmpty);
          final template = (equipment['templates'] as List).first as Map;
          await h.step(
            'calendar to full creation page, checklist and edited date',
            () async {
              await h.container.read(workFocusProvider.future);
              await h.go('/maintenance/planning?day=2026-09-20');
              await h.tap(find.text('Add work here'));
              // All work may ask whose equipment; the saved customer focus skips it.
              if (find.text('Customer work').evaluate().isNotEmpty) {
                await h.tap(find.text('Customer work').last);
              }
              await h.tap(find.byType(AppDropdownField<String>).first);
              await h.tap(
                find
                    .text(
                      '${equipment['customer_name']} · ${equipment['asset_name']}',
                    )
                    .last,
              );
              await h.tap(find.byType(AppDropdownField<String>).last);
              await h.tap(
                find.text('${template['name']} · v${template['version']}').last,
              );
              await h.tap(find.byKey(const Key('creation-date')));
            await h.tap(find.text('23').hitTestable().first);
              await h.tap(find.text('OK'));
              await h.fill(h.field('Work order title'), title);
              await h.fill(
                h.field('Work details'),
                'Synthetic creation check; verify checklist and edited booking.',
              );
              await h.screenshot('creation-ready');
              await h.tap(
                find.widgetWithText(FilledButton, 'Create work order'),
              );
              await h.reveal(find.text(title));
              await h.screenshot('calendar-saved-day');
              final orders = await supabase
                  .from('work_orders')
                  .select(
                    'id,scheduled_date,checklist_template_id,checklist_template_version',
                  )
                  .eq('title', title);
              expect(orders, hasLength(1));
              final order = orders.single;
              manifest.writeAsStringSync(
                jsonEncode({'title': title, 'work_order_id': order['id']}),
              );
              expect(order['scheduled_date'], '2026-09-23');
              expect(order['checklist_template_id'], template['id']);
              expect(order['checklist_template_version'], template['version']);
              await h.tap(find.text(title));
              final saved = await repo.context(order['id'] as String);
              expect((saved['checklist_snapshot'] as List), isNotEmpty);
              await h.screenshot('work-checklist-attached');
            },
          );
          expect(h.issues, isEmpty);
        } finally {
          await h.close();
        }
      });
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
