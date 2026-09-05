import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Only the private internal build config supplies these values. Release builds
// never load the environment value or expose the dev persona switchboard.
const _passwords = kDebugMode
    ? String.fromEnvironment('DEV_LOGIN_PASSWORDS', defaultValue: '{}')
    : '{}';

final devLoginPasswordsProvider = Provider<Map<String, String>>((ref) {
  return parseDevLoginPasswords(
    _passwords,
    debugBuild: kDebugMode,
    supabaseUrl: const String.fromEnvironment('SUPABASE_URL'),
  );
});

Map<String, String> parseDevLoginPasswords(
  String encoded, {
  required bool debugBuild,
  required String supabaseUrl,
}) {
  if (!debugBuild ||
      supabaseUrl != 'https://hkjpojobdbbtjkhaudki.supabase.co') {
    return const {};
  }
  try {
    final decoded = jsonDecode(encoded);
    if (decoded is! Map<String, dynamic>) return const {};
    return Map.unmodifiable({
      for (final entry in decoded.entries)
        if (entry.key.endsWith('@vortice.dev') &&
            entry.value is String &&
            (entry.value as String).isNotEmpty)
          entry.key: entry.value as String,
    });
  } on FormatException {
    return const {};
  }
}
