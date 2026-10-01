import 'dart:async';
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/local_sync.dart';
import 'package:maintenance_local/maintenance_domain.dart';
import 'package:maintenance_local/model.dart';
import 'package:maintenance_local/office_backup.dart';
import 'package:maintenance_local/procedure_library_store.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';
import 'package:sqlite3/sqlite3.dart';

import 'support/procedure_library_fixture.dart';

/// The real store has a fixed process role. This interface adapter keeps its
/// actual queue and SQLite transaction while simulating authority expiring
/// between a command being enqueued and executed.
class _QueuedAuthorityStore implements LabStore {
  _QueuedAuthorityStore(this.inner);
  final LabStore inner;
  bool authorized = true;
  int checks = 0;

  @override
  bool get office => authorized;
  @override
  Database get db => inner.db;
  @override
  SerialQueue get queue => inner.queue;
  @override
  Json? get catalog => inner.catalog;
  @override
  List<Json> get templates => inner.templates;
  @override
  String get device => inner.device;
  @override
  String stamp() => inner.stamp();
  @override
  dynamic setting(String key) => inner.setting(key);
  @override
  void setSetting(String key, Object? value) => inner.setSetting(key, value);
  @override
  void transaction(void Function() action) => inner.transaction(action);
  @override
  void event(String kind, Json data) => inner.event(kind, data);
  @override
  void requireOffice() {
    checks++;
    if (!authorized) throw StateError('Synthetic office authority expired.');
    inner.requireOffice();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() async {
    await RustLib.init(
      externalLibrary: ExternalLibrary.open(
        File(
          Platform.environment['MAINTENANCE_NATIVE_LIBRARY'] ??
              'rust/target/debug/librust_lib_sync_lab.so',
        ).absolute.path,
      ),
    );
  });

  late Directory root;
  late LabStore office;
  late Json source;
  final stores = <LabStore>[];
  Directory path(String name) => Directory('${root.path}/$name');

  Future<LabStore> open(String name, {bool officeRole = true}) async {
    final store = await LabStore.open(
      path(name),
      office: officeRole,
      maintenanceOnly: true,
      now: () => DateTime.utc(2026, 10, 1, 12),
    );
    stores.add(store);
    return store;
  }

