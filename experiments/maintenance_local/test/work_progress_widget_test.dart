import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:maintenance_local/job_progress.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/local_sync.dart';
import 'package:maintenance_local/model.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';
import 'package:maintenance_local/ui/inspection_page.dart';
import 'package:maintenance_local/ui/review_page.dart';
import 'package:maintenance_local/ui/work_progress.dart';
import 'package:maintenance_local/ui/workspace_page.dart';
import 'package:maintenance_local/work_progress_reader.dart';

SubmittedVersion _version(
  String id, {
  String device = 'phone',
  String? decision,
  String reason = 'Record the follow-up',
  int revision = 1,
}) => SubmittedVersion(
  submission: {
    'id': id,
    'jobId': 'job',
    'device': device,
    'documentHash': 'hash',
    'submissionRevision': revision,
    '_state': 'received',
  },
  receipt: decision == null ? null : {'decision': decision, 'reason': reason},
  photoState: PhotoState.complete,
);

JobProgress _progress({
  List<SubmittedVersion> current = const [],
  List<SubmittedVersion> history = const [],
}) => JobProgress(
  jobId: 'job',
  context: {},
  documentHash: 'hash',
  draftPhase: DraftPhase.ready,
  requiredAnswered: 1,
  requiredTotal: 1,
  conflictKeys: [],
  problem: null,
  photoState: PhotoState.complete,
  currentVersions: current,
  history: history,
  queuedVersions: [],
);

class _Fixture {
  _Fixture(this.root, this.store, this.first, this.second);
  final Directory root;
  final LabStore store;
  final String first, second;
  static Future<_Fixture> create() async {
    final root = await Directory.systemTemp.createTemp(
      'maintenance-progress-ui-',
    );
    final store = await LabStore.open(
      Directory('${root.path}/office'),
      office: true,
      maintenanceOnly: true,
    );
    await OfficeIdentity.load(store);
    await store.createCompany(
      'Synthetic progress company',
      coordinatorName: 'Sam Coordinator',
    );
    final equipment = await store.addEquipment(
      name: 'Synthetic excavator',
      meterUnit: 'none',
    );
    final template = await store.publishChecklist(
      title: 'Daily inspection',
      items: [
        {'id': 'guard', 'label': 'Inspect guard', 'input_type': 'check'},
      ],
      provenance: {'kind': 'company-authored'},
    );
    Future<String> prepare(String title) async =>
        (await store.prepareWork(
              equipmentId: equipment['id'] as String,
              templateId: template['id'] as String,
              title: title,
            ))['id']
            as String;
    return _Fixture(
      root,
      store,
      await prepare('Morning inspection'),
      await prepare('Evening inspection'),
    );
  }

  Future<void> fill(String jobId) async {
    await store.update({
      'answer:guard': {'result': 'action', 'value': ''},
      'notes': 'Guard finding recorded.',
    }, jobId: jobId);
    await store.attach(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ),
      jobId: jobId,
    );
  }

  Future<void> close() async {
    await store.close();
    await root.delete(recursive: true);
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(tester.takeException(), isNull);
}

Future<void> _until(WidgetTester tester, bool Function() predicate) async {
  for (var i = 0; i < 25 && !predicate(); i++) {
    await _settle(tester);
  }
  expect(predicate(), isTrue);
}

