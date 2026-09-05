import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/core/constants.dart';

void main() {
  test('runtime backend settings use the supplied build configuration', () {
    const url = String.fromEnvironment('SUPABASE_URL');
    const key = String.fromEnvironment('SUPABASE_ANON_KEY');
    // Compare booleans so failures never print real build credentials.
    expect(
      AppConstants.supabaseUrl == url,
      isTrue,
      reason: 'Runtime URL must use SUPABASE_URL',
    );
    expect(
      AppConstants.supabaseAnonKey == key,
      isTrue,
      reason: 'Runtime API key must use SUPABASE_ANON_KEY',
    );
  });
}
