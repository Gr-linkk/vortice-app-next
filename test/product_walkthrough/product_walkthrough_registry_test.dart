import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/product_walkthrough/product_walkthrough_checks.dart';

void main() {
  test('product walkthrough registry matches backlog doc', () {
    expect(productWalkthroughChecks.length, 203);
    expect(
      productWalkthroughChecks.map((check) => check.backlogId).toSet().length,
      48,
    );
  });
}
