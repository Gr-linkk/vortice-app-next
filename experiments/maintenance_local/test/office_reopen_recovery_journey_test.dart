import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/agent_service/access_scope.dart';
import 'package:maintenance_local/agent_service/proposal_store.dart';
import 'package:maintenance_local/app.dart';
import 'package:maintenance_local/lab_bootstrap.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/local_sync.dart';
import 'package:maintenance_local/model.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';
import 'package:maintenance_local/ui/restore_page.dart';
import 'package:maintenance_local/ui/workspace_page.dart';
import 'package:sqlite3/sqlite3.dart';

import 'support/native_widget_cleanup.dart';

// These are rendered Flutter journeys using the actual Rust/SQLite storage.
// They do not claim acceptance of the separately packaged GTK executable.
// Every identity, workspace, proposal and archive is synthetic and temporary.
const _boundary = Key('office-reopen-recovery-journey');
const _company = 'Synthetic recovery workshop';
const _originalNotes = 'Synthetic original guard inspection notes.';
const _suggestion =
    'Synthetic suggested notes: inspect guard clearance before the next shift.';
const _restoreFailure =
    'Office restore failed. Use a complete office backup with the expected '
    'identity and an absent destination. Existing data was retained.';

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pump(const Duration(milliseconds: 200));
  expect(
    tester.takeException(),
    isNull,
    reason: 'The real journey must render without errors or overflow.',
  );
}

Future<void> _until(WidgetTester tester, bool Function() complete) async {
  for (var attempt = 0; attempt < 40; attempt++) {
    if (complete()) {
      // A native result can install the next route after the previous pump.
      // Finish its frame/transition before looking for user-facing controls.
      await _settle(tester);
      if (complete()) return;
    }
    await _settle(tester);
  }
  expect(complete(), isTrue, reason: 'The native UI command must finish.');
}

Future<void> _show(WidgetTester tester, Finder finder) async {
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 250));
  expect(
    finder.hitTestable(),
    findsOneWidget,
    reason: 'The action must be reachable at the selected text size.',
  );
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _show(tester, finder);
  await tester.tap(finder);
  await _settle(tester);
}

Future<void> _enter(WidgetTester tester, String key, String value) async {
  final finder = find.byKey(Key(key));
  await _show(tester, finder);
  // The busy backup check detaches the previous platform input connection.
  tester.binding.focusedEditable = null;
  await tester.enterText(finder, value);
  await _settle(tester);
}

Future<void> _capture(WidgetTester tester, String name) async {
  final output = Platform.environment['VORTICE_RENDER_OUTPUT'];
  if (output == null || output.isEmpty) return;
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_boundary),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$output/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
    } finally {
      image.dispose();
    }
  });
}

Future<void> _mount(WidgetTester tester, LabStore store, double scale) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await _settle(tester);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _boundary,
      child: LabApp(store: store, textScale: scale, officePort: 0),
    ),
  );
  await _settle(tester);
}

class _Journey {
  _Journey(this.root, this.source, this.identity, this.jobId)
    : sourceDevice = source.device,
      frozenContext = canonical(source.jobContextFor(jobId));
  final Directory root;
  final LabStore source;
  final OfficeIdentity identity;
  final String jobId;
  final String sourceDevice, frozenContext;
  final live = <LabStore>{};

  Directory get backup => Directory('${root.path}/backup');
  Directory get restored => Directory('${root.path}/restored');
  Directory get launcherRoot => Directory('${root.path}/original-launcher');

