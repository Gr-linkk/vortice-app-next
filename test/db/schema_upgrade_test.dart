import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:vortice_app/db/database.dart';

const _payload =
    '{"operation_id":"frozen-command","revision":7,"data":{"report":"report","photo":"photo"}}';
const _tables = [
  'profiles',
  'assets',
  'asset_engines',
  'work_orders',
  'checklist_templates',
  'checklist_items',
  'checklist_responses',
  'service_reports',
  'parts',
  'invoices',
  'sync_operations',
  'local_attachments',
];

Future<void> _populate(File file) async {
  final db = AppDatabase.forAccount(
    'schema-account',
    executor: NativeDatabase(file),
  );
  try {
    await db.customStatement(
      "INSERT INTO profiles(id,email,full_name) VALUES ('schema-account','synthetic@example.invalid','Synthetic worker')",
    );
    await db.customStatement(
      "INSERT INTO assets(id,client_id,asset_type_id,name,notes) VALUES ('asset','client','type','Synthetic asset','Private synthetic asset notes')",
    );
    await db.customStatement(
      "INSERT INTO asset_engines(id,asset_id,label,current_hours) VALUES ('engine','asset','Engine',42)",
    );
    await db.customStatement(
      "INSERT INTO work_orders(id,asset_id,engine_id,client_id,title,created_by,notes_internal) VALUES ('job','asset','engine','client','Synthetic job','schema-account','Private synthetic job notes')",
    );
    await db.customStatement(
      "INSERT INTO checklist_templates(id,name) VALUES ('template','Synthetic procedure')",
    );
    await db.customStatement(
      "INSERT INTO checklist_items(id,template_id,description_en,requires_photo) VALUES ('item','template','Inspect engine',1)",
    );
    await db.customStatement(
      "INSERT INTO checklist_responses(id,work_order_id,checklist_item_id,notes,photo_url,response_status,sync_status,last_error) VALUES ('response','job','item','Captured answer','evidence/photo.jpg','failed','pending_update','synthetic connection failure')",
    );
    await db.customStatement(
      "INSERT INTO service_reports(id,work_order_id,correction,tech_signature_url,sync_status,last_error) VALUES ('report','job','Captured correction','signatures/signature.png','pending_create','synthetic interrupted delivery')",
    );
    await db.customStatement(
      "INSERT INTO parts(id,work_order_id,description,unit_cost) VALUES ('part','job','Synthetic part',19.5)",
    );
    await db.customStatement(
      "INSERT INTO invoices(id,work_order_id,client_id,invoice_number,notes) VALUES ('invoice','job','client','SYN-1','Captured invoice notes')",
    );
    await db.customStatement(
      "INSERT INTO sync_operations(id,entity_type,entity_local_id,entity_remote_id,operation_type,payload_json,status,attempt_count,last_error) VALUES ('frozen-command','service_report','report','job','rpc',?,'pending',3,'synthetic uncertain response')",
      [_payload],
    );
    await db.customStatement(
      "INSERT INTO local_attachments(id,owner_entity_type,owner_local_id,owner_remote_id,purpose,local_path,mime_type,size_bytes,sha256,remote_bucket,remote_path,status) VALUES ('photo','service_report','report','job','evidence','synthetic/photo.jpg','image/jpeg',42,'synthetic-digest','work-evidence','evidence/photo.jpg','pending_create')",
    );
  } finally {
    await db.close();
  }
}

List<Map<String, Object?>> _rows(sqlite.Database raw, String table) => raw
    .select('SELECT * FROM $table ORDER BY id')
    .map((row) => Map<String, Object?>.from(row))
    .toList();

// A logical snapshot verifies durable values and schema, not file bytes:
// SQLite opening can change journal metadata even when all rows are retained.
Map<String, Object?> _snapshot(File file) {
  final raw = sqlite.sqlite3.open(file.path);
  try {
    return {
      'version': raw.select('PRAGMA user_version').single.values.single,
      'schema': raw
          .select('SELECT name,sql FROM sqlite_master ORDER BY name')
          .map((row) => Map<String, Object?>.from(row))
          .toList(),
      for (final table in _tables) table: _rows(raw, table),
      'future_marker': _rows(raw, 'future_marker'),
    };
  } finally {
    raw.dispose();
  }
}

