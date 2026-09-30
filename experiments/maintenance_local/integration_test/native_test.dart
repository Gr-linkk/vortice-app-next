import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:integration_test/integration_test.dart';
import 'package:maintenance_local/src/rust/api/documents.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => RustLib.init());
  testWidgets('Native persistence, conflict, and two-store protocol', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Native document checks'))),
    );
    await tester.pumpAndSettle();
    final root = await Directory.systemTemp.createTemp('vortice-native-proof-');
    try {
      final seed = await createDocument(
        actor: 'seed',
        fieldsJson: '{"meter":10}',
      );
      final a = await editDocument(
        bytes: seed,
        actor: 'phone',
        fieldsJson: '{"meter":11}',
      );
      final b = await editDocument(
        bytes: seed,
        actor: 'office',
        fieldsJson: '{"meter":12}',
      );
      final phone = File('${root.path}/phone.am');
      final office = File('${root.path}/office.am');
      await phone.writeAsBytes(a, flush: true);
      await office.writeAsBytes(b, flush: true);
      final merged = await mergeDocuments(
        left: await phone.readAsBytes(),
        right: await office.readAsBytes(),
      );
      expect(jsonDecode(await documentValues(bytes: merged))['meter'], [
        11,
        12,
      ]);
      final sa = await newSession();
      final sb = await newSession();
      var pa = await sa.step(bytes: await phone.readAsBytes(), incoming: null);
      var pb = await sb.step(
        bytes: await office.readAsBytes(),
        incoming: pa.message,
      );
      for (var i = 0; i < 12; i++) {
        pa = await sa.step(bytes: pa.document, incoming: pb.message);
        pb = await sb.step(bytes: pb.document, incoming: pa.message);
      }
      await phone.writeAsBytes(pa.document, flush: true);
      await office.writeAsBytes(pb.document, flush: true);
      expect(
        await documentValues(bytes: await phone.readAsBytes()),
        await documentValues(bytes: await office.readAsBytes()),
      );
      final resolved = await editDocument(
        bytes: pa.document,
        actor: 'office',
        fieldsJson: '{"meter":12}',
      );
      expect(jsonDecode(await documentValues(bytes: resolved))['meter'], [12]);
    } finally {
      await root.delete(recursive: true);
    }
  });
}
