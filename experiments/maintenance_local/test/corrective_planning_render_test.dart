import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/corrective_planning.dart';
import 'package:maintenance_local/corrective_planning_store.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/manual_fault_intake.dart';
import 'package:maintenance_local/manual_fault_intake_store.dart';
import 'package:maintenance_local/model.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';
import 'package:maintenance_local/ui/corrective_planning_page.dart';
import 'package:maintenance_local/ui/corrective_work_draft_page.dart';
import 'package:maintenance_local/ui/corrective_work_editor.dart';
import 'package:uuid/uuid.dart';

import 'support/native_widget_cleanup.dart';

const _boundary = Key('corrective-planning-render');
const _instructions =
    'Diagnose the guard vibration. Check the fasteners and mounting points before planning the repair.';

class _Fixture {
  _Fixture(
    this.root,
    this.store,
    this.equipment,
    this.otherEquipment,
    this.inspection,
    this.faults,
    this.originalCatalog,
    this.originalDocument,
    this.originalFaults,
  );
  final Directory root;
  LabStore store;
  final Json equipment, otherEquipment;
  final String inspection, originalCatalog, originalDocument, originalFaults;
  final List<ManualFaultRecord> faults;
}

Future<_Fixture> _fixture() async {
  final root = await Directory.systemTemp.createTemp('corrective-render-');
  final store = await LabStore.open(
    Directory('${root.path}/office'),
    office: true,
    maintenanceOnly: true,
  );
  await store.createCompany('Synthetic corrective planning company');
  final equipment = await store.addEquipment(
    name: 'Synthetic generator',
    serial: 'SYNTHETIC-GEN-1',
  );
  final other = await store.addEquipment(
    name: 'Synthetic loader',
    serial: 'SYNTHETIC-LOAD-2',
  );
  final checklist = await store.publishChecklist(
    title: 'Existing synthetic inspection',
    items: [
      {'id': 'guard', 'label': 'Check guard', 'input_type': 'check'},
    ],
  );
  final inspection =
      (await store.prepareWork(
            equipmentId: equipment['id'] as String,
            templateId: checklist['id'] as String,
            title: 'Existing inspection is not corrective',
          ))['id']
          as String;
  final intake = ManualFaultIntakeStore(store);
  for (var index = 0; index < 4; index++) {
    final command = await intake.freeze(
      equipmentId: (index == 3 ? other : equipment)['id'] as String,
      description: [
        'Guard rattles under load.',
        'Mounting bolt is loose.',
        'Guard bracket is cracked.',
        'Loader hose is leaking.',
      ][index],
      severity: index == 2
          ? ManualFaultSeverity.urgent
          : ManualFaultSeverity.normal,
      commandId: const Uuid().v4(),
    );
    await intake.record(command);
  }
  return _Fixture(
    root,
    store,
    equipment,
    other,
    inspection,
    await intake.listRecords(),
    canonical(store.catalog),
    digest(store.documentFor(inspection)!),
    canonical(store.setting(manualFaultIntakeSetting)),
  );
}

/// Only interrupt replies around the actual frozen command and transaction.
class _InterruptedPlanning extends CorrectivePlanningStore {
  _InterruptedPlanning(super.store, {required this.afterCommit});
  final bool afterCommit;
  bool fail = true;
  final commands = <FrozenCorrectivePlanningCommand>[];
  @override
  Future<CorrectivePlanningReceipt> apply(
    FrozenCorrectivePlanningCommand command,
  ) async {
    commands.add(command);
    if (fail && !afterCommit) {
      fail = false;
      throw const FileSystemException('Synthetic interrupted reply');
    }
    final receipt = await super.apply(command);
    if (fail) {
      fail = false;
      throw const FileSystemException('Synthetic lost committed reply');
    }
    return receipt;
  }
}

class _LostFreezePlanning extends CorrectivePlanningStore {
  _LostFreezePlanning(super.store);
  bool failFreeze = true, failRead = false;
  @override
  Future<FrozenCorrectivePlanningCommand> freezeCreate({
    required String equipmentId,
    required String title,
    required String description,
    List<String> faultIds = const [],
    required String commandId,
  }) async {
    final command = await super.freezeCreate(
      equipmentId: equipmentId,
      title: title,
      description: description,
      faultIds: faultIds,
      commandId: commandId,
    );
    if (failFreeze) {
      failFreeze = false;
      failRead = true;
      throw const FileSystemException('Synthetic lost freeze reply');
    }
    return command;
  }

