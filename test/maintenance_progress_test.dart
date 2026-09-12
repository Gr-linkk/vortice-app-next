import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/core/meter_units.dart';
import 'package:vortice_app/features/maintenance/maintenance_progress.dart';
import 'package:vortice_app/features/maintenance/maintenance_recurrence.dart';

void main() {
  test(
    'shared report readiness rejects backward meters and incomplete evidence in either work path',
    () {
      WorkReportProgress progress(
        String meter, {
        bool required = true,
        List<String> evidence = const ['proof'],
      }) => WorkReportProgress(
        diagnosis: 'Seal leak',
        repair: 'Replaced and verified',
        meter: meter,
        meterRequired: required,
        startingMeter: 62000,
        items: const [
          {
            'id': 'step',
            'requires_photo': true,
            'definition': {'input_type': 'check'},
          },
        ],
        answers: const {
          'step': {'result': 'pass', 'photo_path': 'proof'},
        },
        evidence: evidence,
      );
      for (final meter in [
        '',
        'NaN',
        'Infinity',
        '-1',
        '61999',
        '1000000000',
      ]) {
        expect(progress(meter).complete, isFalse, reason: meter);
        expect(progress(meter).meterError(false), isNotNull);
      }
      expect(progress('62000').complete, isTrue);
      expect(progress('62010.5').complete, isTrue);
      expect(progress('', required: false).complete, isTrue);
      expect(progress('62010', evidence: []).complete, isFalse);
    },
  );
  test('distance display conversion retains separate original units', () {
    expect(convertDistance(10000, 'mi', 'km'), closeTo(16093.44, 0.00001));
    expect(convertDistance(16093.44, 'km', 'mi'), closeTo(10000, 0.00001));
    expect(() => convertDistance(100, 'hours', 'km'), throwsArgumentError);
    expect(formatMeter(62000, 'km'), '62000 km');
    expect(
      recurrenceSummary({
        'interval_hours': 10000,
        'interval_months': 12,
        'meter_unit': 'km',
      }, false),
      contains('10000 km'),
    );
    expect(
      recurrenceDueText({'next_due_hours': 72000, 'meter_unit': 'km'}, false),
      '72000 km',
    );
  });

  test('an attached failure stays incomplete after requesting a fault', () {
    final item = <String, dynamic>{
      'id': 'seal',
      'definition': {'input_type': 'check'},
    };
    final answers = <String, dynamic>{
      'seal': {
        'result': 'fail',
        'fault_requested': true,
        'issue_note': 'Leaking under pressure',
      },
    };
    expect(maintenanceCompletedItems([item], answers, []), 0);
    expect(
      maintenanceItemRequirement(item, answers, [], false),
      contains('Correct and verify'),
    );
    answers['seal'] = {'result': 'pass'};
    expect(maintenanceCompletedItems([item], answers, []), 1);
  });

  test(
    'attached progress requires both valid readings and linked evidence',
    () {
      final item = <String, dynamic>{
        'id': 'pressure',
        'requires_photo': true,
        'definition': {'input_type': 'number', 'min': 10, 'max': 20},
      };
      expect(
        maintenanceCompletedItems(
          [item],
          {
            'pressure': {'result': 'pass', 'note': '15'},
          },
          [],
        ),
        0,
      );
      expect(
        maintenanceCompletedItems(
          [item],
          {
            'pressure': {'result': 'pass', 'note': '30', 'photo_path': 'proof'},
          },
          ['proof'],
        ),
        0,
      );
      expect(
        maintenanceCompletedItems(
          [item],
          {
            'pressure': {'result': 'pass', 'note': '15', 'photo_path': 'proof'},
          },
          ['proof'],
        ),
        1,
      );
    },
  );
}
