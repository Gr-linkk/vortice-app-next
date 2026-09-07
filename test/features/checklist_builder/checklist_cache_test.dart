import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:vortice_app/db/database.dart';
import 'package:vortice_app/features/checklists/checklist_repository.dart';
import 'package:vortice_app/features/checklists/work_order_checklist_snapshot_repository.dart';

void main() {
  setUpAll(() {
    if (Platform.isLinux) {
      open.overrideFor(
        OperatingSystem.linux,
        () => DynamicLibrary.open('libsqlite3.so.0'),
      );
    }
  });
  test('v6 cache upgrades without losing existing checklist answers', () async {
    final directory = Directory.systemTemp.createTempSync(
      'vortice-next-checklist-cache-',
    );
    final file = File('${directory.path}/test.db');
    final old = AppDatabase(NativeDatabase(file));
    await old.checklistsDao.upsertTemplate(
      const ChecklistTemplatesTableCompanion(
        id: Value('template'),
        name: Value('Existing template'),
      ),
    );
    await old.customStatement(
      "INSERT INTO checklist_items(id,template_id,description_en) VALUES ('item','template','Existing instruction')",
    );
    await old.customStatement(
      "INSERT INTO checklist_responses(id,work_order_id,checklist_item_id,notes,sync_status) VALUES ('response','job','item','Offline observation','pending')",
    );
    await old.customStatement(
      'ALTER TABLE checklist_templates DROP COLUMN scope_json',
    );
    await old.customStatement(
      'ALTER TABLE checklist_items DROP COLUMN definition_json',
    );
    await old.customStatement('PRAGMA user_version = 6');
    await old.close();
    final upgraded = AppDatabase(NativeDatabase(file));
    try {
      expect(
        (await upgraded.checklistsDao.getAllTemplates()).single.scopeJson,
        '{}',
      );
      expect(
        (await upgraded.checklistsDao.getItemsForTemplate(
          'template',
        )).single.definitionJson,
        '{}',
      );
      final answer = (await upgraded.checklistsDao.getResponsesForWorkOrder(
        'job',
      )).single;
      expect(answer.notes, 'Offline observation');
      expect(answer.syncStatus, 'pending');
    } finally {
      await upgraded.close();
      directory.deleteSync(recursive: true);
    }
  });
  test(
    'opening a frozen job preserves live template scope and retirement',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      try {
        const scope =
            '{"client_id":"company","scope_asset_id":"asset","procedure_id":"procedure"}';
        await db.checklistsDao.upsertTemplate(
          const ChecklistTemplatesTableCompanion(
            id: Value('template'),
            name: Value('Old version'),
            scopeJson: Value(scope),
            isActive: Value(false),
          ),
        );
        final snapshot = WorkOrderChecklistSnapshot.fromJson({
          'work_order_id': 'job',
          'template_id': 'template',
          'template_name': 'Old version',
          'template_version': 1,
          'items_json': [
            {
              'id': 'item',
              'template_id': 'template',
              'description_en': 'Verify signature plate',
              'definition': {
                'authored': true,
                'input_type': 'number',
                'min': 10,
              },
            },
          ],
        });
        await ChecklistRepository(db).cacheSnapshot(snapshot);
        final cached = (await db.checklistsDao.getAllTemplates()).single;
        expect(cached.isActive, isFalse);
        expect(cached.scopeJson, scope);
        final item = (await db.checklistsDao.getItemsForTemplate(
          'template',
        )).single;
        expect(jsonDecode(item.definitionJson)['min'], 10);
        expect(item.descriptionEn, 'Verify signature plate');
      } finally {
        await db.close();
      }
    },
  );
}
