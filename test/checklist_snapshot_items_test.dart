import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/checklists/checklist_snapshot_items.dart';
import 'package:vortice_app/features/checklists/work_order_checklist_snapshot_repository.dart';
import 'package:vortice_app/features/maintenance/maintenance_models.dart';

void main() {
  test(
    'legacy snapshot source links inherit their saved publication without mutation',
    () {
      final rows = [
        {
          'id': 'old',
          'description_en': 'Inspect equipment',
          'definition': {'source_page': 3},
        },
        {
          'id': 'explicit',
          'template_id': 'preserved',
          'description_en': 'Check guard',
        },
      ];
      final job = MaintenanceJob({
        'checklist_template_id': 'publication',
        'checklist_snapshot': rows,
      });
      expect(job.checklist.first['template_id'], 'publication');
      expect(job.checklist.last['template_id'], 'preserved');
      expect(rows.first.containsKey('template_id'), isFalse);
      final snapshot = WorkOrderChecklistSnapshot.fromJson({
        'work_order_id': 'job',
        'template_id': 'publication',
        'items_json': rows,
      });
      expect(snapshot.items.first.templateId, 'publication');
      expect(snapshot.items.last.templateId, 'preserved');
      expect(
        checklistSnapshotItems(rows, null).first.containsKey('template_id'),
        isFalse,
      );
    },
  );
}
