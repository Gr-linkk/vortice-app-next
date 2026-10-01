import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/manual_fault_intake.dart';
import 'package:maintenance_local/manual_fault_intake_store.dart';
import 'package:maintenance_local/model.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';
import 'package:maintenance_local/ui/manual_fault_intake_page.dart';

const _boundary = Key('manual-fault-render');
const _description =
    'Operator reported a loose guard fastener. Check the guard before planning corrective work.';
late final List<int> _photo;

Future<List<int>> _syntheticPng() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(const Color(0xffe4ece6), BlendMode.src);
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTWH(40, 40, 400, 240),
      const Radius.circular(16),
    ),
    Paint()..color = const Color(0xff103d3c),
  );
  final caption = TextPainter(
    text: const TextSpan(
      text: 'SYNTHETIC SAVED EVIDENCE\nGenerator guard',
      style: TextStyle(fontFamily: 'Roboto', fontSize: 24, color: Colors.white),
    ),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
  )..layout(maxWidth: 350);
  caption.paint(canvas, const Offset(65, 120));
  caption.dispose();
  final picture = recorder.endRecording();
  final image = await picture.toImage(480, 320);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Future<void> _close(WidgetTester tester, LabStore store) async {
  var finished = false;
  final closing = store.close().then((_) => finished = true);
  for (var i = 0; i < 20 && !finished; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  expect(
    finished,
    isTrue,
    reason:
        'Drain fake-zone queue callbacks before awaiting real SQLite close.',
  );
  await closing;
}

/// Inject only a reply failure around actual persistence. No records, commands
/// or receipts are mocked; retries must use the durable store's real result.
class _LostReplyIntake extends ManualFaultIntakeStore {
  _LostReplyIntake(super.store, {required this.afterCommit});
  final bool afterCommit;
  bool failOnce = true;
  final commands = <FrozenManualFaultCommand>[];

  @override
  Future<ManualFaultReceipt> record(FrozenManualFaultCommand command) async {
    commands.add(command);
    if (failOnce && !afterCommit) {
      failOnce = false;
      throw const FileSystemException('Synthetic recording interruption');
    }
    final receipt = await super.record(command);
    if (failOnce) {
      failOnce = false;
      throw const FileSystemException('Synthetic lost recording reply');
    }
    return receipt;
  }
}

class _LostFreezeReplyIntake extends ManualFaultIntakeStore {
  _LostFreezeReplyIntake(super.store);
  bool loseFreeze = true, loseRead = false;
  final ids = <String>[];

  @override
  Future<FrozenManualFaultCommand> freeze({
    required String equipmentId,
    required String description,
    required ManualFaultSeverity severity,
    ManualFaultOrigin? originSelection,
    required String commandId,
  }) async {
    ids.add(commandId);
    final command = await super.freeze(
      equipmentId: equipmentId,
      description: description,
      severity: severity,
      originSelection: originSelection,
      commandId: commandId,
    );
    if (loseFreeze) {
      loseFreeze = false;
      loseRead = true;
      throw const FileSystemException('Synthetic lost saved-request reply');
    }
    return command;
  }

  @override
  Future<List<FrozenManualFaultCommand>> pendingCommands() async {
    if (loseRead) {
      loseRead = false;
      throw const FileSystemException('Synthetic recovery read interruption');
    }
    return super.pendingCommands();
  }
}

/// Pause acceptance after the real durable freeze, then release the real store
/// command. This exposes callbacks still rendered before the next busy frame.
class _DeferredIntake extends ManualFaultIntakeStore {
  _DeferredIntake(super.store);
  final release = Completer<void>();
  final commands = <FrozenManualFaultCommand>[];

  @override
  Future<ManualFaultReceipt> record(FrozenManualFaultCommand command) async {
    commands.add(command);
    await release.future;
    return super.record(command);
  }
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pump(const Duration(milliseconds: 300));
  expect(
    tester.takeException(),
    isNull,
    reason: 'Ordinary intake must render without overflow or framework errors.',
  );
}

Future<void> _show(WidgetTester tester, Finder target) async {
  expect(target, findsOneWidget);
  for (var i = 0; i < 12; i++) {
    await Scrollable.ensureVisible(tester.element(target), alignment: 0.3);
    await tester.pump(const Duration(milliseconds: 200));
    if (target.hitTestable().evaluate().length == 1) return;
    await _settle(tester);
  }
  expect(
    target.hitTestable(),
    findsOneWidget,
    reason: 'This ordinary control must be reachable at this text size.',
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

Future<void> _enter(WidgetTester tester, String description) async {
  final field = find.byKey(const Key('manual-fault-description'));
  await _show(tester, field);
  await tester.enterText(field, description);
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

Future<void> _mount(
  WidgetTester tester,
  LabStore store,
  double scale, {
  ManualFaultIntakeStore? intake,
}) async {
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
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xfff7f4ed),
            foregroundColor: Color(0xff103d3c),
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
        home: ManualFaultIntakePage(store: store, intake: intake),
      ),
    ),
  );
  await _settle(tester);
}

