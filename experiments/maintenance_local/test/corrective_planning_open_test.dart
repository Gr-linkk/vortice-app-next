import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/corrective_planning.dart';
import 'package:maintenance_local/corrective_planning_store.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/model.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  final proof = <String, dynamic>{'checks': <String, dynamic>{}};
  setUpAll(() async {
    proof['readerSha256'] = {
      for (final name in [
        'lab_store.dart',
        'corrective_planning.dart',
        'corrective_planning_store.dart',
      ])
        name: digest(await File('lib/$name').readAsBytes()),
    };
    proof['scope'] = 'Synthetic LabStore startup compatibility only.';
    proof['maintenanceRustInitialized'] = false;
  });
  tearDownAll(() async {
    final repository = Directory.current.parent.parent;
    final output = Directory('${repository.path}/outputs/corrective-planning');
    await output.create(recursive: true);
    await File(
      '${output.path}/startup-compatibility-proof.json',
    ).writeAsString(canonical(proof), flush: true);
  });

  late Directory root;
  late Directory workspace;
  final stores = <LabStore>[];
  setUp(() async {
    root = await Directory.systemTemp.createTemp('corrective-open-');
    workspace = Directory('${root.path}/office');
  });
  tearDown(() async {
    for (final store in stores) {
      await store.close();
    }
    stores.clear();
    await root.delete(recursive: true);
  });

  Future<LabStore> openOffice() async {
    final store = await LabStore.open(
      workspace,
      office: true,
      maintenanceOnly: true,
      now: () => DateTime.utc(2026, 10, 1, 18),
    );
    stores.add(store);
    return store;
  }

  Future<void> close(LabStore store) async {
    await store.close();
    stores.remove(store);
  }

  String savedSettingsAndEvents(LabStore store) => canonical({
    'databaseVersion': store.db
        .select('PRAGMA user_version')
        .single
        .values
        .single,
    'settings': [
      for (final row in store.db.select('SELECT * FROM settings ORDER BY key'))
        Map<String, dynamic>.from(row),
    ],
    'events': [
      for (final row in store.db.select('SELECT * FROM events ORDER BY id'))
        Map<String, dynamic>.from(row),
    ],
  });

  // Build the two valid startup states through the real, already accepted store.
  // These fixtures make no inspection, backup, replay or navigation assertions.
  Future<String> fixture({required bool accepted}) async {
    final store = await openOffice();
    await store.createCompany(
      'Synthetic startup compatibility company',
      coordinatorName: 'Synthetic coordinator',
    );
    final equipment = await store.addEquipment(name: 'Synthetic excavator');
    final planning = CorrectivePlanningStore(store);
    final command = await planning.freezeCreate(
      equipmentId: equipment['id'] as String,
      title: 'Synthetic typed corrective draft',
      description: 'Planning instructions only; no repair is recorded.',
      commandId: 'c3000000-0000-4000-8000-000000000001',
    );
    if (accepted) await planning.apply(command);
    expect(store.db.select('PRAGMA user_version').single.values.single, 3);
    final saved = savedSettingsAndEvents(store);
    await close(store);
    return saved;
  }

  Future<Json> inventory() async {
    final files =
        (await workspace.list(recursive: true).toList())
            .whereType<File>()
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    return {
      for (final file in files)
        file.path.substring(workspace.path.length + 1): digest(
          await file.readAsBytes(),
        ),
    };
  }

  void mutateFixture(void Function(Database) mutation) {
    final db = sqlite3.open('${workspace.path}/workspace.sqlite');
    try {
      mutation(db);
      db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    } finally {
      db.close();
    }
  }

  Future<void> refusedWithoutWrites(
    String check,
    Future<LabStore> Function() open,
    Matcher failure,
  ) async {
    final before = await inventory();
    await expectLater(open(), throwsA(failure));
    final after = await inventory();
    expect(after, before);
    (proof['checks'] as Json)[check] = {
      'refused': true,
      'allWorkspaceFileBytesRetained': true,
      'inventorySha256': contentHash(before),
      'beforeFiles': before,
      'afterFiles': after,
    };
  }

  for (final accepted in [false, true]) {
    final phase = accepted ? 'current-draft' : 'pending-intent';
    test('Schema3 office reopens its valid saved $phase', () async {
      final saved = await fixture(accepted: accepted);
      final reopened = await openOffice();
      expect(savedSettingsAndEvents(reopened), saved);
      final planning = CorrectivePlanningStore(reopened);
      if (accepted) {
        final draft = (await planning.listDrafts()).single;
        expect(draft.kind, 'corrective');
        expect(draft.state, 'draft');
        expect(await planning.pendingCommands(), isEmpty);
      } else {
        expect(
          (await planning.pendingCommands()).single.action,
          CorrectivePlanningAction.create,
        );
        expect(await planning.listDrafts(), isEmpty);
      }
      (proof['checks'] as Json)['valid-$phase'] = {
        'officeReopened': true,
        'savedSettingsAndEventsUnchanged': true,
        'savedStateSha256': digest(utf8.encode(saved)),
      };
    });
  }

  test(
    'Schema3 startup refuses the phone role before workspace byte changes',
    () async {
      await fixture(accepted: true);
      await refusedWithoutWrites(
        'phone-role',
        // Exercise the explicit schema3 role guard. Normal product startup also
        // has its existing maintenance-directory ownership check before this.
        () => LabStore.open(workspace, office: false),
        isA<StateError>().having(
          (error) => error.message,
          'office retention message',
          contains('files have been retained'),
        ),
      );
    },
  );

  test(
    'Schema99 startup refuses the future format and retains every file byte',
    () async {
      await fixture(accepted: false);
      mutateFixture((db) => db.execute('PRAGMA user_version=99'));
      await refusedWithoutWrites(
        'schema99',
        () => LabStore.open(workspace, office: true, maintenanceOnly: true),
        isA<StateError>().having(
          (error) => error.message,
          'future edition retention message',
          contains('files have been retained'),
        ),
      );
    },
  );

  test(
    'Schema3 startup refuses an unsupported draft kind retaining file bytes',
    () async {
      await fixture(accepted: true);
      mutateFixture((db) {
        final ledger =
            jsonDecode(
                  db.select('SELECT value FROM settings WHERE key=?', [
                        correctivePlanningSetting,
                      ]).single['value']
                      as String,
                )
                as Json;
        final receipt = ledger['receipts'][0] as Json;
        final draft = receipt['draft'] as Json;
        draft['kind'] = 'inspection';
        draft.remove('hash');
        draft['hash'] = contentHash(draft);
        receipt.remove('hash');
        receipt['hash'] = contentHash(receipt);
        db.execute('UPDATE settings SET value=? WHERE key=?', [
          canonical(ledger),
          correctivePlanningSetting,
        ]);
      });
      await refusedWithoutWrites(
        'unsupported-draft-kind',
        () => LabStore.open(workspace, office: true, maintenanceOnly: true),
        isA<CorrectivePlanningFailure>(),
      );
    },
  );

  test(
    'Fresh schema0 without SQL tables opens when planning state is absent',
    () async {
      await workspace.create();
      final db = sqlite3.open('${workspace.path}/workspace.sqlite');
      try {
        expect(db.select('PRAGMA user_version').single.values.single, 0);
        expect(
          db.select("SELECT name FROM sqlite_master WHERE type='table'"),
          isEmpty,
        );
      } finally {
        db.close();
      }
      final opened = await LabStore.open(workspace, office: true);
      stores.add(opened);
      expect(opened.db.select('PRAGMA user_version').single.values.single, 1);
      expect(opened.setting(correctivePlanningSetting), isNull);
      expect(
        opened.db.select('SELECT id FROM events WHERE kind=?', [
          correctivePlanningRecordedEvent,
        ]),
        isEmpty,
      );
      (proof['checks'] as Json)['fresh-schema0-absent'] = {
        'initialDatabaseVersion': 0,
        'initialSqlTables': 0,
        'opened': true,
        'initializedDatabaseVersion': 1,
      };
    },
  );

  test(
    'Legacy schema1 reopens intact when planning namespace and events are absent',
    () async {
      final original = await LabStore.open(workspace, office: true);
      stores.add(original);
      original.setSetting('syntheticLegacySetting', {'retain': 'exact'});
      original.event('synthetic-legacy-event', {'retain': 'exact'});
      final saved = savedSettingsAndEvents(original);
      await close(original);
      final opened = await LabStore.open(workspace, office: true);
      stores.add(opened);
      expect(opened.db.select('PRAGMA user_version').single.values.single, 1);
      expect(savedSettingsAndEvents(opened), saved);
      expect(opened.setting(correctivePlanningSetting), isNull);
      (proof['checks'] as Json)['legacy-schema1-absent'] = {
        'opened': true,
        'databaseVersion': 1,
        'savedSettingsAndEventsUnchanged': true,
        'savedStateSha256': digest(utf8.encode(saved)),
      };
    },
  );

  for (final oldVersion in [0, 1]) {
    for (final channel in ['namespace', 'event']) {
      test(
        'Legacy schema$oldVersion refuses saved planning $channel retaining file bytes',
        () async {
          // A genuine pending command isolates namespace detection; an accepted
          // receipt event with the namespace missing isolates event detection.
          await fixture(accepted: channel == 'event');
          mutateFixture((db) {
            if (channel == 'event') {
              db.execute('DELETE FROM settings WHERE key=?', [
                correctivePlanningSetting,
              ]);
            }
            db.execute('PRAGMA user_version=$oldVersion');
          });
          await refusedWithoutWrites(
            'legacy-schema$oldVersion-$channel',
            () => LabStore.open(workspace, office: true, maintenanceOnly: true),
            isA<StateError>().having(
              (error) => error.message,
              'format coherence retention message',
              contains('files have been retained'),
            ),
          );
        },
      );
    }
  }
}
