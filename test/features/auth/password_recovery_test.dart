import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/auth/password_recovery.dart';

void main() {
  test('browser recovery accepts only the selected same-origin callback', () {
    final app = Uri.parse('https://next.example/app/');
    expect(
      isBrowserRecoveryCallback(
        Uri.parse('https://next.example/app/?vortice_recovery=1&code=fixture'),
        app,
      ),
      isTrue,
    );
    for (final address in [
      'https://other.example/app/?vortice_recovery=1&code=fixture',
      'https://next.example/other/?vortice_recovery=1&code=fixture',
      'https://next.example/app/?code=fixture',
    ]) {
      expect(isBrowserRecoveryCallback(Uri.parse(address), app), isFalse);
    }
  });
  test('only the isolated app recovery callback is recognized', () {
    expect(
      isRecoveryCallback(Uri.parse('$recoveryRedirect?code=synthetic')),
      true,
    );
    expect(
      isRecoveryCallback(Uri.parse('https://unrelated.example/auth/recovery')),
      false,
    );
    expect(
      isRecoveryCallback(Uri.parse('com.vortice.next://auth/other')),
      false,
    );
  });
  test(
    'password confirmation and minimum length are enforced in both languages',
    () {
      expect(validateRecoveryPassword('short', 'short', false), isNotNull);
      expect(
        validateRecoveryPassword('long password', 'different', true),
        contains('coinciden'),
      );
      expect(
        validateRecoveryPassword('long password', 'long password', false),
        isNull,
      );
    },
  );
}