Future<void> _new(WidgetTester tester, String equipmentId) async {
  await _tap(tester, find.byKey(const Key('manual-fault-new')));
  await _tap(tester, find.byKey(const Key('manual-fault-equipment')));
  await _tap(
    tester,
    find.byKey(ValueKey('manual-fault-equipment-$equipmentId')),
  );
}

Future<void> _source(
  WidgetTester tester,
  String submissionId,
  String kind, {
  String? itemId,
}) async {
  await _tap(tester, find.byKey(const Key('manual-fault-source')));
  await _tap(tester, find.byKey(ValueKey('manual-fault-source-$submissionId')));
  await _tap(
    tester,
    find.byKey(
      ValueKey('manual-fault-use-$kind${itemId == null ? '' : '-$itemId'}'),
    ),
  );
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
    _photo = await _syntheticPng();
  });

  late Directory root;
  late LabStore store;
  late String equipment,
      otherEquipment,
      pendingSubmission,
      approvedSubmission,
      returnedSubmission,
      pendingJob;
  final clock = DateTime.utc(2026, 10, 1, 12);

  setUp(() async {
    root = await Directory.systemTemp.createTemp('manual-fault-render-');
    store = await LabStore.open(
      Directory('${root.path}/office'),
      office: true,
      now: () => clock,
      maintenanceOnly: true,
    );
    await store.createCompany(
      'Synthetic Field Notes company',
      coordinatorName: 'Sam Coordinator',
    );
    equipment =
        (await store.addEquipment(
              name: 'Workshop generator',
              serial: 'GEN-01',
              meterUnit: 'none',
            ))['id']
            as String;
    otherEquipment =
        (await store.addEquipment(
              name: 'Equipment with no submitted inspection',
              meterUnit: 'none',
            ))['id']
            as String;
    final template = await store.publishChecklist(
      title: 'Guard and written condition',
      items: [
        {
          'id': 'guard',
          'label': 'Inspect the guard fasteners',
          'input_type': 'check',
        },
        {
          'id': 'condition',
          'label': 'Describe the visible condition',
          'input_type': 'text',
        },
      ],
      provenance: {
        'kind': 'local-reference',
        'reference': 'Synthetic workshop reference — guard section',
      },
    );
    Future<Json> submission(String title) async {
      final job = await store.prepareWork(
        equipmentId: equipment,
        templateId: template['id'] as String,
        title: title,
      );
      final id = job['id'] as String;
      await store.update({
        'answer:guard': {'result': 'pass', 'value': ''},
        'answer:condition': {
          'result': 'pass',
          'value': 'Guard fasteners visible',
        },
        'notes': '$title: mechanic recorded the original guard condition.',
      }, jobId: id);
      await store.attach(_photo, jobId: id);
      return store.submit(jobId: id);
    }

    final pending = await submission('Awaiting office review');
    pendingSubmission = pending['id'] as String;
    pendingJob = pending['jobId'] as String;
    final approved = await submission('Approved exact inspection');
    approvedSubmission = approved['id'] as String;
    await store.decide(approvedSubmission, approve: true);
    final returned = await submission('Returned exact inspection');
    returnedSubmission = returned['id'] as String;
    await store.decide(
      returnedSubmission,
      approve: false,
      reason: 'Add the guard clearance observation.',
    );
  });

  void cleanup(WidgetTester tester) => addTearDown(() async {
    tester.view.resetViewInsets();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    await tester.pumpWidget(const SizedBox.shrink());
    await _settle(tester);
    await _close(tester, store);
    await tester.runAsync(() => root.delete(recursive: true));
  });

  for (final scale in [1.0, 2.0]) {
    final name = scale == 1 ? 'phone' : 'large-text';
    testWidgets(
      'ordinary manual report validates, discards, handles keyboard and records without source: $name',
      (tester) async {
        cleanup(tester);
        final beforeSubmissions = canonical(store.submissions),
            beforeReceipts = canonical(store.receipts),
            activeJob = store.activeJobId;
        final beforeDocs = {
          for (final job in store.jobs)
            job['id']: digest(store.documentFor(job['id'] as String)!),
        };
        await _mount(tester, store, scale);
        await _tap(tester, find.byKey(const Key('manual-fault-new')));
        await _tap(tester, find.byKey(const Key('manual-fault-submit')));
        expect(
          find.text('Select equipment and describe the reported problem.'),
          findsOneWidget,
        );
        await _tap(tester, find.byKey(const Key('manual-fault-equipment')));
        await _tap(
          tester,
          find.byKey(ValueKey('manual-fault-equipment-$otherEquipment')),
        );
        expect(
          tester
              .widget<ChoiceChip>(
                find.byKey(const Key('manual-fault-severity-normal')),
              )
              .selected,
          isTrue,
        );
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await _enter(tester, 'Unsaved report to discard');
        await _capture(tester, '$name-keyboard-intake');
        tester.view.resetViewInsets();
        await _tap(tester, find.byKey(const Key('manual-fault-source')));
        expect(
          find.textContaining('no saved submitted inspections'),
          findsOneWidget,
        );
        await _capture(tester, '$name-no-saved-source');
        await _tap(tester, find.byType(BackButton));
        await _tap(tester, find.byKey(const Key('manual-fault-cancel')));
        expect(find.text('Discard this report?'), findsOneWidget);
        await _capture(tester, '$name-discard-dialog');
        await _tap(tester, find.text('Keep editing'));
        await _tap(tester, find.byKey(const Key('manual-fault-cancel')));
        await _tap(tester, find.text('Discard report'));
        expect(
          await tester.runAsync(
            () => ManualFaultIntakeStore(store).pendingCommands(),
          ),
          isEmpty,
        );
        await _new(tester, equipment);
        await _enter(tester, _description);
        await _show(tester, find.byKey(const Key('manual-fault-submit')));
        await _capture(tester, '$name-ready-manual-report');
        await _tap(tester, find.byKey(const Key('manual-fault-submit')));
        final records = (await tester.runAsync(
          () => ManualFaultIntakeStore(store).listRecords(),
        ))!;
        expect(records, hasLength(1));
        expect(records.single.severity, ManualFaultSeverity.normal);
        expect(records.single.origin, isNull);
        await _capture(tester, '$name-recorded-list');
        await _tap(
          tester,
          find.byKey(ValueKey('manual-fault-open-${records.single.id}')),
        );
        expect(find.text(manualFaultReportedStatus), findsOneWidget);
        expect(find.text(_description), findsOneWidget);
        expect(find.byType(TextField), findsNothing);
        await _capture(tester, '$name-recorded-detail');
        expect(canonical(store.submissions), beforeSubmissions);
        expect(canonical(store.receipts), beforeReceipts);
        expect(store.activeJobId, activeJob);
        expect({
          for (final job in store.jobs)
            job['id']: digest(store.documentFor(job['id'] as String)!),
        }, beforeDocs);
      },
    );

    testWidgets(
      'exact saved step source, evidence and provenance remain read only after later review: $name',
      (tester) async {
        cleanup(tester);
        final activeJob = store.activeJobId,
            document = digest(store.documentFor(pendingJob)!);
        final submissions = canonical(store.submissions),
            receipts = canonical(store.receipts);
        await _mount(tester, store, scale);
        await _new(tester, equipment);
        await _enter(tester, _description);
        await _tap(tester, find.byKey(const Key('manual-fault-source')));
        await _capture(tester, '$name-source-list');
        await _tap(
          tester,
          find.byKey(ValueKey('manual-fault-source-$pendingSubmission')),
        );
        expect(
          find.text('Captured observation: Pending office review'),
          findsOneWidget,
        );
        await _show(tester, find.text('Prepared checklist and source'));
        await _tap(tester, find.text('Prepared checklist and source'));
        expect(
          find.text('Synthetic workshop reference — guard section'),
          findsOneWidget,
        );
        await _capture(tester, '$name-source-provenance');
        await _show(tester, find.byType(Image));
        await _settle(tester);
        expect(
          tester
              .widget<RawImage>(
                find.descendant(
                  of: find.byType(Image),
                  matching: find.byType(RawImage),
                ),
              )
              .image,
          isNotNull,
        );
        await _capture(tester, '$name-source-stored-photo');
        expect(find.text('Approve this version'), findsNothing);
        expect(find.text('Return with a reason'), findsNothing);
        expect(canonical(store.submissions), submissions);
        expect(canonical(store.receipts), receipts);
        expect(store.activeJobId, activeJob);
        expect(digest(store.documentFor(pendingJob)!), document);
        await _tap(
          tester,
          find.byKey(const Key('manual-fault-use-item-guard')),
        );
        await _tap(
          tester,
          find.byKey(const Key('manual-fault-severity-urgent')),
        );
        await _tap(tester, find.byKey(const Key('manual-fault-submit')));
        final record = (await tester.runAsync(
          () => ManualFaultIntakeStore(store).listRecords(),
        ))!.single;
        expect(record.severity, ManualFaultSeverity.urgent);
        expect(record.origin!.kind, ManualFaultOriginKind.item);
        expect(record.origin!.itemId, 'guard');
        expect(record.origin!.observation, ManualFaultObservation.pending);
        await tester.runAsync(
          () => store.decide(pendingSubmission, approve: true),
        );
        await _tap(
          tester,
          find.byKey(ValueKey('manual-fault-open-${record.id}')),
        );
        await _tap(tester, find.byKey(const Key('manual-fault-view-source')));
        expect(
          find.text('Captured observation: Pending office review'),
          findsOneWidget,
        );
        await _capture(tester, '$name-pending-observation-after-review');
        expect(store.activeJobId, activeJob);
        expect(digest(store.documentFor(pendingJob)!), document);
      },
    );

    testWidgets(
      'approved whole version and returned note sources are selectable: $name',
      (tester) async {
        cleanup(tester);
        await _mount(tester, store, scale);
        for (final choice in [
          (
            approvedSubmission,
            'submission',
            ManualFaultOriginKind.submission,
            ManualFaultObservation.approved,
          ),
          (
            returnedSubmission,
            'note',
            ManualFaultOriginKind.note,
            ManualFaultObservation.returned,
          ),
        ]) {
          await _new(tester, equipment);
          await _enter(tester, _description);
          await _source(tester, choice.$1, choice.$2);
          await _tap(tester, find.byKey(const Key('manual-fault-view-source')));
          if (choice.$4 == ManualFaultObservation.returned) {
            expect(
              find.text('Return reason: Add the guard clearance observation.'),
              findsOneWidget,
            );
          }
          await _capture(tester, '$name-selected-${choice.$2}-source');
          await _tap(tester, find.byType(BackButton));
          await _tap(tester, find.byKey(const Key('manual-fault-submit')));
          final record = (await tester.runAsync(
            () => ManualFaultIntakeStore(store).listRecords(),
          ))!.last;
          expect(record.origin!.kind, choice.$3);
          expect(record.origin!.observation, choice.$4);
          expect(record.origin!.receiptHash, isNotNull);
        }
      },
    );

    testWidgets(
      'interrupted recording reopens as fixed saved request and resumes exact command: $name',
      (tester) async {
        cleanup(tester);
        final intake = _LostReplyIntake(store, afterCommit: false);
        await _mount(tester, store, scale, intake: intake);
        await _new(tester, equipment);
        await _enter(tester, _description);
        await _tap(tester, find.byKey(const Key('manual-fault-submit')));
        expect(
          tester
              .widget<TextField>(
                find.byKey(const Key('manual-fault-description')),
              )
              .enabled,
          isFalse,
        );
        expect(
          tester
              .widget<OutlinedButton>(
                find.byKey(const Key('manual-fault-equipment')),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<OutlinedButton>(
                find.byKey(const Key('manual-fault-source')),
              )
              .onPressed,
          isNull,
        );
        final command = intake.commands.single;
        expect(
          await tester.runAsync(
            () => ManualFaultIntakeStore(store).listRecords(),
          ),
          isEmpty,
        );
        await _capture(tester, '$name-interrupted-fixed-fields');
        await _tap(tester, find.byKey(const Key('manual-fault-cancel')));
        expect(find.text('Discard this report?'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        await _settle(tester);
        await _close(tester, store);
        store = (await tester.runAsync(
          () => LabStore.open(
            Directory('${root.path}/office'),
            office: true,
            now: () => clock,
            maintenanceOnly: true,
          ),
        ))!;
        await _mount(tester, store, scale);
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('manual-fault-new')))
              .onPressed,
          isNull,
        );
        await _capture(tester, '$name-reopened-saved-request');
        await _tap(
          tester,
          find.byKey(ValueKey('manual-fault-resume-${command.id}')),
        );
        expect(find.byType(TextField), findsNothing);
        await _capture(tester, '$name-resume-fixed-request');
        await _tap(
          tester,
          find.byKey(const Key('manual-fault-resume-request')),
        );
        expect(find.text(manualFaultReportedStatus), findsOneWidget);
        final receipt = (await tester.runAsync(
          () => ManualFaultIntakeStore(store).receiptFor(command.id),
        ))!;
        expect(receipt.command.hash, command.hash);
        expect(
          await tester.runAsync(
            () => ManualFaultIntakeStore(store).pendingCommands(),
          ),
          isEmpty,
        );
        expect(
          await tester.runAsync(
            () => ManualFaultIntakeStore(store).listRecords(),
          ),
          hasLength(1),
        );
        await _capture(tester, '$name-resumed-record');
      },
    );

    testWidgets(
      'lost committed reply retries same frozen request without duplicate: $name',
      (tester) async {
        cleanup(tester);
        final intake = _LostReplyIntake(store, afterCommit: true);
        await _mount(tester, store, scale, intake: intake);
        await _new(tester, equipment);
        await _enter(tester, _description);
        await _tap(tester, find.byKey(const Key('manual-fault-submit')));
        expect(
          tester
              .widget<TextField>(
                find.byKey(const Key('manual-fault-description')),
              )
              .enabled,
          isFalse,
        );
        expect(
          await tester.runAsync(
            () => ManualFaultIntakeStore(store).listRecords(),
          ),
          hasLength(1),
        );
        await _capture(tester, '$name-lost-committed-reply');
        await _tap(tester, find.byKey(const Key('manual-fault-submit')));
        expect(intake.commands, hasLength(2));
        expect(intake.commands[1].hash, intake.commands[0].hash);
        expect(
          await tester.runAsync(
            () => ManualFaultIntakeStore(store).listRecords(),
          ),
          hasLength(1),
        );
        expect(
          store.db.select('SELECT id FROM events WHERE kind=?', [
            manualFaultReportedEvent,
          ]),
          hasLength(1),
        );
      },
    );
  }

  testWidgets(
    'lost freeze reply and recovery read keep fields fixed until durable request is found',
    (tester) async {
      cleanup(tester);
      final intake = _LostFreezeReplyIntake(store);
      await _mount(tester, store, 2, intake: intake);
      await _new(tester, equipment);
      await _enter(tester, _description);
      await _tap(tester, find.byKey(const Key('manual-fault-submit')));
      expect(
        tester
            .widget<TextField>(
              find.byKey(const Key('manual-fault-description')),
            )
            .enabled,
        isFalse,
      );
      expect(find.text('Check saved request'), findsOneWidget);
      await _capture(tester, 'large-text-freeze-recovery-read-error');
      await _tap(tester, find.byKey(const Key('manual-fault-check')));
      expect(find.text('Resume saved request'), findsOneWidget);
      await _tap(tester, find.byKey(const Key('manual-fault-submit')));
      final receipt = (await tester.runAsync(
        () => ManualFaultIntakeStore(store).receiptFor(intake.ids.single),
      ))!;
      expect(receipt.record.description, _description);
      expect(
        await tester.runAsync(
          () => ManualFaultIntakeStore(store).listRecords(),
        ),
        hasLength(1),
      );
    },
  );

  testWidgets(
    'newer retained fault history shows recovery guidance and denies new reports',
    (tester) async {
      cleanup(tester);
      store.setSetting(manualFaultIntakeSetting, {
        'version': 2,
        'pending': [],
        'receipts': [],
      });
      final retained = canonical(store.setting(manualFaultIntakeSetting));
      await _mount(tester, store, 2);
      expect(find.textContaining('matching app version'), findsOneWidget);
      expect(find.textContaining('files have been retained'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('manual-fault-new')))
            .onPressed,
        isNull,
      );
      expect(canonical(store.setting(manualFaultIntakeSetting)), retained);
      await _capture(tester, 'large-text-unsupported-retained-history');
    },
  );

  testWidgets(
    'phone entry is safely denied without creating manual fault state',
    (tester) async {
      cleanup(tester);
      final phone = (await tester.runAsync(
        () => LabStore.open(
          Directory('${root.path}/phone'),
          office: false,
          maintenanceOnly: true,
        ),
      ))!;
      await _mount(tester, phone, 2);
      expect(
        find.text('Report and view manual faults on the office computer.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('manual-fault-new')), findsNothing);
      expect(phone.setting(manualFaultIntakeSetting), isNull);
      await _capture(tester, 'large-text-phone-denied');
      await tester.pumpWidget(const SizedBox.shrink());
      await _settle(tester);
      await _close(tester, phone);
    },
  );

  for (final action in ['view-source', 'equipment', 'source']) {
    testWidgets(
      'navigation during recording: stale form $action callback keeps acceptance on its route',
      (tester) async {
        cleanup(tester);
        final intake = _DeferredIntake(store);
        await _mount(tester, store, 2, intake: intake);
        await _new(tester, equipment);
        await _enter(tester, _description);
        await _source(tester, pendingSubmission, 'item', itemId: 'guard');
        final oldAction = switch (action) {
          'view-source' =>
            tester
                .widget<TextButton>(
                  find.byKey(const Key('manual-fault-view-source')),
                )
                .onPressed!,
          'equipment' =>
            tester
                .widget<OutlinedButton>(
                  find.byKey(const Key('manual-fault-equipment')),
                )
                .onPressed!,
          _ =>
            tester
                .widget<OutlinedButton>(
                  find.byKey(const Key('manual-fault-source')),
                )
                .onPressed!,
        };
        final record = tester
            .widget<FilledButton>(find.byKey(const Key('manual-fault-submit')))
            .onPressed!;
        try {
          // Invoke the ordinary callbacks in the same frame, before disabled
          // widgets replace the controls that were visible to the user.
          record();
          oldAction();
          await _settle(tester);
          expect(intake.commands, hasLength(1));
          intake.release.complete();
          await _settle(tester);
          expect(
            await tester.runAsync(
              () => ManualFaultIntakeStore(store).listRecords(),
            ),
            hasLength(1),
          );
          await _capture(
            tester,
            'large-text-stale-form-$action-after-acceptance',
          );
          expect(
            find.widgetWithText(AppBar, 'Reported faults'),
            findsOneWidget,
            reason:
                'Acceptance must close the form, with no stale callback opening another route.',
          );
        } finally {
          if (!intake.release.isCompleted) intake.release.complete();
          await _settle(tester);
        }
      },
    );
  }

  testWidgets(
    'navigation during recording: stale saved-request source callback keeps acceptance visible',
    (tester) async {
      cleanup(tester);
      final origins = (await tester.runAsync(
        () => ManualFaultIntakeStore(store).availableOrigins(equipment),
      ))!;
      final origin = origins.firstWhere(
        (o) =>
            o.submissionId == pendingSubmission &&
            o.kind == ManualFaultOriginKind.item &&
            o.itemId == 'guard',
      );
      final command = (await tester.runAsync(
        () => ManualFaultIntakeStore(store).freeze(
          equipmentId: equipment,
          description: _description,
          severity: ManualFaultSeverity.normal,
          originSelection: origin,
          commandId: '99999999-9999-4999-8999-999999999999',
        ),
      ))!;
      final intake = _DeferredIntake(store);
      await _mount(tester, store, 2, intake: intake);
      await _tap(
        tester,
        find.byKey(ValueKey('manual-fault-resume-${command.id}')),
      );
      // Frozen requests may still view their exact source while idle.
      await _tap(tester, find.byKey(const Key('manual-fault-view-source')));
      expect(
        find.widgetWithText(AppBar, 'Saved inspection source'),
        findsOneWidget,
      );
      await _tap(tester, find.byType(BackButton));
      final oldView = tester
          .widget<TextButton>(find.byKey(const Key('manual-fault-view-source')))
          .onPressed!;
      final resume = tester
          .widget<FilledButton>(
            find.byKey(const Key('manual-fault-resume-request')),
          )
          .onPressed!;
      try {
        resume();
        oldView();
        await _settle(tester);
        expect(intake.commands, hasLength(1));
        intake.release.complete();
        await _settle(tester);
        expect(
          await tester.runAsync(
            () => ManualFaultIntakeStore(store).listRecords(),
          ),
          hasLength(1),
        );
        await _capture(
          tester,
          'large-text-stale-saved-request-source-after-acceptance',
        );
        expect(
          find.widgetWithText(AppBar, 'Fault record'),
          findsOneWidget,
          reason: 'A stale source action must not hide the accepted result.',
        );
        await _tap(tester, find.byKey(const Key('manual-fault-view-source')));
        expect(
          find.widgetWithText(AppBar, 'Saved inspection source'),
          findsOneWidget,
        );
      } finally {
        if (!intake.release.isCompleted) intake.release.complete();
        await _settle(tester);
      }
    },
  );
}
