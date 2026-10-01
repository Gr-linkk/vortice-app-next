import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/model.dart';
import 'package:maintenance_local/src/rust/api/documents.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';
import 'package:maintenance_local/ui/inspection_page.dart';

import 'support/native_widget_cleanup.dart';

const changedInspectionMessage =
    'Inspection changed. Review the updated work and submit again.';

Future<void> initializeEditorNative() => RustLib.init(
  externalLibrary: ExternalLibrary.open(
    Platform.environment['MAINTENANCE_NATIVE_LIBRARY'] ??
        File('rust/target/debug/librust_lib_sync_lab.so').absolute.path,
  ),
);

Future<Json> decodeEditorFields(Uint8List bytes) async =>
    jsonDecode(await documentValues(bytes: bytes)) as Json;

class EditorFixture {
  EditorFixture(this.root, this.store, this.job);
  final Directory root;
  final LabStore store;
  final String job;
  final updates = ValueNotifier<int>(0);
  static final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );

  static Future<EditorFixture> create({bool ready = true}) async {
    final root = await Directory.systemTemp.createTemp('inspection-coherence-');
    final store = await LabStore.open(
      Directory('${root.path}/office'),
      office: true,
      maintenanceOnly: true,
    );
    await store.createCompany('Synthetic inspection company');
    final equipment = await store.addEquipment(name: 'Synthetic generator');
    final template = await store.publishChecklist(
      title: 'Synthetic daily checks',
      items: [
        {
          'id': 'guard',
          'label': 'Inspect guard',
          'input_type': 'check',
          'allow_na': true,
        },
        {
          'id': 'pressure',
          'label': 'Oil pressure',
          'input_type': 'number',
          'min': 10,
          'max': 30,
          'unit': 'psi',
        },
        {'id': 'condition', 'label': 'General condition', 'input_type': 'text'},
      ],
    );
    final job = await store.prepareWork(
      equipmentId: equipment['id'] as String,
      templateId: template['id'] as String,
      title: 'Morning inspection',
    );
    final fixture = EditorFixture(root, store, job['id'] as String);
    if (ready) await fixture.fill();
    return fixture;
  }

  Future<void> fill({
    String notes = 'Guard inspected.',
    int revision = 1,
  }) async {
    await store.update({
      'answer:guard': {
        'result': revision == 1 ? 'pass' : 'action',
        'value': '',
      },
      'answer:pressure': {'result': 'pass', 'value': '${18 + revision}'},
      'answer:condition': {'result': 'pass', 'value': 'Condition $revision'},
      'meter': 100 + revision,
      'notes': notes,
    }, jobId: job);
    await store.attach([...png, if (revision > 1) revision], jobId: job);
  }

  Widget page({Future<Json> Function(Uint8List bytes)? decoder}) => MaterialApp(
    home: InspectionPage(
      store: store,
      jobId: job,
      updates: updates,
      decodeFields: decoder,
    ),
  );

  Future<void> close() async {
    updates.dispose();
    await store.close();
    await root.delete(recursive: true);
  }
}

Future<void> settleEditor(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(tester.takeException(), isNull);
}

Future<void> untilEditor(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 50 && !ready(); i++) {
    await settleEditor(tester);
  }
  expect(ready(), isTrue);
}

TextEditingController editorController(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(ValueKey(key))).controller!;

Future<EditorFixture> editorFixture(
  WidgetTester tester, {
  bool ready = true,
}) async {
  final fixture = (await tester.runAsync(
    () => EditorFixture.create(ready: ready),
  ))!;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await finishNativeWidgetCleanup(tester, fixture.close);
  });
  return fixture;
}

Future<void> enterEditor(WidgetTester tester, String key, String value) async {
  final field = find.byKey(ValueKey(key));
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
  await settleEditor(tester);
}

Future<void> tapEditor(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.runAsync(() => tester.tap(finder));
  await settleEditor(tester);
}

class PausedEditorDecode {
  Completer<void>? entered;
  Completer<void>? release;

  void arm() {
    entered = Completer<void>();
    release = Completer<void>();
  }

  Future<Json> call(Uint8List bytes) async {
    final fields = await decodeEditorFields(bytes);
    final waiting = release;
    if (waiting != null) {
      release = null;
      entered!.complete();
      await waiting.future;
    }
    return fields;
  }
}
