import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/app.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/manual_fault_intake.dart';
import 'package:maintenance_local/manual_fault_intake_store.dart';
import 'package:maintenance_local/model.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';
import 'package:maintenance_local/ui/manual_fault_intake_page.dart';
import 'support/native_widget_cleanup.dart';

const _boundary = Key('manual-fault-workspace-render');

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

Future<void> _tap(
  WidgetTester tester,
  Finder target, {
  String? captureBeforeTap,
}) async {
  expect(target, findsOneWidget);
  for (var frame = 0; frame < 12; frame++) {
    await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
    await _settle(tester);
    if (target.hitTestable().evaluate().length == 1) break;
  }
  expect(target.hitTestable(), findsOneWidget);
  if (captureBeforeTap != null) await _capture(tester, captureBeforeTap);
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
    testWidgets('Home reports a fault and preserves inspection at ${scale}x', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late Directory root;
      late LabStore store;
      late String job, originalCatalog, originalDocument;
      await tester.runAsync(() async {
        root = await Directory.systemTemp.createTemp('fault-workspace-');
        store = await LabStore.open(
          Directory('${root.path}/office'),
          office: true,
          maintenanceOnly: true,
        );
        await store.createCompany('Synthetic fault intake company');
        final equipment = await store.addEquipment(
          name: 'Synthetic compressor',
          meterUnit: 'hours',
        );
        final checklist = await store.publishChecklist(
          title: 'Synthetic guard check',
          items: [
            {'id': 'guard', 'label': 'Check guard', 'input_type': 'check'},
          ],
        );
        job =
            (await store.prepareWork(
                  equipmentId: equipment['id'] as String,
                  templateId: checklist['id'] as String,
                  title: 'Existing synthetic inspection',
                ))['id']
                as String;
        originalCatalog = canonical(store.catalog);
        originalDocument = digest(store.documentFor(job)!);
      });
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await finishNativeWidgetCleanup(tester, () async {
          await store.close();
          await root.delete(recursive: true);
        });
      });
      await tester.pumpWidget(
        RepaintBoundary(
          key: _boundary,
          child: LabApp(store: store, textScale: scale, officePort: 0),
        ),
      );
      await _settle(tester);
      await _tap(
        tester,
        find.text('Reported faults'),
        captureBeforeTap: 'home-fault-entry-${scale.toInt()}x',
      );
      expect(find.byType(ManualFaultIntakePage), findsOneWidget);
      await _capture(tester, 'home-fault-list-${scale.toInt()}x');
      await _tap(tester, find.byKey(const Key('manual-fault-new')));
      await _tap(tester, find.byKey(const Key('manual-fault-equipment')));
      await _tap(tester, find.text('Use this equipment'));
      final description = find.byKey(const Key('manual-fault-description'));
      await tester.ensureVisible(description);
      await tester.enterText(
        description,
        'Synthetic guard rattles under load.',
      );
      await _settle(tester);
      await _tap(tester, find.byKey(const Key('manual-fault-severity-urgent')));
      await _tap(tester, find.byKey(const Key('manual-fault-submit')));
      expect(find.byType(ManualFaultIntakePage), findsOneWidget);
      await _tap(tester, find.text('View fault record'));
      expect(find.text('Synthetic guard rattles under load.'), findsOneWidget);
      expect(find.text(manualFaultReportedStatus), findsOneWidget);
      await _capture(tester, 'home-fault-detail-${scale.toInt()}x');
      await _tap(tester, find.byTooltip('Back'));
      await _tap(tester, find.byTooltip('Back'));
      expect(find.text('Vortice · Local Maintenance'), findsOneWidget);
      expect(find.text('Existing synthetic inspection'), findsOneWidget);
      await tester.runAsync(() async {
        final records = await ManualFaultIntakeStore(store).listRecords();
        expect(records, hasLength(1));
        expect(records.single.severity, ManualFaultSeverity.urgent);
        expect(records.single.origin, isNull);
        expect(canonical(store.catalog), originalCatalog);
        expect(digest(store.documentFor(job)!), originalDocument);
        expect(store.activeJobId, job);
        expect(store.submissions, isEmpty);
        expect(store.receipts, isEmpty);
      });
      await _settle(tester);
    });
  }
}
