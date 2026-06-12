import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/engines/engine_screen_support.dart';

void main() {
  group('engineKindColor', () {
    test('maps known kinds to theme colors', () {
      expect(engineKindColor('main'), AppColors.primary);
      expect(engineKindColor('port'), AppColors.primary);
      expect(engineKindColor('generator'), AppColors.success);
      expect(engineKindColor('auxiliary'), AppColors.warning);
    });

    test('falls back to secondary for unknown kinds', () {
      expect(engineKindColor('unknown'), AppColors.textSecondary);
    });
  });

  group('displayEngineInfoValue', () {
    test('returns em dash for empty values', () {
      expect(displayEngineInfoValue(null), '—');
      expect(displayEngineInfoValue(''), '—');
      expect(displayEngineInfoValue('   '), '—');
    });

    test('returns trimmed value when present', () {
      expect(displayEngineInfoValue('Caterpillar'), 'Caterpillar');
    });
  });

  group('formatLatestEngineHoursSubtitle', () {
    test('formats hours when present', () {
      expect(formatLatestEngineHoursSubtitle(1250.5),
          '1250.5 hrs · latest WO');
    });

    test('returns placeholder when hours are missing', () {
      expect(
        formatLatestEngineHoursSubtitle(null),
        'No work order hours yet',
      );
    });
  });

  group('formatLatestEngineHoursDetail', () {
    test('formats detail value or em dash', () {
      expect(formatLatestEngineHoursDetail(100), '100.0 hrs');
      expect(formatLatestEngineHoursDetail(null), '—');
    });
  });

  group('trimToNull', () {
    test('returns null for blank strings', () {
      expect(trimToNull(''), isNull);
      expect(trimToNull('   '), isNull);
    });

    test('returns trimmed text', () {
      expect(trimToNull('  CAT  '), 'CAT');
    });
  });

  group('buildEngineFormPayload', () {
    test('builds normalized payload with optional fields nulled', () {
      final payload = buildEngineFormPayload(
        assetId: 'asset-1',
        kind: 'generator',
        make: '  CAT ',
        model: '',
        serialNumber: ' SN-1 ',
      );

      expect(payload['asset_id'], 'asset-1');
      expect(payload['label'], 'Generator');
      expect(payload['kind'], 'generator');
      expect(payload['make'], 'CAT');
      expect(payload['model'], isNull);
      expect(payload['serial_number'], 'SN-1');
    });
  });
}
