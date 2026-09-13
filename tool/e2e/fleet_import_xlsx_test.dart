import 'dart:io';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'connected_harness.dart';
import 'audit_output.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'XLSX file selection, cancel, worksheet, header and duplicate review',
    (tester) async {
      await tester.runAsync(() async {
        final h = ConnectedHarness(tester, report: 'next007-xlsx');
        await h.start();
        const channel = MethodChannel('plugins.flutter.io/file_selector');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        try {
          await h.login('demo_fleet_owner@vortice.dev');
          final existing =
              (await supabase
                      .from('assets')
                      .select('name,asset_types(name)')
                      .limit(1))
                  .single;
          await h.go('/assets/import');
          await h.step(
            'cancelling the file picker keeps the import empty',
            () async {
              messenger.setMockMethodCallHandler(channel, (_) async => null);
              await h.tap(find.text('Choose spreadsheet'));
              expect(find.text('Choose a table'), findsOneWidget);
            },
          );
          await h.step(
            'real XLSX bytes decode, sheet and header selection map the table',
            () async {
              final workbook = Excel.createExcel();
              workbook['Instructions'].appendRow([
                TextCellValue('Example export'),
              ]);
              workbook['Fleet'].appendRow([
                TextCellValue('Fleet export title'),
              ]);
              workbook['Fleet'].appendRow([
                TextCellValue('Name'),
                TextCellValue('Type'),
                TextCellValue('Serial'),
              ]);
              workbook['Fleet'].appendRow([
                TextCellValue(existing['name'] as String),
                TextCellValue(
                  (existing['asset_types'] as Map)['name'] as String,
                ),
                TextCellValue('00001234'),
              ]);
              workbook.delete('Sheet1');
              final file = File(auditOutputPath('fleet-export.xlsx'))
                ..writeAsBytesSync(workbook.encode()!);
              messenger.setMockMethodCallHandler(
                channel,
                (_) async => [file.absolute.path],
              );
              await h.tap(find.text('Choose spreadsheet'));
              expect(find.text('Match columns'), findsOneWidget);
              await h.select('Worksheet', 'Fleet');
              await h.select('Header row', '2: Name · Type · Serial');
              await h.screenshot('xlsx-sheet-header-mapping');
              await h.tap(find.text('Preview import'));
              await h.reveal(find.textContaining('Already in this fleet'));
              expect(find.byKey(const Key('import-confirm')), findsNothing);
              await h.screenshot('xlsx-reviewed-duplicate');
            },
          );
        } finally {
          messenger.setMockMethodCallHandler(channel, null);
          await h.close();
        }
        expect(h.issues, isEmpty);
      });
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