  Future<void> close(LabStore store) async {
    await store.close();
    stores.remove(store);
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('lf003-procedure-regression-');
    office = await open('office');
    await office.createCompany(
      'Synthetic procedure regression company',
      coordinatorName: 'Synthetic coordinator',
    );
    source = await office.publishChecklist(
      title: 'Synthetic source procedure',
      items: procedureFixtureItems(),
      provenance: {
        'kind': 'manual-reference',
        'reference': 'Synthetic page 12',
      },
    );
  });

  tearDown(() async {
    for (final store in stores) {
      await store.close();
    }
    stores.clear();
    await root.delete(recursive: true);
  });

  String savedState(LabStore store) => canonical({
    'settings': [
      for (final row in store.db.select(
        'SELECT key,value FROM settings ORDER BY key',
      ))
        {'key': row['key'], 'value': row['value']},
    ],
    'events': [
      for (final row in store.db.select(
        'SELECT id,kind,payload FROM events ORDER BY id',
      ))
        {'id': row['id'], 'kind': row['kind'], 'payload': row['payload']},
    ],
    'documents': [
      for (final row in store.db.select(
        'SELECT id,bytes FROM documents ORDER BY id',
      ))
        {'id': row['id'], 'hash': digest(row['bytes'] as List<int>)},
    ],
  });

  Future<Json> copy({String operationId = 'copy-a'}) => office
      .copyProcedureDraft(source['id'] as String, operationId: operationId);

  Future<Object> outcome(Future<Json> command) async {
    try {
      return await command;
    } catch (error) {
      return error;
    }
  }

  Future<void> unchangedFailure(Future<Json> Function() command) async {
    final before = savedState(office);
    await expectLater(command(), throwsStateError);
    expect(savedState(office), before);
  }

  test(
    'simultaneous editors have one winner and stale save cannot clobber it',
    () async {
      final draft = await copy();
      final draftId = draft['id'] as String;
      final first = procedureItems(draft)
        ..first['label'] = 'Editor one instruction';
      final second = procedureItems(draft)
        ..first['label'] = 'Editor two instruction';
      final outcomes = await Future.wait([
        outcome(
          office.saveProcedureDraft(
            draftId: draftId,
            expectedRevision: 1,
            title: 'Editor one',
            items: first,
            operationId: 'save-one',
          ),
        ),
        outcome(
          office.saveProcedureDraft(
            draftId: draftId,
            expectedRevision: 1,
            title: 'Editor two',
            items: second,
            operationId: 'save-two',
          ),
        ),
      ]);
      expect(outcomes.whereType<Json>(), hasLength(1));
      expect(outcomes.whereType<StateError>(), hasLength(1));
      final winner = outcomes.whereType<Json>().single;
      expect(winner['revision'], 2);
      expect(office.procedureDrafts.single, winner);
      await unchangedFailure(
        () => office.saveProcedureDraft(
          draftId: draftId,
          expectedRevision: 1,
          title: 'Stale later save',
          items: second,
          operationId: 'stale-save',
        ),
      );
      await unchangedFailure(
        () => office.publishProcedureDraft(
          draftId: draftId,
          expectedRevision: 1,
          operationId: 'stale-publish',
        ),
      );
      expect(office.procedureDrafts.single, winner);
    },
  );

  test(
    'simultaneous exact retries create one draft, one revision and one publication',
    () async {
      final eventCount = office.db.select('SELECT id FROM events').length;
      final copied = await Future.wait([copy(), copy()]);
      expect(copied[0], copied[1]);
      expect(office.procedureDrafts, hasLength(1));
      final draft = copied.first;
      Future<Json> save() => office.saveProcedureDraft(
        draftId: draft['id'] as String,
        expectedRevision: 1,
        title: 'Concurrent exact retry',
        items: procedureItems(draft),
        operationId: 'save-a',
      );
      final saved = await Future.wait([save(), save()]);
      expect(saved[0], saved[1]);
      expect(office.procedureDrafts.single['revision'], 2);
      Future<Json> publish() => office.publishProcedureDraft(
        draftId: draft['id'] as String,
        expectedRevision: 2,
        operationId: 'publish-a',
      );
      final published = await Future.wait([publish(), publish()]);
      expect(published[0], published[1]);
      expect(office.templates, hasLength(2));
      expect(
        office.db.select('SELECT id FROM events'),
        hasLength(eventCount + 3),
      );
    },
  );

  test(
    'queued save captures caller input before later editor mutations',
    () async {
      final draft = await copy();
      final inputs = procedureItems(draft);
      final capturedInputs = procedureItems(draft);
      final gate = Completer<void>();
      final entered = Completer<void>();
      final blocker = office.queue.run(() async {
        entered.complete();
        await gate.future;
      });
      await entered.future;
      final save = office.saveProcedureDraft(
        draftId: draft['id'] as String,
        expectedRevision: 1,
        title: 'Captured title',
        items: inputs,
        operationId: 'save-a',
      );
      inputs[0]['label'] = 'Edited while queued';
      inputs[1]['min'] = 123;
      inputs.clear();
      gate.complete();
      await blocker;
      final saved = await save;
      expect(saved['items'], capturedInputs);
      expect(office.procedureDrafts.single['items'], capturedInputs);
      final before = savedState(office);
      expect(
        await office.saveProcedureDraft(
          draftId: draft['id'] as String,
          expectedRevision: 1,
          title: 'Captured title',
          items: capturedInputs,
          operationId: 'save-a',
        ),
        saved,
      );
      expect(savedState(office), before);
    },
  );

  test(
    'copy and save receipts replay their exact earlier result after later edits and restart',
    () async {
      final copied = await copy();
      final firstItems = procedureItems(copied);
      firstItems[0]['label'] = 'First saved instruction';
      final saved = await office.saveProcedureDraft(
        draftId: copied['id'] as String,
        expectedRevision: 1,
        title: 'First saved title',
        items: firstItems,
        operationId: 'save-a',
      );
      final later = await office.saveProcedureDraft(
        draftId: copied['id'] as String,
        expectedRevision: 2,
        title: 'Later title',
        items: procedureItems(saved),
        operationId: 'save-b',
      );
      await close(office);
      office = await open('office');
      final before = savedState(office);
      expect(await copy(), copied);
      expect(
        await office.saveProcedureDraft(
          draftId: copied['id'] as String,
          expectedRevision: 1,
          title: 'First saved title',
          items: firstItems,
          operationId: 'save-a',
        ),
        saved,
      );
      expect(office.procedureDrafts.single, later);
      expect(savedState(office), before);
    },
  );

  test(
    'changed operation reuse rejects every bound argument and cross-command reuse',
    () async {
      final draft = await copy();
      final otherSource = await office.publishChecklist(
        title: 'Other synthetic source',
        items: procedureFixtureItems(),
      );
      await unchangedFailure(
        () => office.copyProcedureDraft(
          otherSource['id'] as String,
          operationId: 'copy-a',
        ),
      );
      final saved = await office.saveProcedureDraft(
        draftId: draft['id'] as String,
        expectedRevision: 1,
        title: 'Saved title',
        items: procedureItems(draft),
        operationId: 'save-a',
      );
      final otherDraft = await copy(operationId: 'copy-b');
      final changedItems = procedureItems(draft)..first['allow_na'] = false;
      final failures = <Future<Json> Function()>[
        () => office.saveProcedureDraft(
          draftId: otherDraft['id'] as String,
          expectedRevision: 1,
          title: 'Saved title',
          items: procedureItems(draft),
          operationId: 'save-a',
        ),
        () => office.saveProcedureDraft(
          draftId: draft['id'] as String,
          expectedRevision: 2,
          title: 'Saved title',
          items: procedureItems(draft),
          operationId: 'save-a',
        ),
        () => office.saveProcedureDraft(
          draftId: draft['id'] as String,
          expectedRevision: 1,
          title: 'Changed title',
          items: procedureItems(draft),
          operationId: 'save-a',
        ),
        () => office.saveProcedureDraft(
          draftId: draft['id'] as String,
          expectedRevision: 1,
          title: 'Saved title',
          items: changedItems,
          operationId: 'save-a',
        ),
        () => office.saveProcedureDraft(
          draftId: draft['id'] as String,
          expectedRevision: 2,
          title: 'Cross-command',
          items: procedureItems(saved),
          operationId: 'copy-a',
        ),
        () => office.copyProcedureDraft(
          source['id'] as String,
          operationId: 'save-a',
        ),
        () => office.publishProcedureDraft(
          draftId: draft['id'] as String,
          expectedRevision: 2,
          operationId: 'save-a',
        ),
      ];
      for (final failure in failures) {
        await unchangedFailure(failure);
      }
    },
  );

  test(
    'published draft is read-only while durable publish retry returns its single publication',
    () async {
      final draft = await copy();
      final publication = await office.publishProcedureDraft(
        draftId: draft['id'] as String,
        expectedRevision: 1,
        operationId: 'publish-a',
      );
      expect(publication['version'], 1);
      expect(publication['id'], isNot(source['id']));
      final finalized = office.procedureDrafts.single;
      expect(finalized['publishedTemplateId'], publication['id']);
      await close(office);
      office = await open('office');
      final before = savedState(office);
      expect(
        await office.publishProcedureDraft(
          draftId: draft['id'] as String,
          expectedRevision: 1,
          operationId: 'publish-a',
        ),
        publication,
      );
      expect(await copy(), draft);
      expect(savedState(office), before);
      expect(office.templates, hasLength(2));
      await unchangedFailure(
        () => office.publishProcedureDraft(
          draftId: draft['id'] as String,
          expectedRevision: 2,
          operationId: 'publish-a',
        ),
      );
      await unchangedFailure(
        () => office.publishProcedureDraft(
          draftId: draft['id'] as String,
          expectedRevision: 1,
          operationId: 'publish-again',
        ),
      );
      await unchangedFailure(
        () => office.saveProcedureDraft(
          draftId: draft['id'] as String,
          expectedRevision: 1,
          title: 'Edit finalized',
          items: procedureItems(draft),
          operationId: 'save-finalized',
        ),
      );
      final otherDraft = await copy(operationId: 'copy-other');
      await unchangedFailure(
        () => office.publishProcedureDraft(
          draftId: otherDraft['id'] as String,
          expectedRevision: 1,
          operationId: 'publish-a',
        ),
      );
    },
  );

  test(
    'save replay remains exact even after its draft was published',
    () async {
      final draft = await copy();
      final saved = await office.saveProcedureDraft(
        draftId: draft['id'] as String,
        expectedRevision: 1,
        title: 'Saved before publication',
        items: procedureItems(draft),
        operationId: 'save-a',
      );
      await office.publishProcedureDraft(
        draftId: draft['id'] as String,
        expectedRevision: 2,
        operationId: 'publish-a',
      );
      final before = savedState(office);
      expect(
        await office.saveProcedureDraft(
          draftId: draft['id'] as String,
          expectedRevision: 1,
          title: 'Saved before publication',
          items: procedureItems(draft),
          operationId: 'save-a',
        ),
        saved,
      );
      expect(savedState(office), before);
      expect(office.procedureDrafts.single['publishedTemplateId'], isNotNull);
    },
  );

  test(
    'unfinished edits persist through restart and strict publication failure does not consume retry ID',
    () async {
      final draft = await copy();
      final unfinished = await office.saveProcedureDraft(
        draftId: draft['id'] as String,
        expectedRevision: 1,
        title: '',
        items: [],
        operationId: 'save-empty',
      );
      await close(office);
      office = await open('office');
      expect(office.procedureDrafts.single, unfinished);
      await unchangedFailure(
        () => office.publishProcedureDraft(
          draftId: draft['id'] as String,
          expectedRevision: 2,
          operationId: 'publish-retry',
        ),
      );
      final completed = await office.saveProcedureDraft(
        draftId: draft['id'] as String,
        expectedRevision: 2,
        title: 'Completed later',
        items: procedureItems(draft),
        operationId: 'save-complete',
      );
      final publication = await office.publishProcedureDraft(
        draftId: draft['id'] as String,
        expectedRevision: completed['revision'] as int,
        operationId: 'publish-retry',
      );
      expect(publication['title'], 'Completed later');
      expect(office.templates, hasLength(2));
    },
  );

  test(
    'return values and library reads are detached from durable nested state',
    () async {
      final draft = await copy();
      final before = savedState(office);
      final originalCopy = procedureCopy(draft);
      expect(
        () => draft['items'][0]['label'] = 'Caller mutation',
        throwsUnsupportedError,
      );
      expect(
        () => draft['source']['title'] = 'Caller source mutation',
        throwsUnsupportedError,
      );
      expect(
        () => draft['provenance']['reference'] = 'Caller reference mutation',
        throwsUnsupportedError,
      );
      final read = office.procedureDrafts;
      expect(
        () => read.single['items'][1]['min'] = 999,
        throwsUnsupportedError,
      );
      expect(() => read.clear(), throwsUnsupportedError);
      expect(savedState(office), before);
      expect(await copy(), originalCopy);
      final saved = await office.saveProcedureDraft(
        draftId: originalCopy['id'] as String,
        expectedRevision: 1,
        title: 'Saved',
        items: procedureItems(originalCopy),
        operationId: 'save-a',
      );
      final storedSave = procedureCopy(saved);
      expect(() => saved['items'][1]['unit'] = 'psi', throwsUnsupportedError);
      expect(office.procedureDrafts.single, storedSave);
      final publication = await office.publishProcedureDraft(
        draftId: originalCopy['id'] as String,
        expectedRevision: 2,
        operationId: 'publish-a',
      );
      final storedPublication = procedureCopy(publication);
      expect(
        () => publication['items'][1]['min'] = 444,
        throwsUnsupportedError,
      );
      expect(
        () => publication['provenance']['reference'] = 'Changed result',
        throwsUnsupportedError,
      );
      expect(office.templates.last, storedPublication);
      expect(
        await office.publishProcedureDraft(
          draftId: originalCopy['id'] as String,
          expectedRevision: 2,
          operationId: 'publish-a',
        ),
        storedPublication,
      );
    },
  );

  test(
    'copy, edit and publish preserve source and previously issued work bytes',
    () async {
      final equipment = await office.addEquipment(
        name: 'Synthetic pump',
        meterUnit: 'none',
      );
      final oldJob = await office.prepareWork(
        equipmentId: equipment['id'] as String,
        templateId: source['id'] as String,
        title: 'Previously issued synthetic work',
      );
      final oldContext = canonical(
        office.jobContextFor(oldJob['id'] as String),
      );
      final oldDocument = digest(office.documentFor(oldJob['id'] as String)!);
      final sourceBefore = canonical(source);
      final draft = await copy();
      final items = procedureItems(draft);
      items[0]['label'] = 'Independent changed instruction';
      items[1]['unit'] = 'psi';
      items[1]['min'] = 12;
      await office.saveProcedureDraft(
        draftId: draft['id'] as String,
        expectedRevision: 1,
        title: 'Independent changed title',
        items: items,
        operationId: 'save-a',
      );
      final publication = await office.publishProcedureDraft(
        draftId: draft['id'] as String,
        expectedRevision: 2,
        operationId: 'publish-a',
      );
      final newJob = await office.prepareWork(
        equipmentId: equipment['id'] as String,
        templateId: publication['id'] as String,
        title: 'New independent work',
      );
      expect(canonical(office.templates.first), sourceBefore);
      expect(
        canonical(office.jobContextFor(oldJob['id'] as String)),
        oldContext,
      );
      expect(digest(office.documentFor(oldJob['id'] as String)!), oldDocument);
      expect(newJob['checklistSnapshot'], publication);
      expect(newJob['snapshotHash'], contentHash(publication));
      expect(oldJob['snapshotHash'], isNot(newJob['snapshotHash']));
      validateCatalog(office.catalog!);
    },
  );

  test(
    'null, zero, empty and missing reading definitions survive saves, publication and restart',
    () async {
      final draft = await copy();
      await office.saveProcedureDraft(
        draftId: draft['id'] as String,
        expectedRevision: 1,
        title: 'Reading definitions',
        items: procedureItems(draft),
        operationId: 'save-a',
      );
      final publication = await office.publishProcedureDraft(
        draftId: draft['id'] as String,
        expectedRevision: 2,
        operationId: 'publish-a',
      );
      await close(office);
      office = await open('office');
      expect(office.templates.last, publication);
      expect(office.procedureDrafts.single['items'], draft['items']);
      final items = procedureItems(publication);
      expect(items[1]['unit'], 'bar');
      expect(items[1]['min'], 0);
      expect(items[1].containsKey('max'), isTrue);
      expect(items[1]['max'], isNull);
      expect(items[2].containsKey('unit'), isTrue);
      expect(items[2]['unit'], isNull);
      expect(items[2]['max'], 0);
      for (final key in ['unit', 'min', 'max']) {
        expect(items[3].containsKey(key), isFalse);
      }
      expect(items[4]['unit'], '');
      expect(items[0]['required'], isFalse);
      expect(items[0]['allow_na'], isTrue);
    },
  );

  test(
    'public catalog and phone import retain strict existing shape without office drafts or receipts',
    () async {
      final draft = await copy();
      final publication = await office.publishProcedureDraft(
        draftId: draft['id'] as String,
        expectedRevision: 1,
        operationId: 'publish-a',
      );
      final unfinished = await copy(operationId: 'private-copy');
      await office.saveProcedureDraft(
        draftId: unfinished['id'] as String,
        expectedRevision: 1,
        title: 'Private unfinished office title',
        items: [],
        operationId: 'private-save',
      );
      final bundle = await office.publicBundle();
      expect(bundle.keys.toSet(), {
        'format',
        'version',
        'catalog',
        'officeDevice',
        'documents',
        'submissions',
        'receipts',
        'blobs',
        'savedAt',
      });
      expect((bundle['catalog'] as Json).keys.toSet(), {
        'version',
        'companyId',
        'company',
        'coordinatorName',
        'equipment',
        'templates',
        'jobs',
      });
      expect(bundle['receipts'], isEmpty);
      validateCatalog(bundle['catalog'] as Json);
      final encoded = canonical(bundle);
      expect(encoded, isNot(contains('procedureLibrary')));
      expect(encoded, isNot(contains('private-copy')));
      expect(encoded, isNot(contains('Private unfinished office title')));
      expect(encoded, isNot(contains('expectedRevision')));
      final phone = await open('phone', officeRole: false);
      await phone.importOfficeBundle(bundle);
      expect(phone.templates, [source, publication]);
      expect(phone.setting('procedureLibrary'), isNull);
      expect(
        phone.db.select("SELECT * FROM settings WHERE key='procedureLibrary'"),
        isEmpty,
      );
      expect(() => phone.procedureDrafts, throwsStateError);
      final before = savedState(phone);
      for (final command in <Future<Json> Function()>[
        () => phone.copyProcedureDraft(
          source['id'] as String,
          operationId: 'phone-copy',
        ),
        () => phone.saveProcedureDraft(
          draftId: draft['id'] as String,
          expectedRevision: 1,
          title: 'Phone edit',
          items: procedureItems(draft),
          operationId: 'phone-save',
        ),
        () => phone.publishProcedureDraft(
          draftId: draft['id'] as String,
          expectedRevision: 1,
          operationId: 'phone-publish',
        ),
      ]) {
        await expectLater(command(), throwsStateError);
        expect(savedState(phone), before);
      }
    },
  );

  test(
    'queued copy, save, publish and replay recheck office authority at execution',
    () async {
      final draft = await copy();
      final adapter = _QueuedAuthorityStore(office);
      final gate = Completer<void>();
      final entered = Completer<void>();
      final blocker = office.queue.run(() async {
        entered.complete();
        await gate.future;
      });
      await entered.future;
      final pending = <Future<Object>>[
        outcome(
          adapter.copyProcedureDraft(
            source['id'] as String,
            operationId: 'queued-copy',
          ),
        ),
        outcome(
          adapter.saveProcedureDraft(
            draftId: draft['id'] as String,
            expectedRevision: 1,
            title: 'Queued save',
            items: procedureItems(draft),
            operationId: 'queued-save',
          ),
        ),
        outcome(
          adapter.publishProcedureDraft(
            draftId: draft['id'] as String,
            expectedRevision: 1,
            operationId: 'queued-publish',
          ),
        ),
        outcome(
          adapter.copyProcedureDraft(
            source['id'] as String,
            operationId: 'copy-a',
          ),
        ),
      ];
      final checksBefore = adapter.checks;
      final before = savedState(office);
      adapter.authorized = false;
      gate.complete();
      await blocker;
      final results = await Future.wait(pending);
      expect(results.whereType<StateError>(), hasLength(4));
      expect(adapter.checks, greaterThanOrEqualTo(checksBefore + 4));
      expect(savedState(office), before);
    },
  );

  test(
    'transaction failure rolls back drafts, receipts, publications and events for all commands',
    () async {
      Future<void> failEvent(Future<Json> Function() command) async {
        office.db.execute(
          "CREATE TRIGGER synthetic_procedure_event_failure BEFORE INSERT ON events "
          "BEGIN SELECT RAISE(ABORT, 'synthetic event failure'); END",
        );
        final before = savedState(office);
        try {
          await expectLater(command(), throwsA(isA<SqliteException>()));
          expect(savedState(office), before);
        } finally {
          office.db.execute('DROP TRIGGER synthetic_procedure_event_failure');
        }
      }

      await failEvent(() => copy());
      final draft = await copy();
      Future<Json> save() => office.saveProcedureDraft(
        draftId: draft['id'] as String,
        expectedRevision: 1,
        title: 'Transaction saved',
        items: procedureItems(draft),
        operationId: 'save-a',
      );
      await failEvent(save);
      await save();
      Future<Json> publish() => office.publishProcedureDraft(
        draftId: draft['id'] as String,
        expectedRevision: 2,
        operationId: 'publish-a',
      );
      await failEvent(publish);
      final publication = await publish();
      expect(office.templates, hasLength(2));
      expect(
        office.procedureDrafts.single['publishedTemplateId'],
        publication['id'],
      );
    },
  );

  test(
    'invalid or unknown commands leave state unchanged and do not poison serial queue',
    () async {
      final draft = await copy();
      await unchangedFailure(
        () => office.copyProcedureDraft('unknown', operationId: 'unknown-copy'),
      );
      await unchangedFailure(
        () =>
            office.copyProcedureDraft(source['id'] as String, operationId: ''),
      );
      await unchangedFailure(
        () => office.saveProcedureDraft(
          draftId: 'unknown',
          expectedRevision: 1,
          title: 'Unknown',
          items: [],
          operationId: 'unknown-save',
        ),
      );
      await unchangedFailure(
        () => office.publishProcedureDraft(
          draftId: 'unknown',
          expectedRevision: 1,
          operationId: 'unknown-publish',
        ),
      );
      final invalidItems = procedureItems(draft)..first['required'] = null;
      await unchangedFailure(
        () => office.saveProcedureDraft(
          draftId: draft['id'] as String,
          expectedRevision: 1,
          title: 'Invalid',
          items: invalidItems,
          operationId: 'invalid-save',
        ),
      );
      final valid = await office.saveProcedureDraft(
        draftId: draft['id'] as String,
        expectedRevision: 1,
        title: 'Valid after rejection',
        items: procedureItems(draft),
        operationId: 'invalid-save',
      );
      expect(valid['revision'], 2);
    },
  );

  test(
    'malformed stored library fails closed at every boundary without overwriting retained bytes',
    () async {
      final draft = await copy();
      await office.saveProcedureDraft(
        draftId: draft['id'] as String,
        expectedRevision: 1,
        title: 'Saved',
        items: procedureItems(draft),
        operationId: 'save-a',
      );
      final valid = procedureCopy(office.setting('procedureLibrary') as Json);
      final malformed = <Object?>[
        null,
        [],
        {'version': 2, 'drafts': [], 'receipts': []},
        {'version': 1, 'drafts': [], 'receipts': [], 'future': true},
        procedureCopy(valid)..['drafts'] = {},
        procedureCopy(valid)..['receipts'] = {},
        procedureCopy(valid)..['drafts'][0]['revision'] = 0,
        procedureCopy(valid)
          ..['drafts'][0]['title'] = 'Rewritten without receipt',
        procedureCopy(valid)
          ..['drafts'].add(procedureCopy(valid['drafts'][0] as Json)),
        procedureCopy(valid)
          ..['receipts'].add(procedureCopy(valid['receipts'][0] as Json)),
        procedureCopy(valid)..['receipts'][0]['hash'] = '0' * 64,
        procedureCopy(valid)
          ..['drafts'][0]['publishedTemplateId'] = 'missing-publication',
      ];
      final changedReceipt = procedureCopy(valid);
      changedReceipt['receipts'][1]['result']['title'] =
          'Rehashed receipt rewrite';
      final receipt = changedReceipt['receipts'][1] as Json;
      receipt['hash'] = contentHash({...receipt}..remove('hash'));
      malformed.add(changedReceipt);
      final changedArguments = procedureCopy(valid);
      changedArguments['receipts'][1]['arguments']['expectedRevision'] = 2;
      final argumentReceipt = changedArguments['receipts'][1] as Json;
      argumentReceipt['hash'] = contentHash(
        {...argumentReceipt}..remove('hash'),
      );
      malformed.add(changedArguments);
      for (var i = 0; i < malformed.length; i++) {
        office.setSetting('procedureLibrary', malformed[i]);
        final before = savedState(office);
        expect(
          () => office.procedureDrafts,
          throwsStateError,
          reason: 'state $i',
        );
        await expectLater(
          copy(operationId: 'corrupt-copy-$i'),
          throwsStateError,
        );
        await expectLater(
          office.saveProcedureDraft(
            draftId: draft['id'] as String,
            expectedRevision: 2,
            title: 'Do not overwrite',
            items: procedureItems(draft),
            operationId: 'corrupt-save-$i',
          ),
          throwsStateError,
        );
        await expectLater(
          office.publishProcedureDraft(
            draftId: draft['id'] as String,
            expectedRevision: 2,
            operationId: 'corrupt-publish-$i',
          ),
          throwsStateError,
        );
        expect(savedState(office), before, reason: 'state $i retained');
      }
      office.setSetting('procedureLibrary', valid);
      office.db.execute(
        "UPDATE settings SET value='{' WHERE key='procedureLibrary'",
      );
      final before = savedState(office);
      expect(() => office.procedureDrafts, throwsA(anything));
      await expectLater(
        copy(operationId: 'invalid-json-copy'),
        throwsA(anything),
      );
      expect(savedState(office), before);
      office.setSetting('procedureLibrary', valid);
      expect(office.procedureDrafts.single['revision'], 2);
    },
  );

  test(
    'backup and same-identity restore retain private drafts and replay receipts at snapshot boundary',
    () async {
      final draft = await copy();
      final saved = await office.saveProcedureDraft(
        draftId: draft['id'] as String,
        expectedRevision: 1,
        title: 'Backed-up draft',
        items: procedureItems(draft),
        operationId: 'save-a',
      );
      final publication = await office.publishProcedureDraft(
        draftId: draft['id'] as String,
        expectedRevision: 2,
        operationId: 'publish-a',
      );
      final unfinished = await copy(operationId: 'copy-unfinished');
      final partial = await office.saveProcedureDraft(
        draftId: unfinished['id'] as String,
        expectedRevision: 1,
        title: '',
        items: [],
        operationId: 'save-unfinished',
      );
      final equipment = await office.addEquipment(
        name: 'Synthetic backed-up pump',
        meterUnit: 'none',
      );
      final issuedJob = await office.prepareWork(
        equipmentId: equipment['id'] as String,
        templateId: publication['id'] as String,
        title: 'Backed-up independent work',
      );
      final issuedJobId = issuedJob['id'] as String;
      final contextAtBackup = canonical(office.jobContextFor(issuedJobId));
      final documentAtBackup = digest(office.documentFor(issuedJobId)!);
      final libraryAtBackup = canonical(office.setting('procedureLibrary'));
      final catalogAtBackup = canonical(office.catalog);
      await OfficeIdentity.load(office);
      final backup = await OfficeBackup.create(office, path('backup'));
      await office.saveProcedureDraft(
        draftId: unfinished['id'] as String,
        expectedRevision: 2,
        title: 'Later excluded edit',
        items: procedureItems(unfinished),
        operationId: 'later-save',
      );
      await OfficeBackup.restore(
        path('backup'),
        path('restored'),
        expectedFingerprint: backup.fingerprint,
        requiredFormat: OfficeBackupFormat.maintenance,
      );
      final restored = await open('restored');
      expect(restored.device, office.device);
      expect(canonical(restored.setting('procedureLibrary')), libraryAtBackup);
      expect(canonical(restored.catalog), catalogAtBackup);
      expect(canonical(restored.jobContextFor(issuedJobId)), contextAtBackup);
      expect(digest(restored.documentFor(issuedJobId)!), documentAtBackup);
      expect(restored.procedureDrafts.last, partial);
      final before = savedState(restored);
      expect(
        await restored.copyProcedureDraft(
          source['id'] as String,
          operationId: 'copy-a',
        ),
        draft,
      );
      expect(
        await restored.saveProcedureDraft(
          draftId: draft['id'] as String,
          expectedRevision: 1,
          title: 'Backed-up draft',
          items: procedureItems(draft),
          operationId: 'save-a',
        ),
        saved,
      );
      expect(
        await restored.publishProcedureDraft(
          draftId: draft['id'] as String,
          expectedRevision: 2,
          operationId: 'publish-a',
        ),
        publication,
      );
      expect(savedState(restored), before);
      expect(
        canonical(restored.procedureDrafts),
        isNot(contains('Later excluded edit')),
      );
      await expectLater(
        restored.saveProcedureDraft(
          draftId: draft['id'] as String,
          expectedRevision: 1,
          title: 'Changed restored retry',
          items: procedureItems(draft),
          operationId: 'save-a',
        ),
        throwsStateError,
      );
      expect(savedState(restored), before);
    },
  );
}
