import 'dart:convert';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/assets/asset_type_provider.dart';
import 'package:vortice_app/features/assets/import/fleet_import_table.dart';
import 'package:vortice_app/features/assets/import/fleet_import_mapping.dart';

void main() {
  const types = [AssetType(id: 'excavator', name: 'Excavator')];
  FleetImportReview review(
    String csv, {
    String date = 'iso',
    Set<int> excluded = const {},
  }) {
    final rows = FleetImportTable.text(csv).sheets.values.single;
    return FleetImportMapping(
      columns: suggestFleetColumns(rows.first),
      types: types,
      defaultType: 'excavator',
      dateFormat: date,
    ).review(rows, 0, excluded: excluded);
  }

  test('quoted commas, newlines, escaped quotes, trailing cells and BOM', () {
    final rows = FleetImportTable.text(
      '\uFEFFName,Notes,Serial\r\n"Pump, one","Line 1\nLine ""two""",00123\r\nTruck,,0001',
    ).sheets.values.single;
    expect(rows[1], ['Pump, one', 'Line 1\nLine "two"', '00123']);
    expect(rows[2], ['Truck', '', '0001']);
    expect(
      () => FleetImportTable.text('Name\n"unterminated'),
      throwsFormatException,
    );
  });
  test('semicolon/tab exports and UTF-16 preserve text identifiers', () {
    expect(
      FleetImportTable.text('Name;Serial\nPump;001').sheets.values.single[1],
      ['Pump', '001'],
    );
    const text = 'Name\tSerial\nPump\t0001';
    final bytes = Uint8List.fromList([
      255,
      254,
      ...text.codeUnits.expand((c) => [c & 255, c >> 8]),
    ]);
    expect(FleetImportTable.bytes(bytes, 'fleet.tsv').sheets.values.single[1], [
      'Pump',
      '0001',
    ]);
    expect(
      FleetImportTable.bytes(
        Uint8List.fromList(utf8.encode(text)),
        'fleet.txt',
      ).sheets.values.single[1],
      ['Pump', '0001'],
    );
    expect(
      () => FleetImportTable.bytes(bytes, 'fleet.xls'),
      throwsFormatException,
    );
  });
  test('XLSX sheets, title rows, date cells, formulas and text serials', () {
    final book = Excel.createExcel();
    final sheet = book['Fleet'];
    sheet.appendRow([TextCellValue('Export title')]);
    sheet.appendRow([
      TextCellValue('Name'),
      TextCellValue('Serial'),
      TextCellValue('Last service date'),
    ]);
    sheet.appendRow([
      TextCellValue('Pump'),
      TextCellValue('000123'),
      const DateCellValue(year: 2026, month: 1, day: 2),
    ]);
    book['Formula'].appendRow([const FormulaCellValue('1+1')]);
    final decoded = FleetImportTable.bytes(
      Uint8List.fromList(book.encode()!),
      'fleet.xlsx',
    );
    expect(decoded.sheets['Fleet']![2], ['Pump', '000123', '2026-01-02']);
    expect(decoded.sheets['Formula']![0][0].startsWith('='), isTrue);
    final rows = decoded.sheets['Fleet']!;
    final mapped = FleetImportMapping(
      columns: {'name': 0, 'serial_number': 1},
      types: types,
      defaultType: 'excavator',
    ).review(rows, 1);
    expect(mapped.assets.single['serial_number'], '000123');
  });
  test('bounded inputs and rejected formulas do not silently truncate', () {
    expect(
      () => FleetImportTable.text('a' * (FleetImportTable.maxBytes + 1)),
      throwsFormatException,
    );
    expect(
      () => FleetImportTable.text(List.filled(1027, 'Name').join('\n')),
      throwsFormatException,
    );
    expect(review('Name,Serial\n=1+1,001').errors[2], contains('formulas'));
  });
  test('merge components with matching equipment and preserve baselines', () {
    final data = review(
      'Name,Serial,Component,Component meter,Service name,Interval hours,Last service meter\nBoat,001,Port,125.5,Oil,250,100\nBoat,001,Starboard,200,Oil,250,150',
    );
    expect(data.errors, isEmpty);
    expect(data.assets, hasLength(1));
    final components = data.assets.single['components'] as List;
    expect(components, hasLength(2));
    expect(components[0]['current_hours'], 125.5);
    expect(components[1]['plans'][0]['last_service_hours'], 150);
    expect(data.rows, [
      [2, 3],
    ]);
  });
  test(
    'ambiguous and invalid dates, units and contradictory identities stop preview',
    () {
      const csv =
          'Name,Component,Service name,Interval months,Last service date\nBoat,Main,Inspection,6,01/02/2026';
      expect(review(csv).errors[2], contains('date format'));
      expect(
        ((review(csv, date: 'dmy').assets.single['components'] as List)
                    .single['plans']
                as List)
            .single['last_service_date'],
        '2026-02-01',
      );
      expect(
        review(csv.replaceAll('01/02/2026', '31/02/2026'), date: 'dmy').errors,
        isNotEmpty,
      );
      expect(review('Name,Meter unit\nTruck,gal').errors, isNotEmpty);
      expect(
        review(
          'Name,Serial,Component\nBoat,001,Port\nBoat,002,Starboard',
        ).errors[3],
        contains('conflict'),
      );
      expect(
        review('Name,Serial\nBoat,001\nBoat,001').errors[3],
        contains('Repeated'),
      );
      expect(
        review('Name,Serial\nBoat,001\nBoat,001', excluded: {3}).errors,
        isEmpty,
      );
    },
  );
  test(
    'unknown types need deliberate mapping and fleet duplicates are rejected',
    () {
      final rows = FleetImportTable.text(
        'Name,Type,Serial\nTruck,Source type,001',
      ).sheets.values.single;
      final mapping = FleetImportMapping(
        columns: suggestFleetColumns(rows.first),
        types: types,
        typeValues: {'Source type': 'excavator'},
      );
      expect(mapping.review(rows, 0).errors, isEmpty);
      expect(
        mapping
            .review(
              rows,
              0,
              existing: [
                {'name': 'Other', 'serial_number': '001'},
              ],
            )
            .errors[2],
        contains('Already'),
      );
    },
  );
  test('failed repeated component row cannot partially merge a service', () {
    final data = review(
      'Name,Component,Component meter,Service name,Interval hours,Last service meter\nBoat,Main,125,Oil,250,100\nBoat,Main,126,Fuel,250,100',
    );
    expect(data.errors[3], contains('conflicts'));
    expect(
      ((data.assets.single['components'] as List).single['plans'] as List),
      hasLength(1),
    );
  });
}
