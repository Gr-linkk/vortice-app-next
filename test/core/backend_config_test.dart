import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/core/backend_config.dart';

void main() {
  const url = 'https://hkjpojobdbbtjkhaudki.supabase.co';
  String token(String role, {String ref = 'hkjpojobdbbtjkhaudki'}) =>
      'header.${base64Url.encode(utf8.encode(jsonEncode({'role': role, 'ref': ref})))}.signature';

  test('accepts public key formats only on the authorized host', () {
    validateBackendConfig(url, 'sb_publishable_fixture');
    validateBackendConfig(url, token('anon'));
    for (final host in ['', 'https://unrelated.invalid', '$url/']) {
      expect(
        () => validateBackendConfig(host, token('anon')),
        throwsStateError,
      );
    }
  });

  test(
    'rejects privileged, wrong-project, missing and malformed keys safely',
    () {
      final keys = [
        '',
        'PLACEHOLDER',
        'sb_${'secret'}_fixture',
        token('service_role'),
        token('authenticated'),
        token('anon', ref: 'unrelated'),
        'header.invalid.signature',
        'header.W10.signature',
        'header.e30.signature',
      ];
      for (final key in keys) {
        expect(
          () => validateBackendConfig(url, key),
          throwsA(
            isA<StateError>().having(
              (error) => key.isEmpty || !error.toString().contains(key),
              'does not expose the key',
              isTrue,
            ),
          ),
        );
      }
    },
  );
}