Future<_Fixture> _fixture(WidgetTester tester) async {
  final fixture = (await tester.runAsync(_Fixture.create))!;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await _settle(tester);
    var closed = false;
    final closing = fixture.close();
    unawaited(closing.then((_) => closed = true));
    await _until(tester, () => closed);
    await closing;
  });
  return fixture;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.runAsync(() => tester.tap(finder));
  await _settle(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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

  testWidgets(
    'Home periodic unchanged refresh keeps Backup hit target and scroll stable',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 915));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final fixture = await _fixture(tester);
      final captured = (await tester.runAsync(() async {
        await fixture.fill(fixture.first);
        final submission = await fixture.store.submit(jobId: fixture.first);
        await fixture.store.decide(submission['id'] as String, approve: true);
        return readWorkProgress(fixture.store);
      }))!;
      var pendingToken = Completer<String>();
      var holdRefresh = false, tokenReads = 0, progressReads = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: WorkspacePage(
            store: fixture.store,
            officePort: 0,
            progressReader: (_) async {
              progressReads++;
              return captured;
            },
            progressTokenReader: (_) async {
              tokenReads++;
              return holdRefresh ? pendingToken.future : captured.token;
            },
          ),
        ),
      );
      await _until(
        tester,
        () => find.text('Reviewed history (1)').evaluate().isNotEmpty,
      );
      final backup = find.widgetWithText(
        OutlinedButton,
        'Back up office computer',
      );
      await tester.ensureVisible(backup);
      await tester.pumpAndSettle();
      final scroll = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      final offsetBefore = scroll.position.pixels;
      final targetBefore = tester.getRect(backup);
      final readsBefore = tokenReads;
      expect(offsetBefore, greaterThan(0));
      expect(backup.hitTestable(), findsOneWidget);

      holdRefresh = true;
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
      expect(tokenReads, greaterThan(readsBefore));
      final targetPending = tester.getRect(backup);
      expect(
        targetPending.top,
        closeTo(targetBefore.top, 0.1),
        reason:
            'A pending unchanged token read must retain the Backup hit target.',
      );
      expect(scroll.position.pixels, closeTo(offsetBefore, 0.1));
      expect(backup.hitTestable(), findsOneWidget);
      expect(find.text('Updating work status…'), findsOneWidget);
      expect(find.text('Reviewed history (1)'), findsOneWidget);
      expect(find.text('Approved inspection'), findsOneWidget);

      holdRefresh = false;
      pendingToken.complete(captured.token);
      await tester.pump();
      await tester.pump();
      expect(find.text('Saved work status'), findsOneWidget);
      expect(tester.getRect(backup).top, closeTo(targetBefore.top, 0.1));
      expect(scroll.position.pixels, closeTo(offsetBefore, 0.1));
      expect(
        progressReads,
        1,
        reason: 'An unchanged token reuses the bulk read.',
      );
      await tester.tapAt(targetBefore.center);
      await tester.pumpAndSettle();
      expect(find.byType(WorkspacePage), findsNothing);
      expect(find.text('Back up office computer'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      final inspection = find
          .widgetWithText(FilledButton, 'Open inspection')
          .first;
      await tester.ensureVisible(inspection);
      await tester.pumpAndSettle();
      final inspectionTarget = tester.getRect(inspection);
      final focus = Focus.of(
        tester.element(find.text('Open inspection').first),
      );
      pendingToken = Completer<String>();
      holdRefresh = true;
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
      await tester.tapAt(inspectionTarget.center);
      await tester.pump();
      expect(find.byType(InspectionPage), findsNothing);
      expect(focus.canRequestFocus, isFalse);
      focus.requestFocus();
      await tester.pump();
      expect(focus.hasFocus, isFalse);

      holdRefresh = false;
      pendingToken.complete(captured.token);
      await tester.pump();
      await tester.pump();
      expect(focus.canRequestFocus, isTrue);
      await tester.tapAt(inspectionTarget.center);
      await _settle(tester);
      expect(find.byType(InspectionPage), findsOneWidget);
    },
  );

  testWidgets(
    'current records are excluded from earlier count and own-device reuse is explicit',
    (tester) async {
      final approved = _version('approved', decision: 'approved');
      final earlier = _version('earlier', decision: 'returned');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DraftProgressView(
              progress: _progress(
                current: [approved],
                history: [earlier, approved],
              ),
              localDevice: 'phone',
            ),
          ),
        ),
      );
      expect(
        find.text('1 earlier submitted version retained.'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Submitting this unchanged draft reuses its existing record.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Current submitted record'), findsOneWidget);
    },
  );

  testWidgets(
    'another actor current record does not promise idempotent local submission',
    (tester) async {
      final approved = _version(
        'approved',
        device: 'office',
        decision: 'approved',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DraftProgressView(
              progress: _progress(current: [approved], history: [approved]),
              localDevice: 'phone',
            ),
          ),
        ),
      );
      expect(
        find.text(
          'Submitting this unchanged draft reuses its existing record.',
        ),
        findsNothing,
      );
      expect(find.textContaining('earlier submitted'), findsNothing);
      expect(find.textContaining('Approved inspection'), findsOneWidget);
    },
  );

  testWidgets(
    'edited approved draft retains history without inheriting current approval',
    (tester) async {
      final approved = _version('approved', decision: 'approved');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DraftProgressView(
              progress: _progress(history: [approved]),
              localDevice: 'phone',
            ),
          ),
        ),
      );
      expect(
        find.textContaining('This draft has not been submitted'),
        findsOneWidget,
      );
      expect(find.textContaining('Current submitted record'), findsNothing);
      expect(
        find.text('1 earlier submitted version retained.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'pinned historical reason and exact current return appear once each',
    (tester) async {
      final old = _version(
        'old',
        decision: 'returned',
        reason: 'Earlier reason',
      );
      final current = _version(
        'current',
        decision: 'returned',
        reason: 'Current reason',
        revision: 2,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ReturnedWorkView(
                progress: _progress(
                  current: [current],
                  history: [old, current, current],
                ),
                correctionSubmissionId: old.id,
              ),
            ),
          ),
        ),
      );
      expect(find.text('Returned: Earlier reason'), findsOneWidget);
      expect(find.text('Earlier return reasons (1)'), findsOneWidget);
      await _tap(tester, find.text('Earlier return reasons (1)'));
      expect(find.text('Device version 2 · Current reason'), findsOneWidget);
    },
  );

  test(
    'existing submission messages name the unchanged decision or queue state',
    () {
      for (final decision in ['approved', 'returned', null]) {
        final message = submissionSavedMessage(
          _version('record', decision: decision),
          existing: true,
          office: false,
          sendingStatusShown: true,
        );
        expect(message, contains('Existing device version 1'));
        expect(message, isNot(contains('Version saved for review')));
        if (decision == 'returned') {
          expect(message, contains('Record the follow-up'));
        }
        if (decision == 'approved') {
          expect(message, contains('decision is unchanged'));
        }
        if (decision == null) {
          expect(message, contains('No new version was created'));
        }
      }
    },
  );

  test(
    'bulk controller ignores late generations and caches unchanged tokens',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final stale = Completer<WorkProgressSnapshot>();
      var token = 'old', reads = 0;
      final controller = WorkProgressController(
        fixture.store,
        tokenReader: (_) async => token,
        reader: (_) async {
          reads++;
          if (reads == 1) return stale.future;
          return WorkProgressSnapshot(
            token: token,
            jobs: {},
            undecided: [],
            reviewed: [],
          );
        },
      );
      addTearDown(controller.dispose);
      final first = controller.refresh();
      await Future<void>.delayed(Duration.zero);
      token = 'new';
      await controller.refresh();
      expect(controller.snapshot!.token, 'new');
      stale.complete(
        WorkProgressSnapshot(
          token: 'old',
          jobs: {},
          undecided: [],
          reviewed: [],
        ),
      );
      await first;
      expect(controller.snapshot!.token, 'new');
      expect(controller.displaySnapshot!.token, 'new');
      await controller.refresh();
      expect(reads, 2);
    },
  );

  test(
    'display progress preserves verified layout while pending and fails closed',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      var reads = 0, fail = false;
      Completer<String>? pending;
      final controller = WorkProgressController(
        fixture.store,
        tokenReader: (_) async {
          if (fail) throw StateError('Synthetic token read failure');
          return pending?.future ?? Future.value('stable');
        },
        reader: (_) async {
          reads++;
          return WorkProgressSnapshot(
            token: 'stable',
            jobs: {},
            undecided: [],
            reviewed: [],
          );
        },
      );
      addTearDown(controller.dispose);
      expect(controller.displaySnapshot, isNull);
      await controller.refresh();
      final verified = controller.snapshot;

      pending = Completer<String>();
      final refresh = controller.refresh();
      expect(controller.snapshot, isNull);
      expect(controller.displaySnapshot, same(verified));
      expect(controller.loading, isTrue);
      pending.complete('stable');
      await refresh;
      expect(controller.snapshot, same(verified));
      expect(controller.displaySnapshot, same(verified));
      expect(reads, 1);

      fail = true;
      await controller.refresh();
      expect(controller.snapshot, isNull);
      expect(controller.displaySnapshot, isNull);
      expect(controller.loading, isFalse);
      expect(controller.error, contains('could not be read'));

      fail = false;
      pending = null;
      await controller.refresh();
      expect(controller.snapshot, same(verified));
      expect(controller.error, isNull);
      expect(reads, 1);
    },
  );

  test(
    'disposed progress controller ignores a completed pending read',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final pending = Completer<WorkProgressSnapshot>();
      var notifications = 0;
      final controller = WorkProgressController(
        fixture.store,
        tokenReader: (_) async => 'pending',
        reader: (_) => pending.future,
      )..addListener(() => notifications++);
      final refresh = controller.refresh();
      await Future<void>.delayed(Duration.zero);
      final beforeDispose = notifications;
      controller.dispose();
      pending.complete(
        WorkProgressSnapshot(
          token: 'pending',
          jobs: {},
          undecided: [],
          reviewed: [],
        ),
      );
      await refresh;
      expect(controller.snapshot, isNull);
      expect(controller.displaySnapshot, isNull);
      expect(notifications, beforeDispose);
    },
  );

  test(
    'bulk controller hides approved snapshot immediately and retries overtaken token',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      var token = 'approved', reads = 0;
      final gate = Completer<void>();
      final controller = WorkProgressController(
        fixture.store,
        tokenReader: (_) async => token,
        reader: (_) async {
          reads++;
          final captured = token;
          if (reads == 2) {
            await gate.future;
            token = 'newer';
          }
          return WorkProgressSnapshot(
            token: captured,
            jobs: {},
            undecided: [],
            reviewed: [],
          );
        },
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      final approved = controller.snapshot;
      token = 'edited';
      final refresh = controller.refresh();
      expect(controller.snapshot, isNull);
      expect(controller.displaySnapshot, same(approved));
      expect(controller.loading, isTrue);
      gate.complete();
      await refresh;
      expect(controller.snapshot!.token, 'newer');
      expect(controller.displaySnapshot!.token, 'newer');
      expect(reads, 3);
    },
  );

  testWidgets(
    'returned record opens its pinned job and unchanged submit preserves decision',
    (tester) async {
      final fixture = await _fixture(tester);
      late Json submission;
      await tester.runAsync(() async {
        await fixture.fill(fixture.first);
        submission = await fixture.store.submit(jobId: fixture.first);
        await fixture.store.decide(
          submission['id'] as String,
          approve: false,
          reason: 'Record the guard follow-up',
        );
        fixture.store.selectJob(fixture.second);
      });
      await tester.pumpWidget(
        MaterialApp(home: WorkspacePage(store: fixture.store, officePort: 0)),
      );
      await _until(
        tester,
        () => find
            .byKey(ValueKey('submitted-version:${submission['id']}'))
            .evaluate()
            .isNotEmpty,
      );
      await _tap(
        tester,
        find.descendant(
          of: find.byKey(ValueKey('submitted-version:${submission['id']}')),
          matching: find.byType(ListTile),
        ),
      );
      await _tap(tester, find.text('Open current inspection'));
      expect(
        tester.widget<InspectionPage>(find.byType(InspectionPage)).jobId,
        fixture.first,
      );
      expect(
        tester
            .widget<InspectionPage>(find.byType(InspectionPage))
            .correctionSubmissionId,
        submission['id'],
      );
      await _until(
        tester,
        () => find
            .descendant(
              of: find.byType(InspectionPage),
              matching: find.text('Returned: Record the guard follow-up'),
            )
            .evaluate()
            .isNotEmpty,
      );
      await _tap(tester, find.text('Submit for review'));
      await _until(
        tester,
        () => find
            .textContaining('Existing device version 1 was returned')
            .evaluate()
            .isNotEmpty,
      );
      expect(fixture.store.submissions, hasLength(1));
      expect(fixture.store.receipts, hasLength(1));
      expect(
        find.textContaining('Existing device version 1 was returned'),
        findsOneWidget,
      );
      expect(fixture.store.receipts.single['decision'], 'returned');
    },
  );

  testWidgets(
    'office undecided queue is near work and older undecided survives newer approval',
    (tester) async {
      final fixture = await _fixture(tester);
      late Json old, current;
      await tester.runAsync(() async {
        await fixture.fill(fixture.first);
        old = await fixture.store.submit(jobId: fixture.first);
        await fixture.store.update({
          'notes': 'Newer follow-up recorded.',
        }, jobId: fixture.first);
        current = await fixture.store.submit(jobId: fixture.first);
        await fixture.store.queue.idle;
        await fixture.store.decide(current['id'] as String, approve: true);
      });
      await tester.pumpWidget(
        MaterialApp(home: WorkspacePage(store: fixture.store, officePort: 0)),
      );
      await _until(
        tester,
        () => find.text('Awaiting review (1)').evaluate().isNotEmpty,
      );
      expect(find.text('Reviewed history (1)'), findsOneWidget);
      final queueTop = tester.getTopLeft(find.text('Awaiting review (1)')).dy;
      final equipmentTop = tester.getTopLeft(find.text('Equipment')).dy;
      expect(queueTop, lessThan(equipmentTop));
      expect(
        find.byKey(ValueKey('submitted-version:${old['id']}')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('submitted-version:${current['id']}')),
        findsOneWidget,
      );
      expect(fixture.store.receipts.single['submissionId'], current['id']);
    },
  );

  testWidgets(
    'failed submit refreshes a standalone persisted draft without inheriting approval',
    (tester) async {
      final fixture = await _fixture(tester);
      late Json approved;
      late String approvedHash;
      await tester.runAsync(() async {
        await fixture.fill(fixture.first);
        approved = await fixture.store.submit(jobId: fixture.first);
        await fixture.store.decide(approved['id'] as String, approve: true);
        approvedHash = digest(fixture.store.documentFor(fixture.first)!);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: InspectionPage(store: fixture.store, jobId: fixture.first),
        ),
      );
      await _until(
        tester,
        () => find
            .textContaining('Current submitted record')
            .evaluate()
            .isNotEmpty,
      );
      await tester.ensureVisible(find.byKey(const Key('notes')));
      await tester.enterText(find.byKey(const Key('notes')), '');
      await _tap(tester, find.text('Submit for review'));
      await _until(
        tester,
        () => find
            .textContaining('Current draft: Incomplete')
            .evaluate()
            .isNotEmpty,
      );
      expect(
        digest(fixture.store.documentFor(fixture.first)!),
        isNot(approvedHash),
      );
      expect(find.textContaining('Current submitted record'), findsNothing);
      expect(
        find.textContaining('This draft has not been submitted'),
        findsOneWidget,
      );
      expect(fixture.store.submissions, hasLength(1));
      expect(fixture.store.receipts, hasLength(1));
      expect(fixture.store.receipts.single['submissionId'], approved['id']);
      await tester.runAsync(() async {
        expect(
          valuesOf(await fixture.store.fields(jobId: fixture.first))['notes'],
          '',
        );
      });
    },
  );

  testWidgets(
    'exact review remains disabled during queued read then exposes actual stale guard',
    (tester) async {
      final fixture = await _fixture(tester);
      late Json submission;
      await tester.runAsync(() async {
        await fixture.fill(fixture.first);
        submission = await fixture.store.submit(jobId: fixture.first);
      });
      final gate = Completer<void>();
      unawaited(fixture.store.queue.run(() => gate.future));
      await tester.pumpWidget(
        MaterialApp(
          home: ReviewPage(store: fixture.store, submission: submission),
        ),
      );
      await _settle(tester);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Approve this version'),
            )
            .onPressed,
        isNull,
      );
      gate.complete();
      await _until(
        tester,
        () =>
            tester
                .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Approve this version'),
                )
                .onPressed !=
            null,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(
        () => fixture.store.update({
          'notes': 'Changed after submission',
        }, jobId: fixture.first),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ReviewPage(store: fixture.store, submission: submission),
        ),
      );
      await _until(
        tester,
        () => find
            .text(
              'Work has changed. Return this version and request a new submission.',
            )
            .evaluate()
            .isNotEmpty,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Approve this version'),
            )
            .onPressed,
        isNull,
      );
      expect(fixture.store.receipts, isEmpty);
    },
  );
}