  static Future<_Journey> create() async {
    final root = await Directory.systemTemp.createTemp(
      'synthetic-office-reopen-journey-',
    );
    final source = await openLabWorkspace(
      Directory('${root.path}/source'),
      office: true,
      maintenanceOnly: true,
    );
    final identity = await OfficeIdentity.load(source);
    await source.createCompany(_company, coordinatorName: 'Synthetic Sam');
    final equipment = await source.addEquipment(
      name: 'Synthetic guard test rig',
      serial: 'SYNTHETIC-RECOVERY-ONLY',
      meterUnit: 'none',
    );
    final checklist = await source.publishChecklist(
      title: 'Synthetic guard checklist',
      items: [
        {'id': 'guard', 'label': 'Inspect guard', 'input_type': 'check'},
      ],
    );
    final job = await source.prepareWork(
      equipmentId: equipment['id'] as String,
      templateId: checklist['id'] as String,
      title: 'Synthetic recovery inspection',
    );
    final jobId = job['id'] as String;
    await source.update({'notes': _originalNotes}, jobId: jobId);
    final journey = _Journey(root, source, identity, jobId);
    journey.live.add(source);
    return journey;
  }

  Future<void> propose(String key, String notes) async {
    final scope = AgentAccessScope.forOffice(source)!;
    final result = await AgentProposalStore(source.root).create(
      grantId: 'synthetic-recovery-grant',
      actorId: 'Synthetic workshop helper',
      payload: {
        'type': 'inspection.notes',
        'job_id': jobId,
        'expected_document_hash': digest(source.documentFor(jobId)!),
        'notes': notes,
        'idempotency_key': key,
      },
      context: source.jobContextFor(jobId),
      scope: scope.toJson(),
      createdAt: DateTime.utc(2026, 10, 1, 12),
      authorize: () async {},
    );
    expect(result['status'], 'pending_human_review');
    expect(result['applied'], false);
  }

  void cleanup(WidgetTester tester) => addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await finishNativeWidgetCleanup(tester, () async {
      for (final store in live) {
        await store.close();
      }
      await root.delete(recursive: true);
    });
  });

  Future<void> stop(WidgetTester tester, LabStore store) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await _settle(tester);
    await finishNativeWidgetCleanup(tester, () async {
      await store.close();
      live.remove(store);
    });
  }

  Future<LabStore> openLauncher(WidgetTester tester) async {
    late LabStore store;
    await tester.runAsync(() async {
      // Always reopen from the original launcher, never directly at restored.
      store = await openLabWorkspace(
        launcherRoot,
        office: true,
        maintenanceOnly: true,
      );
      live.add(store);
    });
    return store;
  }

  LabStore restoredStore(WidgetTester tester, LabStore launcher) {
    final copy = tester.widget<WorkspacePage>(find.byType(WorkspacePage)).store;
    // Successful normal UI replacement closes the empty launcher itself.
    live.remove(launcher);
    live.add(copy);
    expect(copy.root.absolute.path, restored.absolute.path);
    expect(copy.device, sourceDevice);
    expect(canonical(copy.jobContextFor(jobId)), frozenContext);
    return copy;
  }
}

Future<void> _backupUi(
  WidgetTester tester,
  _Journey journey,
  String prefix,
) async {
  await _tap(tester, find.text('Back up office computer'));
  await _enter(tester, 'backupDestination', journey.backup.path);
  await _tap(tester, find.text('Create verified backup'));
  await _until(
    tester,
    () => find.textContaining('Backup verified:').evaluate().isNotEmpty,
  );
  await _show(tester, find.textContaining('Backup verified:'));
  await _capture(tester, '$prefix-backup-verified');
}

Future<void> _restoreForm(
  WidgetTester tester,
  _Journey journey,
  String destination,
) async {
  expect(find.text('Start with your company'), findsOneWidget);
  await _tap(tester, find.text('Restore office backup'));
  await _enter(tester, 'restoreSource', journey.backup.path);
  await _enter(tester, 'restoreDestination', destination);
  await _enter(tester, 'restoreFingerprint', journey.identity.fingerprint);
  await _tap(tester, find.text('Check backup'));
  await _until(
    tester,
    () => find.textContaining('Backup checked:').evaluate().isNotEmpty,
  );
  expect(tester.widget<FilledButton>(_restoreButton).onPressed, isNotNull);
}

Finder get _restoreButton =>
    find.widgetWithText(FilledButton, 'Restore verified office');

