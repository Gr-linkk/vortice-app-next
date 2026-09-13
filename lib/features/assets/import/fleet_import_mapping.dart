import 'dart:convert';
import '../asset_type_provider.dart';

class FleetImportReview {
  FleetImportReview(this.assets, this.rows, this.errors);
  final List<Map<String, dynamic>> assets;

  /// Source spreadsheet rows for each grouped equipment record.
  final List<List<int>> rows;
  final Map<int, String> errors;
}

class FleetImportMapping {
  FleetImportMapping({
    required this.columns,
    required this.types,
    this.defaultType,
    this.defaultUnit = 'hours',
    this.dateFormat = 'iso',
    this.decimalComma = false,
    this.template,
    this.typeValues = const {},
  });
  final Map<String, int> columns;
  final List<AssetType> types;
  final String? defaultType, template;
  final String defaultUnit, dateFormat;
  final bool decimalComma;
  final Map<String, String> typeValues;

  FleetImportReview review(
    List<List<String>> table,
    int headerRow, {
    Set<int> excluded = const {},
    List<Map<String, dynamic>> existing = const [],
  }) {
    final assets = <Map<String, dynamic>>[];
    final sources = <List<int>>[];
    final errors = <int, String>{};
    final exactRows = <String>{};
    for (var index = headerRow + 1; index < table.length; index++) {
      final rowNumber = index + 1;
      if (excluded.contains(rowNumber) ||
          table[index].every((s) => s.trim().isEmpty)) {
        continue;
      }
      final row = table[index];
      String get(String key) {
        final col = columns[key];
        final value = col == null || col >= row.length ? '' : row[col].trim();
        if (value.startsWith('=')) {
          throw const FormatException(
            'Replace formulas with their values before importing.',
          );
        }
        return value;
      }

      try {
        final name = get('name');
        if (name.isEmpty) {
          throw const FormatException(
            'Map a column containing equipment names.',
          );
        }
        final serial = get('serial_number');
        if (existing.any(
          (a) =>
              _same(a['name'], name) ||
              (serial.isNotEmpty && _same(a['serial_number'], serial)),
        )) {
          throw const FormatException(
            'Already in this fleet. Exclude this row or correct its identity.',
          );
        }
        final typeText = get('asset_type_id');
        final type = typeText.isEmpty
            ? defaultType
            : typeValues[typeText] ??
                  types
                      .where((t) => _same(t.name, typeText) || t.id == typeText)
                      .firstOrNull
                      ?.id;
        if (type == null || !types.any((t) => t.id == type)) {
          throw FormatException(
            'Choose an equipment type${typeText.isEmpty ? '' : ': $typeText'}.',
          );
        }
        final unit = _unit(get('meter_unit'), defaultUnit);
        final asset = <String, dynamic>{
          'name': name,
          'asset_type_id': type,
          'meter_unit': unit,
          for (final key in [
            'serial_number',
            'make',
            'model',
            'location',
            'notes',
          ])
            if (get(key).isNotEmpty) key: get(key),
          if (get('year').isNotEmpty) 'year': _integer(get('year')),
        };
        final components = <Map<String, dynamic>>[];
        final opening = _number(get('current_hours'));
        if (opening != null) {
          components.add({
            'label': 'Equipment meter',
            'kind': 'other',
            'primary_meter': true,
            'meter_unit': unit,
            'current_hours': opening,
            'plans': <Map<String, dynamic>>[],
          });
        }
        final label = get('component');
        final componentFields = [
          'component_serial',
          'component_make',
          'component_model',
          'component_meter',
          'component_unit',
        ];
        if (label.isEmpty && componentFields.any((k) => get(k).isNotEmpty)) {
          throw const FormatException(
            'A component name is required for component details.',
          );
        }
        if (label.isNotEmpty) {
          if (_same(label, 'Equipment meter')) {
            throw const FormatException(
              'Use a distinct component name; Equipment meter is reserved for the equipment reading.',
            );
          }
          components.add({
            'label': label,
            'kind': 'other',
            'meter_unit': _unit(get('component_unit'), unit),
            for (final key in ['serial', 'make', 'model'])
              if (get('component_$key').isNotEmpty)
                (key == 'serial' ? 'serial_number' : key): get(
                  'component_$key',
                ),
            if (get('component_meter').isNotEmpty)
              'current_hours': _number(get('component_meter')),
            'plans': <Map<String, dynamic>>[],
          });
        }
        final serviceKeys = [
          'interval_label',
          'interval_hours',
          'interval_months',
          'last_service_hours',
          'last_service_date',
        ];
        if (serviceKeys.any((k) => get(k).isNotEmpty)) {
          if (get('interval_label').isEmpty) {
            throw const FormatException('Give the service plan a name.');
          }
          if (components.isEmpty) {
            components.add({
              'label': 'Equipment meter',
              'kind': 'other',
              'primary_meter': true,
              'meter_unit': unit,
              'plans': <Map<String, dynamic>>[],
            });
          }
          final c = components.last;
          final interval = get('interval_hours').isEmpty
              ? 0
              : _integer(get('interval_hours'));
          final months = get('interval_months').isEmpty
              ? null
              : _integer(get('interval_months'));
          final baseline = _number(get('last_service_hours'));
          if (interval <= 0 && months == null) {
            throw const FormatException(
              'Provide a meter interval or a monthly interval.',
            );
          }
          if (interval > 0 &&
              (baseline == null ||
                  c['current_hours'] == null ||
                  baseline > (c['current_hours'] as num))) {
            throw const FormatException(
              'A meter plan needs an opening reading and last-service reading no greater than it.',
            );
          }
          final date = get('last_service_date').isEmpty
              ? null
              : _date(get('last_service_date'));
          if (months != null && date == null) {
            throw const FormatException(
              'A monthly plan needs the last-service date.',
            );
          }
          (c['plans'] as List).add({
            'interval_label': get('interval_label'),
            'interval_hours': interval,
            if (months != null) 'interval_months': months,
            if (baseline != null) 'last_service_hours': baseline,
            if (date != null) 'last_service_date': date,
            if (template != null) 'template_id': template,
          });
        }
        final fingerprint = jsonEncode([asset, components]);
        if (!exactRows.add(fingerprint)) {
          throw const FormatException(
            'Repeated identical row. Exclude the extra copy.',
          );
        }
        final found = assets.indexWhere(
          (a) =>
              _same(a['name'], name) ||
              (serial.isNotEmpty && _same(a['serial_number'], serial)),
        );
        if (found == -1) {
          assets.add({...asset, 'components': components});
          sources.add([rowNumber]);
        } else {
          final old = assets[found];
          if (jsonEncode({...old}..remove('components')) != jsonEncode(asset)) {
            throw FormatException(
              'Equipment details conflict with row ${sources[found].first}. Match all equipment columns before combining components.',
            );
          }
          // Merge on a copy so a failed row cannot partially change the preview.
          final merged = (jsonDecode(jsonEncode(old['components'])) as List)
              .cast<Map<String, dynamic>>();
          for (final c in components) {
            final match = merged
                .where((m) => _same(m['label'], c['label']))
                .firstOrNull;
            if (match == null) {
              merged.add(c);
              continue;
            }
            if (jsonEncode({...match}..remove('plans')) !=
                jsonEncode({...c}..remove('plans'))) {
              throw FormatException(
                'Component ${c['label']} conflicts with an earlier row.',
              );
            }
            for (final plan in c['plans'] as List) {
              if ((match['plans'] as List).any(
                (p) => _same(p['interval_label'], plan['interval_label']),
              )) {
                throw FormatException(
                  'Repeated service plan ${plan['interval_label']}.',
                );
              }
              (match['plans'] as List).add(plan);
            }
          }
          old['components'] = merged;
          sources[found].add(rowNumber);
        }
      } on FormatException catch (e) {
        errors[rowNumber] = e.message;
      }
    }
    if (assets.length > 500) {
      errors[0] = 'Import at most 500 equipment records at a time.';
    }
    if (table.length - headerRow - 1 > 1000) {
      errors[0] = 'Import at most 1,000 data rows at a time.';
    }
    return FleetImportReview(assets, sources, errors);
  }

