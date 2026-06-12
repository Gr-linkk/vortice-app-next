import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/parts/pm_kits_support.dart';

void main() {
  group('pmKitPartCountLabel', () {
    test('uses singular for one part', () {
      expect(pmKitPartCountLabel(1), '1 part');
    });

    test('uses plural for multiple parts', () {
      expect(pmKitPartCountLabel(0), '0 parts');
      expect(pmKitPartCountLabel(3), '3 parts');
    });
  });

  group('formatAssetMakeModel', () {
    test('returns null when both values are empty', () {
      expect(formatAssetMakeModel(null, null), isNull);
      expect(formatAssetMakeModel('', ''), isNull);
    });

    test('joins make and model when present', () {
      expect(formatAssetMakeModel('Caterpillar', 'C32'), 'Caterpillar C32');
      expect(formatAssetMakeModel('Caterpillar', null), 'Caterpillar');
      expect(formatAssetMakeModel(null, 'C32'), 'C32');
    });
  });

  group('formatPmKitPartQty', () {
    test('defaults qty to 1 and unit to ea', () {
      expect(formatPmKitPartQty(null, null), '1 ea');
    });

    test('formats provided qty and unit', () {
      expect(formatPmKitPartQty(2.5, 'L'), '2.5 L');
      expect(formatPmKitPartQty(4, 'kg'), '4 kg');
    });
  });
}
