import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/service_requests/service_request_form_support.dart';

void main() {
  group('isOtherAssetSelection', () {
    test('returns true for other asset sentinel', () {
      expect(isOtherAssetSelection(kServiceRequestOtherAssetValue), isTrue);
    });

    test('returns false for asset id or null', () {
      expect(isOtherAssetSelection('asset-1'), isFalse);
      expect(isOtherAssetSelection(null), isFalse);
    });
  });

  group('parseServiceRequestEngineHours', () {
    test('returns null for empty input', () {
      expect(parseServiceRequestEngineHours(null), isNull);
      expect(parseServiceRequestEngineHours(''), isNull);
      expect(parseServiceRequestEngineHours('   '), isNull);
    });

    test('parses decimal values and strips commas', () {
      expect(parseServiceRequestEngineHours('1250.5'), 1250.5);
      expect(parseServiceRequestEngineHours('1,250.5'), 1250.5);
    });
  });

  group('validateServiceRequestAssetSelection', () {
    test('requires a selection', () {
      expect(validateServiceRequestAssetSelection(null), isNotNull);
      expect(validateServiceRequestAssetSelection(''), isNotNull);
      expect(validateServiceRequestAssetSelection('asset-1'), isNull);
    });
  });

  group('validateServiceRequestOtherAssetName', () {
    test('requires name when other asset is selected', () {
      expect(
        validateServiceRequestOtherAssetName(null, isOtherAsset: true),
        isNotNull,
      );
      expect(
        validateServiceRequestOtherAssetName('  ', isOtherAsset: true),
        isNotNull,
      );
      expect(
        validateServiceRequestOtherAssetName('Dredge 2', isOtherAsset: true),
        isNull,
      );
    });

    test('skips validation when not other asset', () {
      expect(
        validateServiceRequestOtherAssetName(null, isOtherAsset: false),
        isNull,
      );
    });
  });

  group('validateServiceRequestEngineHours', () {
    test('allows empty optional field', () {
      expect(validateServiceRequestEngineHours(null), isNull);
      expect(validateServiceRequestEngineHours(''), isNull);
    });

    test('rejects invalid or negative values', () {
      expect(validateServiceRequestEngineHours('abc'), isNotNull);
      expect(validateServiceRequestEngineHours('-1'), isNotNull);
    });

    test('accepts valid hours', () {
      expect(validateServiceRequestEngineHours('100'), isNull);
      expect(validateServiceRequestEngineHours('1,000.5'), isNull);
    });
  });

  group('validateServiceRequestDescription', () {
    test('requires non-empty description', () {
      expect(validateServiceRequestDescription(null), isNotNull);
      expect(validateServiceRequestDescription('  '), isNotNull);
      expect(validateServiceRequestDescription('Leak at port engine'), isNull);
    });
  });

  group('validateServiceRequestContact', () {
    test('requires contact info', () {
      expect(validateServiceRequestContact(null), isNotNull);
      expect(validateServiceRequestContact(''), isNotNull);
      expect(validateServiceRequestContact('+1 555-0100'), isNull);
    });
  });

  group('resolveServiceRequestAssetId', () {
    test('returns null for other asset selection', () {
      expect(
        resolveServiceRequestAssetId(kServiceRequestOtherAssetValue),
        isNull,
      );
    });

    test('returns asset id for normal selection', () {
      expect(resolveServiceRequestAssetId('asset-42'), 'asset-42');
    });
  });

  group('resolveServiceRequestOtherAssetName', () {
    test('returns trimmed name for other asset selection', () {
      expect(
        resolveServiceRequestOtherAssetName(
          kServiceRequestOtherAssetValue,
          '  Custom dredge  ',
        ),
        'Custom dredge',
      );
    });

    test('returns null when not other asset or empty', () {
      expect(
        resolveServiceRequestOtherAssetName('asset-1', 'ignored'),
        isNull,
      );
      expect(
        resolveServiceRequestOtherAssetName(
          kServiceRequestOtherAssetValue,
          '   ',
        ),
        isNull,
      );
    });
  });
}