  @override
  Future<CorrectivePlanningReceipt?> receiptFor(String commandId) {
    if (failRead) {
      failRead = false;
      throw const FileSystemException('Synthetic recovery read interruption');
    }
    return super.receiptFor(commandId);
  }
}

class _StaleEditPlanning extends CorrectivePlanningStore {
  _StaleEditPlanning(super.store);
  bool changeBeforeFreeze = true;
  @override
  Future<FrozenCorrectivePlanningCommand> freezeEdit({
    required String draftId,
    required int expectedRevision,
    required String expectedDraftHash,
    required String title,
    required String description,
    required String commandId,
  }) async {
    if (changeBeforeFreeze) {
      changeBeforeFreeze = false;
      final other = await super.freezeEdit(
        draftId: draftId,
        expectedRevision: expectedRevision,
        expectedDraftHash: expectedDraftHash,
        title: 'Saved concurrent planning revision',
        description: 'Synthetic existing instructions.',
        commandId: const Uuid().v4(),
      );
      await super.apply(other);
    }
    return super.freezeEdit(
      draftId: draftId,
      expectedRevision: expectedRevision,
      expectedDraftHash: expectedDraftHash,
      title: title,
      description: description,
      commandId: commandId,
    );
  }
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  for (var frame = 0; frame < 8; frame++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
  expect(
    tester.takeException(),
    isNull,
    reason: 'Planning must render without overflow or framework errors.',
  );
}

Future<void> _show(WidgetTester tester, Finder target) async {
  expect(target, findsOneWidget);
  for (var frame = 0; frame < 12; frame++) {
    await Scrollable.ensureVisible(tester.element(target), alignment: 0.3);
    await tester.pump(const Duration(milliseconds: 200));
    if (target.hitTestable().evaluate().length == 1) return;
    await _settle(tester);
  }
  expect(
    target.hitTestable(),
    findsOneWidget,
    reason: 'The ordinary action must remain reachable at this text size.',
  );
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await _show(tester, target);
  await tester.runAsync(() async {
    await tester.tap(target);
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });
  await _settle(tester);
}

Future<void> _enter(WidgetTester tester, String key, String value) async {
  final field = find.byKey(Key(key));
  await _show(tester, field);
  await tester.enterText(field, value);
  await _settle(tester);
}

Future<void> _capture(WidgetTester tester, String name) async {
  final output = Platform.environment['VORTICE_RENDER_OUTPUT'];
  if (output == null || output.isEmpty) return;
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
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

Future<void> _mount(WidgetTester tester, Widget home, double scale) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(412, 915);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _boundary,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xfff7f4ed),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xff103d3c),
            primary: const Color(0xff103d3c),
            surface: const Color(0xfff7f4ed),
          ),
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
            filled: true,
            fillColor: Colors.white,
          ),
          cardTheme: const CardThemeData(
            color: Colors.white,
            elevation: 0,
            margin: EdgeInsets.symmetric(vertical: 8),
          ),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: home,
      ),
    ),
  );
  await _settle(tester);
}

Future<void> _cleanup(WidgetTester tester, _Fixture fixture) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await finishNativeWidgetCleanup(tester, () async {
    await fixture.store.close();
    await fixture.root.delete(recursive: true);
  });
}

Future<void> _assertInspectionUntouched(_Fixture fixture) async {
  expect(canonical(fixture.store.catalog), fixture.originalCatalog);
  expect(
    digest(fixture.store.documentFor(fixture.inspection)!),
    fixture.originalDocument,
  );
  expect(
    canonical(fixture.store.setting(manualFaultIntakeSetting)),
    fixture.originalFaults,
  );
  expect(fixture.store.activeJobId, fixture.inspection);
  expect(fixture.store.submissions, isEmpty);
  expect(fixture.store.receipts, isEmpty);
}

