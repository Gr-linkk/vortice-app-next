import 'dart:convert';

/// Fail before initialization if an internal build is misconfigured. Never put
/// key values in exceptions: these errors can reach device or build logs.
void validateBackendConfig(String url, String key) {
  const projectRef = 'hkjpojobdbbtjkhaudki';
  if (url != 'https://$projectRef.supabase.co') {
    throw StateError(
      'Backend must target the authorized Vortice Next project.',
    );
  }
  if (RegExp(r'^sb_publishable_[A-Za-z0-9_-]+$').hasMatch(key)) return;
  try {
    final parts = key.split('.');
    if (parts.length != 3 || parts.any((part) => part.isEmpty)) {
      throw const FormatException();
    }
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    if (payload is Map<String, dynamic> &&
        payload['role'] == 'anon' &&
        payload['ref'] == projectRef) {
      return;
    }
  } on FormatException {
    // Validation identifies public-client configuration, not JWT authenticity;
    // Supabase verifies the signature. Reject unknown and privileged key types.
  }
  throw StateError('Backend requires a public publishable or Next anon key.');
}
