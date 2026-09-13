import 'dart:convert';
import 'dart:typed_data';
import 'package:excel/excel.dart';

/// Local-only table decoding. Never evaluates formulas or uploads source files.
class FleetImportTable {
  const FleetImportTable(this.sheets);
  final Map<String, List<List<String>>> sheets;
  static const maxBytes = 5 * 1024 * 1024;
  static const maxRows = 1025;

  static FleetImportTable text(String text, {String? delimiter}) {
    if (utf8.encode(text).length > maxBytes) {
      throw const FormatException('Use a table smaller than 5 MB.');
    }
    text = text.replaceFirst(RegExp(r'^\uFEFF'), '');
    delimiter ??= ['\t', ';', ','].reduce(
      (a, b) =>
          _count(text.split('\n').first, a) >= _count(text.split('\n').first, b)
          ? a
          : b,
    );
    final rows = <List<String>>[];
    var row = <String>[];
    var cell = StringBuffer();
    var quoted = false, closed = false;
    void endCell() {
      row.add(cell.toString());
      cell = StringBuffer();
      closed = false;
      if (row.length > 100) {
        throw const FormatException('Use at most 100 columns.');
      }
    }

    void endRow() {
      endCell();
      rows.add(row);
      row = [];
      if (rows.length > maxRows) {
        throw const FormatException('Use at most 1,000 data rows.');
      }
    }

    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (quoted) {
        if (ch == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            cell.write('"');
            i++;
          } else {
            quoted = false;
            closed = true;
          }
        } else {
          cell.write(ch);
        }
      } else if (ch == delimiter) {
        endCell();
      } else if (ch == '\r' || ch == '\n') {
        if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
        endRow();
      } else if (ch == '"' && cell.isEmpty && !closed) {
        quoted = true;
      } else {
        if (closed && ch.trim().isNotEmpty) {
          throw const FormatException('Unexpected text after a quoted cell.');
        }
        if (!closed) cell.write(ch);
      }
    }
    if (quoted) {
      throw const FormatException(
        'A quoted cell is missing its closing quote.',
      );
    }
    if (cell.isNotEmpty || row.isNotEmpty || closed) endRow();
    if (rows.isEmpty) throw const FormatException('The table is empty.');
    return FleetImportTable({'Table': rows});
  }

  static int _count(String line, String delimiter) {
    var quoted = false, count = 0;
    for (final ch in line.split('')) {
      if (ch == '"') quoted = !quoted;
      if (ch == delimiter && !quoted) count++;
    }
    return count;
  }

  static FleetImportTable bytes(
    Uint8List bytes,
    String name, {
    String? delimiter,
  }) {
    if (bytes.length > maxBytes) {
      throw const FormatException('Use a file smaller than 5 MB.');
    }
    if (name.toLowerCase().endsWith('.xlsx')) {
      // Check ZIP central-directory sizes before the Excel library inflates XML.
      // Reject ZIP64 and unreasonable expansion rather than exhausting a phone.
      final data = ByteData.sublistView(bytes);
      var expanded = 0, entries = 0;
      for (var i = 0; i + 46 <= bytes.length; i++) {
        if (data.getUint32(i, Endian.little) != 0x02014b50) continue;
        expanded += data.getUint32(i + 24, Endian.little);
        entries++;
        if (expanded > 20 * 1024 * 1024 || entries > 2000) {
          throw const FormatException(
            'Workbook is too complex. Export a smaller CSV table.',
          );
        }
        i +=
            45 +
            data.getUint16(i + 28, Endian.little) +
            data.getUint16(i + 30, Endian.little) +
            data.getUint16(i + 32, Endian.little);
      }
      if (entries == 0) throw const FormatException('Invalid XLSX workbook.');
      final workbook = Excel.decodeBytes(bytes);
      return FleetImportTable({
        for (final sheet in workbook.tables.entries)
          sheet.key: _sheet(sheet.value),
      });
    }
    if (!RegExp(r'\.(csv|tsv|txt)$', caseSensitive: false).hasMatch(name)) {
      throw const FormatException(
        'Export as XLSX, CSV or TSV, or paste a table. PDF, photos and older XLS files are not supported.',
      );
    }
    String text;
    if (bytes.length >= 2 &&
        ((bytes[0] == 255 && bytes[1] == 254) ||
            (bytes[0] == 254 && bytes[1] == 255))) {
      if (bytes.length.isOdd) {
        throw const FormatException('Incomplete UTF-16 file.');
      }
      final data = ByteData.sublistView(bytes);
      text = String.fromCharCodes([
        for (var i = 2; i < bytes.length; i += 2)
          data.getUint16(i, bytes[0] == 255 ? Endian.little : Endian.big),
      ]);
    } else {
      try {
        text = utf8.decode(bytes);
      } catch (_) {
        throw const FormatException(
          'Save the CSV with UTF-8 encoding, or paste the table.',
        );
      }
    }
    return FleetImportTable.text(
      text,
      delimiter:
          delimiter ?? (name.toLowerCase().endsWith('.tsv') ? '\t' : null),
    );
  }

  static List<List<String>> _sheet(Sheet sheet) {
    if (sheet.maxRows > maxRows || sheet.maxColumns > 100) {
      throw const FormatException(
        'Use at most 1,000 data rows and 100 columns per sheet.',
      );
    }
    return [
      for (final row in sheet.rows)
        [
          for (final cell in row)
            switch (cell?.value) {
              FormulaCellValue v => '=${v.formula}',
              DateCellValue v =>
                v.asDateTimeLocal().toIso8601String().split('T').first,
              DateTimeCellValue v =>
                '${v.year.toString().padLeft(4, '0')}-${v.month.toString().padLeft(2, '0')}-${v.day.toString().padLeft(2, '0')}',
              final v => v?.toString() ?? '',
            },
        ],
    ];
  }
}