void _reconstructVersion(sqlite.Database raw, int version) {
  // Remove exactly the columns/tables introduced by the current migration
  // thresholds. The fixture is a synthetic historical shape, not a user store.
  for (final table in [
    'assets',
    'asset_engines',
    'work_orders',
    'service_reports',
  ]) {
    raw.execute('ALTER TABLE $table DROP COLUMN meter_unit');
  }
  raw.execute('ALTER TABLE assets DROP COLUMN primary_meter_engine_id');
  raw.execute('ALTER TABLE checklist_templates DROP COLUMN scope_json');
  raw.execute('ALTER TABLE checklist_items DROP COLUMN definition_json');
  if (version < 6) {
    for (final column in ['sync_status', 'last_synced_at', 'last_error']) {
      raw.execute('ALTER TABLE service_reports DROP COLUMN $column');
    }
  }
  if (version < 5) {
    for (final column in [
      'response_status',
      'sync_status',
      'updated_at',
      'last_synced_at',
      'last_error',
    ]) {
      raw.execute('ALTER TABLE checklist_responses DROP COLUMN $column');
    }
  }
  if (version < 4) {
    raw.execute('DROP TABLE sync_operations');
    raw.execute('DROP TABLE local_attachments');
  }
  raw.execute('PRAGMA user_version=$version');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final version in [9, 999]) {
    test(
      'Future schema $version rejects repeated reads and writes without changing saved data',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'vortice-future-schema-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final file = File('${directory.path}/fixture.sqlite');
        await _populate(file);
        final raw = sqlite.sqlite3.open(file.path);
        try {
          raw.execute(
            'CREATE TABLE future_marker(id TEXT PRIMARY KEY,value TEXT NOT NULL)',
          );
          raw.execute(
            "INSERT INTO future_marker VALUES ('future-id','Synthetic future-only data')",
          );
          raw.execute('PRAGMA user_version=$version');
        } finally {
          raw.dispose();
        }
        final before = _snapshot(file);
        final rejectedSchema = throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'schema rejection',
            contains(
              'Database schema $version is newer than supported schema 8',
            ),
          ),
        );
        // Test account-owned and legacy constructor paths, including a write as
        // the first query. A later reopening must reject the same store again.
        for (var attempt = 0; attempt < 4; attempt++) {
          final db = attempt.isEven
              ? AppDatabase.forAccount(
                  'schema-account',
                  executor: NativeDatabase(file),
                )
              : AppDatabase(NativeDatabase(file));
          try {
            final openingQuery = attempt < 2
                ? db.customSelect('SELECT * FROM service_reports').get()
                : db.customStatement(
                    "INSERT INTO profiles(id,email,full_name) VALUES ('forbidden-write','write@example.invalid','Must not persist')",
                  );
            await expectLater(openingQuery, rejectedSchema);
            // A connection that failed its migration must remain fenced even
            // though SQLite itself opened successfully before the rejection.
            await expectLater(
              db.customStatement(
                "UPDATE service_reports SET correction='Must not persist' WHERE id='report'",
              ),
              rejectedSchema,
            );
          } finally {
            await db.close();
          }
          expect(
            _snapshot(file),
            before,
            reason:
                'Rejected opening $attempt must preserve version, schema and every saved row.',
          );
        }
      },
    );
  }

  for (final version in [3, 4, 5, 6]) {
    test(
      'Populated schema $version upgrades and reopens preserving all existing values',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'vortice-supported-schema-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final file = File('${directory.path}/fixture.sqlite');
        await _populate(file);
        final raw = sqlite.sqlite3.open(file.path);
        late final Map<String, List<Map<String, Object?>>> before;
        try {
          _reconstructVersion(raw, version);
          before = {
            for (final table in _tables)
              if (version >= 4 ||
                  !['sync_operations', 'local_attachments'].contains(table))
                table: _rows(raw, table),
          };
        } finally {
          raw.dispose();
        }
        for (var opening = 0; opening < 2; opening++) {
          final db = AppDatabase.forAccount(
            'schema-account',
            executor: NativeDatabase(file),
          );
          try {
            expect(
              (await db.customSelect('PRAGMA user_version').get())
                  .single
                  .data
                  .values
                  .single,
              8,
            );
            for (final entry in before.entries) {
              final after = await db
                  .customSelect('SELECT * FROM ${entry.key} ORDER BY id')
                  .get();
              expect(after, hasLength(entry.value.length));
              for (var row = 0; row < after.length; row++) {
                for (final value in entry.value[row].entries) {
                  expect(
                    after[row].data[value.key],
                    value.value,
                    reason:
                        'v$version ${entry.key}.${value.key} must survive upgrade/reopen $opening.',
                  );
                }
              }
            }
            final job = (await db.select(db.workOrdersTable).get()).single;
            expect(job.meterUnit, 'hours');
            expect(
              (await db.select(db.checklistTemplatesTable).get())
                  .single
                  .scopeJson,
              '{}',
            );
            expect(
              (await db.select(db.checklistItemsTable).get())
                  .single
                  .definitionJson,
              '{}',
            );
            final report =
                (await db.select(db.serviceReportsTable).get()).single;
            expect(report.techSignatureUrl, 'signatures/signature.png');
            if (version < 6) expect(report.syncStatus, 'synced');
            final response =
                (await db.select(db.checklistResponsesTable).get()).single;
            expect(response.photoUrl, 'evidence/photo.jpg');
            if (version < 5) expect(response.syncStatus, 'synced');
            final operations = await db.select(db.syncOperationsTable).get();
            final attachments = await db.select(db.localAttachmentsTable).get();
            if (version < 4) {
              expect(operations, isEmpty);
              expect(attachments, isEmpty);
            } else {
              expect(operations.single.id, 'frozen-command');
              expect(operations.single.payloadJson, _payload);
              expect(attachments.single.ownerLocalId, report.id);
              expect(attachments.single.remotePath, response.photoUrl);
            }
          } finally {
            await db.close();
          }
        }
      },
    );
  }
}