Future<CorrectiveWorkDraft> _createDraft(
  _Fixture fixture, {
  String title = 'Saved corrective draft',
  String? equipmentId,
  List<String> faults = const [],
}) async {
  final planning = CorrectivePlanningStore(fixture.store);
  return (await planning.apply(
    await planning.freezeCreate(
      equipmentId: equipmentId ?? fixture.equipment['id'] as String,
      title: title,
      description: _instructions,
      faultIds: faults,
      commandId: const Uuid().v4(),
    ),
  )).draft;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await RustLib.init(
      externalLibrary: ExternalLibrary.open(
        Platform.environment['MAINTENANCE_NATIVE_LIBRARY']!,
      ),
    );
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
    testWidgets(
      'standalone draft validates, saves empty description, edits and reopens at ${scale}x',
      (tester) async {
        late _Fixture fixture;
        await tester.runAsync(() async => fixture = await _fixture());
        addTearDown(() => _cleanup(tester, fixture));
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await _mount(
          tester,
          CorrectivePlanningPage(store: fixture.store),
          scale,
        );
        await _capture(tester, 'planning-entry-${scale.toInt()}x');
        await _tap(tester, find.byKey(const Key('corrective-new')));
        await _tap(tester, find.byKey(const Key('corrective-save')));
        expect(
          find.text('Enter a title for the corrective work.'),
          findsOneWidget,
        );
        await _enter(
          tester,
          'corrective-title',
          'Diagnose generator vibration',
        );
        await _tap(tester, find.byKey(const Key('corrective-save')));
        expect(
          find.text('Choose existing equipment for this draft.'),
          findsOneWidget,
        );
        await _tap(tester, find.byKey(const Key('corrective-equipment')));
        await _tap(
          tester,
          find.byKey(
            ValueKey('corrective-use-equipment-${fixture.equipment['id']}'),
          ),
        );
        await _capture(tester, 'standalone-create-${scale.toInt()}x');
        await _tap(tester, find.byKey(const Key('corrective-save')));
        expect(find.byType(CorrectiveWorkDraftPage), findsOneWidget);
        expect(
          find.text('No planning description recorded yet'),
          findsOneWidget,
        );
        expect(find.text(correctivePlanningNotice), findsOneWidget);
        await _tap(tester, find.byKey(const Key('corrective-edit')));
        await _enter(tester, 'corrective-description', _instructions);
        await _capture(tester, 'planning-edit-${scale.toInt()}x');
        await _tap(tester, find.byKey(const Key('corrective-save')));
        expect(find.text(_instructions), findsOneWidget);
        expect(find.text('Corrective work · Draft revision 2'), findsOneWidget);
        await _capture(tester, 'standalone-detail-${scale.toInt()}x');
        late String id;
        await tester.runAsync(() async {
          final draft = (await CorrectivePlanningStore(
            fixture.store,
          ).listDrafts()).single;
          id = draft.id;
          expect(draft.description, _instructions);
          expect(draft.faults, isEmpty);
          await _assertInspectionUntouched(fixture);
        });
        await tester.pumpWidget(const SizedBox.shrink());
        await finishNativeWidgetCleanup(tester, () async {
          await fixture.store.close();
          fixture.store = await LabStore.open(
            Directory('${fixture.root.path}/office'),
            office: true,
            maintenanceOnly: true,
          );
        });
        await _mount(
          tester,
          CorrectiveWorkDraftPage(store: fixture.store, draftId: id),
          scale,
        );
        expect(find.text(_instructions), findsOneWidget);
        expect(find.text('Corrective work · Draft revision 2'), findsOneWidget);
      },
    );

    testWidgets(
      'multi-fault create, same-equipment batch link and saved association at ${scale}x',
      (tester) async {
        late _Fixture fixture;
        await tester.runAsync(() async => fixture = await _fixture());
        addTearDown(() => _cleanup(tester, fixture));
        await _mount(
          tester,
          CorrectivePlanningPage(
            store: fixture.store,
            initialFaultId: fixture.faults[0].id,
          ),
          scale,
        );
        await _tap(
          tester,
          find.byKey(ValueKey('corrective-plan-fault-${fixture.faults[0].id}')),
        );
        expect(
          find.byKey(ValueKey('corrective-fault-${fixture.faults[3].id}')),
          findsNothing,
        );
        await _enter(tester, 'corrective-title', 'Plan guard repair');
        await _enter(tester, 'corrective-description', _instructions);
        await _tap(
          tester,
          find.byKey(ValueKey('corrective-fault-${fixture.faults[1].id}')),
        );
        await _capture(tester, 'multi-fault-create-${scale.toInt()}x');
        await _tap(tester, find.byKey(const Key('corrective-save')));
        expect(
          find.byKey(ValueKey('corrective-linked-${fixture.faults[0].id}')),
          findsOneWidget,
        );
        expect(
          find.byKey(ValueKey('corrective-linked-${fixture.faults[1].id}')),
          findsOneWidget,
        );
        await _tap(tester, find.byKey(const Key('corrective-add-faults')));
        expect(
          find.byKey(ValueKey('corrective-fault-${fixture.faults[0].id}')),
          findsNothing,
        );
        expect(
          find.byKey(ValueKey('corrective-fault-${fixture.faults[3].id}')),
          findsNothing,
        );
        await _tap(
          tester,
          find.byKey(ValueKey('corrective-fault-${fixture.faults[2].id}')),
        );
        await _capture(tester, 'batch-link-${scale.toInt()}x');
        await _tap(tester, find.byKey(const Key('corrective-save')));
        expect(find.text('Corrective work · Draft revision 2'), findsOneWidget);
        await _show(
          tester,
          find.byKey(ValueKey('corrective-linked-${fixture.faults[2].id}')),
        );
        await _capture(tester, 'linked-fault-history-${scale.toInt()}x');
        await _tap(tester, find.byTooltip('Back'));
        expect(
          find.byKey(ValueKey('corrective-open-fault-${fixture.faults[0].id}')),
          findsOneWidget,
        );
        expect(
          find.byKey(ValueKey('corrective-plan-fault-${fixture.faults[0].id}')),
          findsNothing,
        );
        expect(
          find.byKey(
            ValueKey('corrective-existing-fault-${fixture.faults[0].id}'),
          ),
          findsNothing,
        );
        await tester.runAsync(() async {
          final planning = CorrectivePlanningStore(fixture.store);
          final draft = (await planning.listDrafts()).single;
          expect(draft.faults, hasLength(3));
          for (final fault in fixture.faults.take(3)) {
            expect((await planning.draftForFault(fault.id))!.id, draft.id);
          }
          expect(await planning.draftForFault(fixture.faults[3].id), isNull);
          await _assertInspectionUntouched(fixture);
        });
      },
    );

    testWidgets(
      'existing-draft picker excludes inspection and other equipment at ${scale}x',
      (tester) async {
        late _Fixture fixture;
        late CorrectiveWorkDraft eligible;
        await tester.runAsync(() async {
          fixture = await _fixture();
          eligible = await _createDraft(
            fixture,
            title: 'Eligible saved guard plan',
          );
          await _createDraft(
            fixture,
            title: 'Ineligible loader draft',
            equipmentId: fixture.otherEquipment['id'] as String,
          );
        });
        addTearDown(() => _cleanup(tester, fixture));
        await _mount(
          tester,
          CorrectivePlanningPage(
            store: fixture.store,
            initialFaultId: fixture.faults[0].id,
          ),
          scale,
        );
        await _tap(
          tester,
          find.byKey(
            ValueKey('corrective-existing-fault-${fixture.faults[0].id}'),
          ),
        );
        expect(
          find.text('Existing inspection is not corrective'),
          findsNothing,
        );
        expect(find.text('Ineligible loader draft'), findsNothing);
        await _capture(tester, 'existing-draft-picker-${scale.toInt()}x');
        await _tap(
          tester,
          find.byKey(ValueKey('corrective-use-draft-${eligible.id}')),
        );
        await _tap(
          tester,
          find.byKey(ValueKey('corrective-fault-${fixture.faults[1].id}')),
        );
        await _tap(tester, find.byKey(const Key('corrective-save')));
        await tester.runAsync(() async {
          final current = await CorrectivePlanningStore(
            fixture.store,
          ).draftFor(eligible.id);
          expect(current!.faults, hasLength(2));
          expect(current.revision, 2);
          await _assertInspectionUntouched(fixture);
        });
      },
    );

    testWidgets(
      'interrupted frozen intent resumes after store restart at ${scale}x',
      (tester) async {
        late _Fixture fixture;
        await tester.runAsync(() async => fixture = await _fixture());
        addTearDown(() => _cleanup(tester, fixture));
        final interrupted = _InterruptedPlanning(
          fixture.store,
          afterCommit: false,
        );
        await _mount(
          tester,
          CorrectivePlanningPage(
            store: fixture.store,
            initialFaultId: fixture.faults[0].id,
            planning: interrupted,
          ),
          scale,
        );
        await _tap(
          tester,
          find.byKey(ValueKey('corrective-plan-fault-${fixture.faults[0].id}')),
        );
        await _enter(tester, 'corrective-title', 'Saved interrupted plan');
        await _enter(tester, 'corrective-description', _instructions);
        await _tap(tester, find.byKey(const Key('corrective-save')));
        expect(
          tester
              .widget<TextFormField>(find.byKey(const Key('corrective-title')))
              .enabled,
          isFalse,
        );
        final frozen = interrupted.commands.single;
        await tester.pumpWidget(const SizedBox.shrink());
        await finishNativeWidgetCleanup(tester, () async {
          await fixture.store.close();
          fixture.store = await LabStore.open(
            Directory('${fixture.root.path}/office'),
            office: true,
            maintenanceOnly: true,
          );
        });
        await _mount(
          tester,
          CorrectivePlanningPage(store: fixture.store),
          scale,
        );
        await _tap(
          tester,
          find.byKey(ValueKey('corrective-pending-${frozen.id}')),
        );
        expect(find.text(_instructions), findsOneWidget);
        await _capture(tester, 'saved-request-${scale.toInt()}x');
        await _tap(tester, find.byKey(const Key('corrective-request-resume')));
        expect(find.byType(CorrectiveWorkDraftPage), findsOneWidget);
        await tester.runAsync(() async {
          final planning = CorrectivePlanningStore(fixture.store);
          expect(await planning.pendingCommands(), isEmpty);
          final receipt = await planning.receiptFor(frozen.id);
          expect(receipt!.command.hash, frozen.hash);
          expect(receipt.draft.faults, hasLength(1));
          expect(
            fixture.store.db.select('SELECT * FROM events WHERE kind=?', [
              correctivePlanningRecordedEvent,
            ]),
            hasLength(1),
          );
          await _assertInspectionUntouched(fixture);
        });
      },
    );

    testWidgets(
      'lost committed reply replays exact command once at ${scale}x',
      (tester) async {
        late _Fixture fixture;
        await tester.runAsync(() async => fixture = await _fixture());
        addTearDown(() => _cleanup(tester, fixture));
        final interrupted = _InterruptedPlanning(
          fixture.store,
          afterCommit: true,
        );
        await _mount(
          tester,
          CorrectivePlanningPage(
            store: fixture.store,
            initialFaultId: fixture.faults[0].id,
            planning: interrupted,
          ),
          scale,
        );
        await _tap(
          tester,
          find.byKey(ValueKey('corrective-plan-fault-${fixture.faults[0].id}')),
        );
        await _enter(tester, 'corrective-title', 'Plan with lost reply');
        await _tap(tester, find.byKey(const Key('corrective-save')));
        await _tap(tester, find.byKey(const Key('corrective-resume')));
        expect(find.byType(CorrectiveWorkDraftPage), findsOneWidget);
        expect(interrupted.commands, hasLength(2));
        expect(interrupted.commands[0].hash, interrupted.commands[1].hash);
        await tester.runAsync(() async {
          expect(await interrupted.listDrafts(), hasLength(1));
          expect(
            fixture.store.db.select('SELECT * FROM events WHERE kind=?', [
              correctivePlanningRecordedEvent,
            ]),
            hasLength(1),
          );
          await _assertInspectionUntouched(fixture);
        });
      },
    );

    testWidgets(
      'stale revision retains dirty instructions until explicit reload at ${scale}x',
      (tester) async {
        late _Fixture fixture;
        late CorrectiveWorkDraft draft;
        await tester.runAsync(() async {
          fixture = await _fixture();
          draft = await _createDraft(fixture);
        });
        addTearDown(() => _cleanup(tester, fixture));
        final stale = _StaleEditPlanning(fixture.store);
        await _mount(
          tester,
          CorrectiveWorkDraftPage(
            store: fixture.store,
            draftId: draft.id,
            planning: stale,
          ),
          scale,
        );
        await _tap(tester, find.byKey(const Key('corrective-edit')));
        await _enter(tester, 'corrective-title', 'Keep this unsaved title');
        await _enter(
          tester,
          'corrective-description',
          'Keep these unsaved diagnosis instructions.',
        );
        await _tap(tester, find.byKey(const Key('corrective-save')));
        final title = tester.widget<TextFormField>(
          find.byKey(const Key('corrective-title')),
        );
        expect(title.controller!.text, 'Keep this unsaved title');
        expect(title.enabled, isTrue);
        expect(
          tester
              .widget<TextFormField>(
                find.byKey(const Key('corrective-description')),
              )
              .controller!
              .text,
          'Keep these unsaved diagnosis instructions.',
        );
        await _capture(tester, 'stale-edit-${scale.toInt()}x');
        await _tap(tester, find.byKey(const Key('corrective-reload-revision')));
        await _tap(tester, find.byKey(const Key('corrective-save')));
        expect(find.text('Corrective work · Draft revision 3'), findsOneWidget);
        await tester.runAsync(() async {
          expect(
            (await stale.draftFor(draft.id))!.title,
            'Keep this unsaved title',
          );
          expect(await stale.pendingCommands(), isEmpty);
          await _assertInspectionUntouched(fixture);
        });
      },
    );
  }

  testWidgets(
    'lost freeze and recovery reply keep original fields fixed until recovered',
    (tester) async {
      late _Fixture fixture;
      await tester.runAsync(() async => fixture = await _fixture());
      addTearDown(() => _cleanup(tester, fixture));
      final planning = _LostFreezePlanning(fixture.store);
      await _mount(
        tester,
        CorrectivePlanningPage(
          store: fixture.store,
          initialFaultId: fixture.faults[0].id,
          planning: planning,
        ),
        2,
      );
      await _tap(
        tester,
        find.byKey(ValueKey('corrective-plan-fault-${fixture.faults[0].id}')),
      );
      await _enter(tester, 'corrective-title', 'Original frozen plan');
      await _tap(tester, find.byKey(const Key('corrective-save')));
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('corrective-title')))
            .enabled,
        isFalse,
      );
      await _tap(tester, find.byKey(const Key('corrective-recheck')));
      await _tap(tester, find.byKey(const Key('corrective-resume')));
      expect(find.text('Original frozen plan'), findsOneWidget);
      await tester.runAsync(() async {
        expect(await planning.pendingCommands(), isEmpty);
        expect(await planning.listDrafts(), hasLength(1));
      });
    },
  );

  testWidgets('phone and unsupported planning history deny mutation', (
    tester,
  ) async {
    late _Fixture fixture;
    await tester.runAsync(() async => fixture = await _fixture());
    addTearDown(() => _cleanup(tester, fixture));
    await tester.runAsync(() async {
      await _createDraft(fixture);
      fixture.store.setSetting(correctivePlanningSetting, {
        'version': 99,
        'pending': [],
        'receipts': [],
      });
    });
    await _mount(tester, CorrectivePlanningPage(store: fixture.store), 2);
    expect(
      find.text(
        'This corrective planning needs its matching app version. Its files have been retained.',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('corrective-new')))
          .onPressed,
      isNull,
    );
    await tester.runAsync(() async {
      expect(
        fixture.store.db.select('PRAGMA user_version').single.values.single,
        3,
      );
    });
    late LabStore phone;
    await tester.runAsync(
      () async => phone = await LabStore.open(
        Directory('${fixture.root.path}/phone'),
        office: false,
        maintenanceOnly: true,
      ),
    );
    await _mount(tester, CorrectivePlanningPage(store: phone), 2);
    expect(
      find.text('Plan corrective work on the office computer.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('corrective-new')), findsNothing);
    await _mount(
      tester,
      CorrectiveWorkDraftPage(store: phone, draftId: fixture.inspection),
      2,
    );
    expect(
      find.text('View and plan corrective work on the office computer.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await finishNativeWidgetCleanup(tester, () async {
      expect(phone.setting(correctivePlanningSetting), isNull);
      await phone.close();
    });
  });
}