Future<void> _restoreUi(WidgetTester tester) async {
  await _tap(tester, _restoreButton);
  await _until(
    tester,
    () => find.textContaining('Office backup restored.').evaluate().isNotEmpty,
  );
}

Future<void> _inspectNotes(
  WidgetTester tester,
  String jobId,
  String notes,
  String capture,
) async {
  final open = find.descendant(
    of: find.byKey(ValueKey('inspection:$jobId')),
    matching: find.widgetWithText(FilledButton, 'Open inspection'),
  );
  await _tap(tester, open);
  await _until(tester, () {
    final fields = find.byKey(const Key('notes')).evaluate();
    return fields.isNotEmpty &&
        (fields.single.widget as TextField).controller!.text == notes;
  });
  await _show(tester, find.byKey(const Key('notes')));
  expect(
    tester.widget<TextField>(find.byKey(const Key('notes'))).controller!.text,
    notes,
  );
  await _capture(tester, capture);
  await _tap(tester, find.byType(BackButton).hitTestable());
}

Future<void> _historyUi(
  WidgetTester tester,
  LabStore store,
  String immutableReceipt,
  String capture,
) async {
  await _tap(tester, find.widgetWithText(OutlinedButton, 'Agent suggestions'));
  await _until(
    tester,
    () =>
        find.text('View review record').evaluate().isNotEmpty &&
        find
            .text('No suggested notes are waiting for review.')
            .evaluate()
            .isNotEmpty,
  );
  expect(
    find.text('No suggested notes are waiting for review.'),
    findsOneWidget,
  );
  expect(find.text('Review suggested notes'), findsNothing);
  expect(canonical(store.agentNotesReviews.single), immutableReceipt);
  await _tap(tester, find.widgetWithText(OutlinedButton, 'View review record'));
  expect(find.text('Review record'), findsOneWidget);
  expect(find.text(_suggestion), findsOneWidget);
  expect(find.text(_originalNotes), findsNothing);
  expect(
    find.textContaining('Saved locally. Draft notes updated.'),
    findsOneWidget,
  );
  await _show(tester, find.text(_suggestion));
  await _capture(tester, capture);
  await _tap(tester, find.byType(BackButton).hitTestable());
  await _tap(tester, find.byType(BackButton).hitTestable());
}

