import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/checklists/checklist_item_widget.dart';
import 'package:vortice_app/features/checklists/checklist_sync_banner.dart';
import 'package:vortice_app/features/checklists/checklist_template_selector.dart';
import 'package:vortice_app/models/checklist_item.dart';
import 'package:vortice_app/models/checklist_template.dart';
import 'package:vortice_app/sync/sync_status.dart';

void main() {
  group('ChecklistItemWidget', () {
    testWidgets('renders item description and status buttons', (tester) async {
      const item = ChecklistItem(
        id: 'item-1',
        templateId: 'tpl-1',
        descriptionEn: 'Check hydraulic fluid level',
        descriptionEs: 'Verificar nivel de fluido hidráulico',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChecklistItemWidget(
              item: item,
              status: null,
              note: '',
              photo: null,
              photoUrl: null,
              syncStatus: null,
              onStatusChanged: (_) {},
              onNoteChanged: (_) {},
              onPhotoChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Check hydraulic fluid level'), findsOneWidget);
      expect(find.text('Verificar nivel de fluido hidráulico'), findsOneWidget);
      expect(find.text('PASS'), findsOneWidget);
      expect(find.text('MONITOR'), findsOneWidget);
      expect(find.text('ACTION'), findsOneWidget);
      expect(find.text('N/A'), findsOneWidget);
    });

    testWidgets('shows note field when monitor is selected', (tester) async {
      const item = ChecklistItem(
        id: 'item-1',
        templateId: 'tpl-1',
        descriptionEn: 'Inspect belt tension',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChecklistItemWidget(
              item: item,
              status: 'monitor',
              note: '',
              photo: null,
              photoUrl: null,
              syncStatus: SyncStatusValues.failed,
              onStatusChanged: (_) {},
              onNoteChanged: (_) {},
              onPhotoChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Describe issue / action required'), findsOneWidget);
      expect(find.text('Sync failed'), findsOneWidget);
    });
  });

  group('ChecklistSyncStatusBanner', () {
    testWidgets('shows conflict message when hasConflict is true',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ChecklistSyncStatusBanner(
              hasConflict: true,
              message: 'Checklist has sync conflicts.',
            ),
          ),
        ),
      );

      expect(find.text('Checklist has sync conflicts.'), findsOneWidget);
      expect(find.byIcon(Icons.sync_problem), findsOneWidget);
    });

    testWidgets('shows pending sync message when hasConflict is false',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ChecklistSyncStatusBanner(
              hasConflict: false,
              message: 'Saved locally. Sync pending.',
            ),
          ),
        ),
      );

      expect(find.text('Saved locally. Sync pending.'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    });

    testWidgets('shows retry action when provided', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChecklistSyncStatusBanner(
              hasConflict: false,
              message:
                  'Sync blocked by server permissions. Retry after access is fixed.',
              onRetry: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.text('Retry'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      expect(tapped, isTrue);
    });
  });

  group('ChecklistTemplateSelector', () {
    testWidgets('shows empty message when no templates', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChecklistTemplateSelector(
              templates: const [],
              emptyMessage: 'No checklist templates available.',
              onSelect: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('No checklist templates available.'), findsOneWidget);
    });

    testWidgets('renders service hour templates and category groups',
        (tester) async {
      final templates = [
        ChecklistTemplate(
          id: 'svc-250',
          name: '250HR Service',
          category: 'general',
          intervalHours: 250,
        ),
        ChecklistTemplate(
          id: 'pre-op',
          name: 'Pre-Op',
          category: 'pre_ops',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChecklistTemplateSelector(
              templates: templates,
              emptyMessage: 'No checklist templates available.',
              onSelect: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Service Hours'), findsOneWidget);
      expect(find.text('250HR Service'), findsOneWidget);
      expect(find.text('Pre-Operations'), findsOneWidget);
      expect(find.text('Pre-Op'), findsOneWidget);
      expect(find.text('250h'), findsOneWidget);
    });

    testWidgets('highlights selected template', (tester) async {
      final template = ChecklistTemplate(
        id: 'pre-op',
        name: 'Pre-Op',
        category: 'pre_ops',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChecklistTemplateSelector(
              templates: [template],
              preselected: template,
              emptyMessage: 'No checklist templates available.',
              onSelect: (_) {},
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.check), findsOneWidget);
    });
  });
}
