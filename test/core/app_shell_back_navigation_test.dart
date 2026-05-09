import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/core/app_shell.dart';
import 'package:vortice_app/models/profile.dart';

void main() {
  group('appShellBackFallbackRoute', () {
    test('owner top-level leaf falls back to owner dashboard', () {
      expect(
        appShellBackFallbackRoute(UserRole.owner, '/owner/assets'),
        '/owner/dashboard',
      );
    });

    test('owner dashboard has no fallback target', () {
      expect(
        appShellBackFallbackRoute(UserRole.owner, '/owner/dashboard'),
        isNull,
      );
    });

    test('client team roles fall back to client dashboard', () {
      expect(
        appShellBackFallbackRoute(UserRole.clientAdmin, '/org/admin'),
        '/client/dashboard',
      );
      expect(
        appShellBackFallbackRoute(UserRole.operator, '/operator/flags'),
        '/client/dashboard',
      );
    });
  });
}
