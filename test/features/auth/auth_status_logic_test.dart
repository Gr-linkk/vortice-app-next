import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/auth/auth_status_logic.dart';

void main() {
  group('authStatusWhileStreamLoading', () {
    test('treats cleared session as unauthenticated during stream reload', () {
      expect(authStatusWhileStreamLoading(null), AppAuthStatus.unauthenticated);
    });

    test('keeps loading when session still exists', () {
      final session = Session(
        accessToken: 'token',
        tokenType: 'bearer',
        user: const User(
          id: 'user-1',
          appMetadata: {},
          userMetadata: {},
          aud: 'authenticated',
          createdAt: '2026-01-01T00:00:00Z',
        ),
      );

      expect(authStatusWhileStreamLoading(session), AppAuthStatus.loading);
    });
  });
}
