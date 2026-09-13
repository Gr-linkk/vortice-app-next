import 'dart:convert';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/assets/asset_type_provider.dart';
import 'package:vortice_app/features/assets/import/fleet_import_mapping.dart';
import 'package:vortice_app/features/assets/import/fleet_import_table.dart';

void main() {
  const types = [AssetType(id: 'excavator', name: 'Excavator')];
  FleetImportReview map(List<List<String>> rows, {int header = 0}) =>
      FleetImportMapping(
        columns: header < 0 ? {'name': 0} : suggestFleetColumns(rows[header]),
        types: types,
        defaultType: 'excavator',
      ).review(rows, header);

  for (final item in [
    ('comma CSV', 'fleet.csv', ',', '\r\n'),
    ('semicolon CSV', 'fleet.csv', ';', '\n'),
    ('tab-delimited CSV', 'fleet.csv', '\t', '\n'),
    ('TSV', 'fleet.tsv', '\t', '\r\n'),
    ('delimited TXT', 'fleet.txt', ';', '\n'),
    ('uppercase extension', 'FLEET.CSV', ',', '\n'),
    ('classic CR line endings', 'fleet.csv', ',', '\r'),
  ]) {
    test(
      '${item.$1}: decode and map equipment, text serial and decimal meter',
      () {
        final text = [
          'Name${item.$3}Serial${item.$3}Current meter',
          'Excavator 12${item.$3}00001234${item.$3}125.5',
        ].join(item.$4);
        final table = FleetImportTable.bytes(
          Uint8List.fromList(utf8.encode(text)),
          item.$2,
        );
        final result = map(table.sheets.values.single);
        expect(result.errors, isEmpty);
        expect(result.assets.single['serial_number'], '00001234');
        expect(
          (result.assets.single['components'] as List).single['current_hours'],
          125.5,
        );
      },
    );
  }

  for (final encoding in [
    'UTF-8',
    'UTF-8 BOM',
    'UTF-16 LE BOM',
    'UTF-16 BE BOM',
  ]) {
    test('$encoding: accented names and serials survive file decoding', () {
      const text = 'Name\tSerial\nGrúa hidráulica\t00001234';
      final bytes = switch (encoding) {
        'UTF-8' => utf8.encode(text),
        'UTF-8 BOM' => [239, 187, 191, ...utf8.encode(text)],
        'UTF-16 LE BOM' => [
          255,
          254,
          ...text.codeUnits.expand((c) => [c & 255, c >> 8]),
        ],
        _ => [
          254,
          255,
          ...text.codeUnits.expand((c) => [c >> 8, c & 255]),
        ],
      };
      final result = map(
        FleetImportTable.bytes(
          Uint8List.fromList(bytes),
          'fleet.tsv',
        ).sheets.values.single,
      );
      expect(result.errors, isEmpty);
      expect(result.assets.single['name'], 'Grúa hidráulica');
      expect(result.assets.single['serial_number'], '00001234');
    });
  }

  test('pasted spreadsheet and plain name list without a header', () {
    final pasted = map(
      FleetImportTable.text(
        'Name\tSerial\nExcavator\t0001',
      ).sheets.values.single,
    );
    expect(pasted.assets.single['serial_number'], '0001');
    final names = map(
      FleetImportTable.text(
        'Excavator\nGenerator\nWork truck',
      ).sheets.values.single,
      header: -1,
    );
    expect(names.errors, isEmpty);
    expect(names.assets.map((a) => a['name']), [
      'Excavator',
      'Generator',
      'Work truck',
    ]);
  });

  test('CSV title row: explicit delimiter and header selection', () {
    final rows = FleetImportTable.text(
      'Fleet export\nName;Serial\nExcavator;0001',
      delimiter: ';',
    ).sheets.values.single;
    expect(map(rows, header: 1).assets.single['serial_number'], '0001');
  });

  test(
    'XLSX: multiple worksheets, header offset, text serial and Excel date',
    () {
      final book = Excel.createExcel();
      book['Instructions'].appendRow([
        TextCellValue('Choose the Fleet worksheet'),
      ]);
      book['Fleet'].appendRow([TextCellValue('Export title')]);
      book['Fleet'].appendRow([
        for (final h in [
          'Name',
          'Serial',
          'Service name',
          'Interval months',
          'Last service date',
        ])
          TextCellValue(h),
      ]);
      book['Fleet'].appendRow([
        TextCellValue('Excavator'),
        TextCellValue('00001234'),
        TextCellValue('Inspection'),
        const IntCellValue(6),
        const DateCellValue(year: 2026, month: 1, day: 2),
      ]);
      final decoded = FleetImportTable.bytes(
        Uint8List.fromList(book.encode()!),
        'FLEET.XLSX',
      );
      expect(decoded.sheets.keys, containsAll(['Instructions', 'Fleet']));
      final result = map(decoded.sheets['Fleet']!, header: 1);
      expect(result.errors, isEmpty);
      expect(result.assets.single['serial_number'], '00001234');
      expect(
        (result.assets.single['components'] as List)
            .single['plans'][0]['last_service_date'],
        '2026-01-02',
      );
    },
  );

  for (final extension in [
    'xls',
    'xlsm',
    'ods',
    'numbers',
    'pdf',
    'jpg',
    'png',
    'docx',
    'json',
  ]) {
    test('$extension is rejected with export guidance', () {
      expect(
        () => FleetImportTable.bytes(
          Uint8List.fromList(utf8.encode('Name\nExcavator')),
          'fleet.$extension',
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('Export as XLSX'),
          ),
        ),
      );
    });
  }
  test(
    'corrupt XLSX and legacy Windows-1252 CSV fail instead of mangling data',
    () {
      expect(
        () =>
            FleetImportTable.bytes(Uint8List.fromList([1, 2, 3]), 'fleet.xlsx'),
        throwsFormatException,
      );
      expect(
        () => FleetImportTable.bytes(
          Uint8List.fromList([...utf8.encode('Name\nGr'), 250, 97]),
          'fleet.csv',
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('UTF-8'),
          ),
        ),
      );
    },
  );
  test('semicolon decimal-comma export needs its explicit number setting', () {
    final rows = FleetImportTable.text(
      'Name;Current meter\nExcavator;125,5',
    ).sheets.values.single;
    final result = FleetImportMapping(
      columns: suggestFleetColumns(rows.first),
      types: types,
      defaultType: 'excavator',
      decimalComma: true,
    ).review(rows, 0);
    expect(result.errors, isEmpty);
    expect(
      (result.assets.single['components'] as List).single['current_hours'],
      125.5,
    );
  });
}