  static bool _same(dynamic a, dynamic b) =>
      (a?.toString().trim().toLowerCase() ?? '') ==
      b.toString().trim().toLowerCase();
  String _unit(String s, String fallback) {
    if (s.isEmpty) return fallback;
    final result = switch (s.toLowerCase()) {
      'hours' || 'hour' || 'hrs' || 'h' || 'horas' => 'hours',
      'km' || 'kilometers' || 'kilometres' => 'km',
      'mi' || 'miles' => 'mi',
      _ => null,
    };
    if (result == null) {
      throw FormatException('Unknown meter unit: $s. Use hours, km or mi.');
    }
    return result;
  }

  num? _number(String s) {
    if (s.isEmpty) return null;
    final pattern = decimalComma ? r'^\d+(,\d+)?$' : r'^\d+(\.\d+)?$';
    if (!RegExp(pattern).hasMatch(s)) {
      throw FormatException(
        'Invalid number: $s. Use the selected decimal separator without thousands separators.',
      );
    }
    final n = num.tryParse(s.replaceAll(',', '.'));
    if (n == null || !n.isFinite || n >= 1000000000) {
      throw FormatException('Number out of range: $s.');
    }
    return n;
  }

  int _integer(String s) {
    final n = _number(s)!;
    if (n != n.round()) {
      throw FormatException('A whole number is required: $s.');
    }
    return n.toInt();
  }

  String _date(String s) {
    int y, m, d;
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) {
      final p = s.split('-').map(int.parse).toList();
      y = p[0];
      m = p[1];
      d = p[2];
    } else if (dateFormat != 'iso' &&
        RegExp(r'^\d{1,2}[/.-]\d{1,2}[/.-]\d{4}$').hasMatch(s)) {
      final p = s.split(RegExp(r'[/.-]')).map(int.parse).toList();
      y = p[2];
      m = p[dateFormat == 'mdy' ? 0 : 1];
      d = p[dateFormat == 'mdy' ? 1 : 0];
    } else {
      throw FormatException(
        'Choose the date format for $s, or use YYYY-MM-DD.',
      );
    }
    final date = DateTime(y, m, d);
    if (date.year != y ||
        date.month != m ||
        date.day != d ||
        y < 1900 ||
        date.isAfter(DateTime.now())) {
      throw FormatException('Invalid last-service date: $s.');
    }
    return date.toIso8601String().split('T').first;
  }
}