// Record both bytes and tree entries to detect any new/deleted files, not just
// a retained sentinel. Existing destination setup uses the public LabStore API.
Future<Map<String, Object>> _tree(Directory root) async {
  final entries = <String, Object>{};
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    final relative = entity.path.substring(root.path.length + 1);
    entries[relative] = entity is File
        ? await entity.readAsBytes()
        : entity is Directory
        ? 'directory'
        : 'unexpected-link';
  }
  return entries;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final library = File(
      Platform.environment['MAINTENANCE_NATIVE_LIBRARY'] ??
          'rust/target/debug/librust_lib_sync_lab.so',
    ).absolute;
    await RustLib.init(externalLibrary: ExternalLibrary.open(library.path));
    // Startup of the real store below exercises SQLite, not an in-memory fake.
    debugPrint('Journey native library: ${library.path}');
    debugPrint('Journey SQLite runtime: ${sqlite3.version}');
    for (final face in ['Regular', 'Bold']) {
      await (FontLoader('Roboto')..addFont(
            File(
              '../../assets/fonts/Roboto-$face.ttf',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  for (final scale in [1.0, 2.0]) {
    final suffix = '${scale.toInt()}x';
    void configure(WidgetTester tester) {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    testWidgets(
      'home applied suggestion survives UI recovery and original launcher reopen at $suffix',
      (tester) async {
        configure(tester);
        late _Journey journey;
        await tester.runAsync(() async {
          journey = await _Journey.create();
          await journey.propose(
            '11111111-1111-4111-8111-111111111111',
            _suggestion,
          );
        });
        journey.cleanup(tester);
        await _mount(tester, journey.source, scale);
        await _tap(
          tester,
          find.widgetWithText(OutlinedButton, 'Agent suggestions'),
        );
        await _until(
          tester,
          () => find.text('Review suggested notes').evaluate().isNotEmpty,
        );
        await _tap(
          tester,
          find.widgetWithText(OutlinedButton, 'Review suggested notes'),
        );
        await _until(
          tester,
          () =>
              find.text(_originalNotes).evaluate().isNotEmpty &&
              find.text(_suggestion).evaluate().isNotEmpty,
        );
        expect(find.text(_originalNotes), findsOneWidget);
        expect(find.text(_suggestion), findsOneWidget);
        await _tap(
          tester,
          find.widgetWithText(FilledButton, 'Apply to draft notes'),
        );
        expect(find.text('Apply suggested notes?'), findsOneWidget);
        expect(journey.source.agentNotesReviews, isEmpty);
        await _capture(tester, 'suggestion-$suffix-apply-confirmation');
        await _tap(
          tester,
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.widgetWithText(FilledButton, 'Apply to draft notes'),
          ),
        );
        await _until(
          tester,
          () => find.text('Review record').evaluate().isNotEmpty,
        );
        final immutableReceipt = canonical(
          journey.source.agentNotesReviews.single,
        );
        expect(journey.source.agentNotesReviews.single['decision'], 'applied');
        expect(journey.source.submissions, isEmpty);
        expect(journey.source.receipts, isEmpty);
        await _tap(tester, find.byType(BackButton).hitTestable());
        await _tap(tester, find.byType(BackButton).hitTestable());
        await _inspectNotes(
          tester,
          journey.jobId,
          _suggestion,
          'suggestion-$suffix-home-inspection-notes',
        );
        await tester.runAsync(() async {
          await journey.propose(
            '22222222-2222-4222-8222-222222222222',
            'Synthetic unreviewed notes that must not enter recovery.',
          );
          expect(
            await AgentProposalStore(journey.source.root).records(),
            hasLength(2),
          );
        });
        await _backupUi(tester, journey, 'suggestion-$suffix');
        await tester.runAsync(() async {
          expect(
            await Directory(
              '${journey.backup.path}/agent-proposals-v1',
            ).exists(),
            isFalse,
          );
        });
        await journey.stop(tester, journey.source);
        final launcher = await journey.openLauncher(tester);
        await _mount(tester, launcher, scale);
        await _restoreForm(tester, journey, journey.restored.path);
        await _restoreUi(tester);
        final restored = journey.restoredStore(tester, launcher);
        await tester.runAsync(() async {
          expect(await AgentProposalStore(restored.root).records(), isEmpty);
          expect(
            await Directory(
              '${restored.root.path}/agent-proposals-v1',
            ).exists(),
            isFalse,
          );
          expect((await restored.fields(jobId: journey.jobId))['notes'], [
            _suggestion,
          ]);
        });
        await _historyUi(
          tester,
          restored,
          immutableReceipt,
          'suggestion-$suffix-restored-history-without-sidecar',
        );
        await journey.stop(tester, restored);
        final reopened = await journey.openLauncher(tester);
        expect(reopened.root.absolute.path, journey.restored.absolute.path);
        expect(reopened.device, journey.sourceDevice);
        expect(
          canonical(reopened.jobContextFor(journey.jobId)),
          journey.frozenContext,
        );
        await tester.runAsync(() async {
          expect(
            (await OfficeIdentity.load(reopened)).fingerprint,
            journey.identity.fingerprint,
          );
          expect(await AgentProposalStore(reopened.root).records(), isEmpty);
        });
        await _mount(tester, reopened, scale);
        await _historyUi(
          tester,
          reopened,
          immutableReceipt,
          'suggestion-$suffix-original-launcher-reopened-history',
        );
        await _inspectNotes(
          tester,
          journey.jobId,
          _suggestion,
          'suggestion-$suffix-original-launcher-reopened-notes',
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    testWidgets(
      'valid restore retains existing destination and retries on same page at $suffix',
      (tester) async {
        configure(tester);
        late _Journey journey;
        late Directory occupied;
        late Map<String, Object> unchanged;
        await tester.runAsync(() async {
          journey = await _Journey.create();
          occupied = Directory('${journey.root.path}/occupied');
          final existing = await LabStore.open(
            occupied,
            office: true,
            maintenanceOnly: true,
          );
          await existing.createCompany(
            'Synthetic retained destination company',
          );
          await existing.close();
          unchanged = await _tree(occupied);
          expect(unchanged, isNotEmpty);
        });
        journey.cleanup(tester);
        await _mount(tester, journey.source, scale);
        await _backupUi(tester, journey, 'retry-$suffix');
        await journey.stop(tester, journey.source);
        final launcher = await journey.openLauncher(tester);
        await _mount(tester, launcher, scale);
        await _restoreForm(tester, journey, occupied.path);
        final samePage = tester.state(find.byType(RestorePage));
        await _tap(tester, _restoreButton);
        await _until(
          tester,
          () => find.text(_restoreFailure).evaluate().isNotEmpty,
        );
        expect(find.text(_restoreFailure), findsOneWidget);
        expect(find.textContaining('Bad state:'), findsNothing);
        expect(find.textContaining('Backup checked:'), findsOneWidget);
        expect(
          tester.widget<FilledButton>(_restoreButton).onPressed,
          isNotNull,
        );
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('restoreDestination')))
              .enabled,
          isTrue,
        );
        expect(launcher.catalog, isNull);
        expect(launcher.setting('officeRestoredTo'), isNull);
        await tester.runAsync(() async {
          expect(await _tree(occupied), unchanged);
          expect(await journey.restored.exists(), isFalse);
        });
        await _show(tester, find.text(_restoreFailure));
        await _capture(tester, 'retry-$suffix-final-failure-existing-retained');
        await _enter(tester, 'restoreDestination', journey.restored.path);
        expect(tester.state(find.byType(RestorePage)), same(samePage));
        expect(find.textContaining('Backup checked:'), findsNothing);
        expect(find.text(_restoreFailure), findsNothing);
        expect(tester.widget<FilledButton>(_restoreButton).onPressed, isNull);
        await _show(tester, _restoreButton);
        await _capture(tester, 'retry-$suffix-edit-clears-checked-summary');
        await _tap(tester, find.text('Check backup'));
        await _until(
          tester,
          () => find.textContaining('Backup checked:').evaluate().isNotEmpty,
        );
        expect(tester.state(find.byType(RestorePage)), same(samePage));
        expect(
          tester.widget<FilledButton>(_restoreButton).onPressed,
          isNotNull,
        );
        await _restoreUi(tester);
        final restored = journey.restoredStore(tester, launcher);
        expect(restored.catalog!['company'], _company);
        await _inspectNotes(
          tester,
          journey.jobId,
          _originalNotes,
          'retry-$suffix-same-page-restored-inspection',
        );
        await journey.stop(tester, restored);
        final reopened = await journey.openLauncher(tester);
        expect(reopened.root.absolute.path, journey.restored.absolute.path);
        expect(reopened.device, journey.sourceDevice);
        expect(
          canonical(reopened.jobContextFor(journey.jobId)),
          journey.frozenContext,
        );
        await tester.runAsync(() async {
          expect(
            (await OfficeIdentity.load(reopened)).fingerprint,
            journey.identity.fingerprint,
          );
          expect(await _tree(occupied), unchanged);
          expect((await reopened.fields(jobId: journey.jobId))['notes'], [
            _originalNotes,
          ]);
        });
        await _mount(tester, reopened, scale);
        expect(find.text(_company), findsOneWidget);
        await _inspectNotes(
          tester,
          journey.jobId,
          _originalNotes,
          'retry-$suffix-original-launcher-reopened-notes',
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }
}
