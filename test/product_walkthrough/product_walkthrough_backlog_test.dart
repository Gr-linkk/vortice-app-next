import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/product_walkthrough/product_walkthrough_checks.dart';
import 'package:vortice_app/product_walkthrough/product_walkthrough_coverage.dart';
import 'package:vortice_app/product_walkthrough/product_walkthrough_verifiers.dart';

void main() {
  group('Product walkthrough scoreboard', () {
    test('reports backlog coverage summary', () {
      final summary = summarizeProductWalkthroughCoverage();

      // ignore: avoid_print
      print(
        'Product walkthrough backlog: ${summary.failing.length} failing / '
        '${summary.total} total checks',
      );

      for (final check in summary.failing.take(20)) {
        // ignore: avoid_print
        print('  FAIL ${check.id}: ${check.description}');
      }
      if (summary.failing.length > 20) {
        // ignore: avoid_print
        print('  ... and ${summary.failing.length - 20} more');
      }

      expect(summary.total, 203);
      expect(summary.passing.length + summary.failing.length, 203);
    });

    for (final check in productWalkthroughChecks) {
      test('${check.id} ${check.description}', () {
        expect(
          verifyProductWalkthroughCheck(check.backlogId, check.checkIndex),
          isTrue,
          reason:
              'Backlog ${check.backlogId} check ${check.checkIndex}: ${check.description}',
        );
      });
    }
  }, skip: 'Run explicitly: flutter test test/product_walkthrough/product_walkthrough_backlog_test.dart');
}
