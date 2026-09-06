import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/auth/password_recovery.dart';

void main() {
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
