import 'package:vortice_app/product_walkthrough/product_walkthrough_checks.dart';
import 'package:vortice_app/product_walkthrough/product_walkthrough_verifiers.dart';

class WalkthroughCoverageSummary {
  const WalkthroughCoverageSummary({
    required this.passing,
    required this.failing,
  });

  final List<ProductWalkthroughCheck> passing;
  final List<ProductWalkthroughCheck> failing;

  int get total => passing.length + failing.length;
}

WalkthroughCoverageSummary summarizeProductWalkthroughCoverage() {
  final passing = <ProductWalkthroughCheck>[];
  final failing = <ProductWalkthroughCheck>[];
  for (final check in productWalkthroughChecks) {
    (verifyProductWalkthroughCheck(check.backlogId, check.checkIndex)
            ? passing
            : failing)
        .add(check);
  }
  return WalkthroughCoverageSummary(
    passing: passing,
    failing: failing,
  );
}
