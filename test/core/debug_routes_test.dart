import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/core/router.dart';

void main() {
  group('buildDebugQaRoutes', () {
    test('omits QA routes when debug QA is disabled', () {
      expect(buildDebugQaRoutes(enabled: false), isEmpty);
    });

    test('registers the route QA screen when debug QA is enabled', () {
      final routes = buildDebugQaRoutes(enabled: true);

      expect(routes, hasLength(1));
    });
  });
}
