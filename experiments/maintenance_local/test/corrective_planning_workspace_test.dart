import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/app.dart';
import 'package:maintenance_local/corrective_planning_store.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/manual_fault_intake.dart';
import 'package:maintenance_local/manual_fault_intake_store.dart';
import 'package:maintenance_local/model.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';
import 'package:maintenance_local/ui/corrective_planning_page.dart';
import 'package:maintenance_local/ui/corrective_work_draft_page.dart';
import 'package:maintenance_local/ui/manual_fault_intake_page.dart';
import 'package:uuid/uuid.dart';

import 'support/native_widget_cleanup.dart';

const _boundary = Key('corrective-workspace-render');

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  for (var frame = 0; frame < 8; frame++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pump(const Duration(milliseconds: 400));
  expect(tester.takeException(), isNull);
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  expect(target, findsOneWidget);
  for (var frame = 0; frame < 12; frame++) {
    await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
    await _settle(tester);
    if (target.hitTestable().evaluate().length == 1) break;
  }
  expect(target.hitTestable(), findsOneWidget);
  await tester.runAsync(() async {
    await tester.tap(target);
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });
  await _settle(tester);
}

Future<void> _capture(WidgetTester tester, String name) async {
  final output = Platform.environment['VORTICE_RENDER_OUTPUT'];
  if (output == null || output.isEmpty) return;
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
      'Home fault planning retains history across reopen at ${scale}x',
      (tester) async {
        tester.view.physicalSize = const Size(412, 915);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        late Directory root;
        late LabStore store;
        late String job,
            faultId,
            originalCatalog,
            originalDocument,
            faultHistory;
        await tester.runAsync(() async {
          root = await Directory.systemTemp.createTemp('corrective-workspace-');
          store = await LabStore.open(
            Directory('${root.path}/office'),
            office: true,
            maintenanceOnly: true,
          );
          await store.createCompany('Synthetic corrective company');
          final equipment = await store.addEquipment(
            name: 'Synthetic compressor',
          );
          final checklist = await store.publishChecklist(
            title: 'Synthetic inspection',
            items: [
              {'id': 'guard', 'label': 'Check guard', 'input_type': 'check'},
            ],
          );
          job =
              (await store.prepareWork(
                    equipmentId: equipment['id'] as String,
                    templateId: checklist['id'] as String,
                    title: 'Existing inspection',
                  ))['id']
                  as String;
          final intake = ManualFaultIntakeStore(store);
          final reported = await intake.record(
            await intake.freeze(
              equipmentId: equipment['id'] as String,
              description: 'Guard rattles under load.',
              severity: ManualFaultSeverity.urgent,
              commandId: const Uuid().v4(),
            ),
          );
          faultId = reported.record.id;
          originalCatalog = canonical(store.catalog);
          originalDocument = digest(store.documentFor(job)!);
          faultHistory = canonical(store.setting(manualFaultIntakeSetting));
        });
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await finishNativeWidgetCleanup(tester, () async {
            await store.close();
            await root.delete(recursive: true);
          });
        });
        Future<void> showHome() async {
          await tester.pumpWidget(
            RepaintBoundary(
              key: _boundary,
              child: LabApp(store: store, textScale: scale, officePort: 0),
            ),
          );
          await _settle(tester);
        }

        await showHome();
        await _tap(tester, find.byKey(const Key('office-corrective-planning')));
        expect(find.byType(CorrectivePlanningPage), findsOneWidget);
        await _capture(tester, 'normal-home-planning-${scale.toInt()}x');
        expect(store.db.select('PRAGMA user_version').single.values.single, 2);
        await _tap(tester, find.byTooltip('Back'));
        await _tap(tester, find.text('Reported faults'));
        expect(find.byType(ManualFaultIntakePage), findsOneWidget);
        await _tap(tester, find.text('View fault record'));
        expect(find.text(manualFaultReportedStatus), findsOneWidget);
        await _tap(
          tester,
          find.byKey(const Key('manual-fault-corrective-planning')),
        );
        await _tap(tester, find.byKey(Key('corrective-plan-fault-$faultId')));
        final title = find.byKey(const Key('corrective-title'));
        await tester.ensureVisible(title);
        await tester.enterText(title, 'Diagnose guard vibration');
        final description = find.byKey(const Key('corrective-description'));
        await tester.ensureVisible(description);
        await tester.enterText(
          description,
          'Check fasteners and mounting points.',
        );
        await _settle(tester);
        await _capture(tester, 'normal-fault-plan-editor-${scale.toInt()}x');
        await _tap(tester, find.byKey(const Key('corrective-save')));
        expect(find.byType(CorrectiveWorkDraftPage), findsOneWidget);
        expect(find.text('Diagnose guard vibration'), findsOneWidget);
        await _capture(tester, 'normal-fault-plan-saved-${scale.toInt()}x');
        await _tap(tester, find.byTooltip('Back'));
        await _tap(tester, find.byTooltip('Back'));
        expect(find.text('Open corrective draft'), findsOneWidget);
        expect(
          find.text(
            'Reported — corrective draft linked. Work has not started.',
          ),
          findsOneWidget,
        );
        expect(
          find.text('At reporting: Reported — corrective work not planned'),
          findsOneWidget,
        );
        await _capture(tester, 'normal-linked-fault-${scale.toInt()}x');
        await tester.pumpWidget(const SizedBox.shrink());
        await finishNativeWidgetAction(tester, () async {
          final draft = await CorrectivePlanningStore(
            store,
          ).draftForFault(faultId);
          expect(draft!.faults.single.faultId, faultId);
          expect(draft.description, 'Check fasteners and mounting points.');
          expect(canonical(store.catalog), originalCatalog);
          expect(digest(store.documentFor(job)!), originalDocument);
          expect(
            canonical(store.setting(manualFaultIntakeSetting)),
            faultHistory,
          );
          await store.close();
          store = await LabStore.open(
            Directory('${root.path}/office'),
            office: true,
            maintenanceOnly: true,
          );
        });
        await showHome();
        await _tap(tester, find.text('Reported faults'));
        expect(find.text('Reported — corrective draft linked'), findsOneWidget);
        await _tap(tester, find.text('View fault record'));
        await _tap(
          tester,
          find.byKey(const Key('manual-fault-corrective-planning')),
        );
        expect(find.byType(CorrectiveWorkDraftPage), findsOneWidget);
        expect(find.text('Corrective work · Draft revision 1'), findsOneWidget);
        expect(
          find.text('Check fasteners and mounting points.'),
          findsOneWidget,
        );
        await _capture(tester, 'normal-plan-reopened-${scale.toInt()}x');
      },
    );
  }
}