const fleetImportFields = <String, (String, String)>{
  'name': ('Equipment name', 'Nombre del equipo'),
  'asset_type_id': ('Equipment type', 'Tipo de equipo'),
  'serial_number': ('Serial / VIN', 'Serie / VIN'),
  'make': ('Make', 'Marca'),
  'model': ('Model', 'Modelo'),
  'year': ('Year', 'Año'),
  'location': ('Location', 'Ubicación'),
  'notes': ('Notes', 'Notas'),
  'meter_unit': ('Equipment meter unit', 'Unidad del equipo'),
  'current_hours': ('Equipment opening meter', 'Lectura inicial del equipo'),
  'component': ('Component name', 'Nombre del componente'),
  'component_serial': ('Component serial', 'Serie del componente'),
  'component_make': ('Component make', 'Marca del componente'),
  'component_model': ('Component model', 'Modelo del componente'),
  'component_unit': ('Component meter unit', 'Unidad del componente'),
  'component_meter': (
    'Component opening meter',
    'Lectura inicial del componente',
  ),
  'interval_label': ('Service plan name', 'Nombre del plan'),
  'interval_hours': ('Service every (meter units)', 'Servicio cada (unidades)'),
  'interval_months': ('Service every (months)', 'Servicio cada (meses)'),
  'last_service_hours': ('Last service meter', 'Lectura del último servicio'),
  'last_service_date': ('Last service date', 'Fecha del último servicio'),
};

Map<String, int> suggestFleetColumns(List<String> headers) {
  const aliases = {
    'name': [
      'name',
      'assetname',
      'equipmentname',
      'unitnumber',
      'vehiclename',
      'equipment',
      'nombredelequipo',
    ],
    'asset_type_id': ['type', 'assettype', 'equipmenttype', 'vehicletype'],
    'serial_number': ['serial', 'serialnumber', 'vin', 'serialvin'],
    'meter_unit': ['meterunit', 'equipmentmeterunit'],
    'current_hours': [
      'currentmeter',
      'odometer',
      'currenthours',
      'equipmentopeningmeter',
    ],
    'component': ['component', 'componentname', 'enginename'],
    'component_meter': [
      'componentmeter',
      'enginehours',
      'componentopeningmeter',
    ],
    'interval_label': ['servicename', 'serviceplan', 'serviceplanname'],
    'interval_hours': [
      'serviceinterval',
      'intervalhours',
      'serviceeverymeterunits',
    ],
    'interval_months': ['intervalmonths', 'serviceeverymonths'],
    'last_service_hours': ['lastservicemeter', 'lastservicehours'],
    'last_service_date': ['lastservicedate'],
  };
  String norm(String s) => s.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
  return {
    for (final field in fleetImportFields.keys)
      if (headers.any(
        (h) => [
          norm(field),
          norm(fleetImportFields[field]!.$1),
          ...?aliases[field],
        ].contains(norm(h)),
      ))
        field: headers.indexWhere(
          (h) => [
            norm(field),
            norm(fleetImportFields[field]!.$1),
            ...?aliases[field],
          ].contains(norm(h)),
        ),
  };
}
