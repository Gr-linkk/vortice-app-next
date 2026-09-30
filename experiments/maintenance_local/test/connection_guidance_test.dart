import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/local_sync.dart';

void main() {
  const raw =
      'Bearer private-token invitation=secret key=PRIVATE-KEY https://192.168.1.8:47841/private';

  test(
    'unreachable, refused and timed out connections give a safe next step',
    () {
      final failures = <Object>[
        SocketException(raw, osError: const OSError(raw, 113)),
        SocketException(raw, osError: const OSError(raw, 111)),
        SocketException(raw, osError: const OSError(raw, 110)),
        TimeoutException(raw),
        const HttpException(raw),
      ];
      for (final failure in failures) {
        final guidance = connectionGuidance(failure)!;
        expect(guidance.message, 'Cannot reach the computer.');
        expect(guidance.nextStep, contains('same Wi-Fi or hotspot'));
        expect(guidance.nextStep, contains('both apps open'));
        expect(guidance.details, contains('Update computer connection'));
        expect(guidance.details, contains('same office computer'));
        expect(guidance.details, contains('network administrator'));
        expect(guidance.details, contains('TCP 47841'));
        expect(connectionProblem(failure), guidance.text);
        for (final secret in [
          'private-token',
          'secret',
          'PRIVATE-KEY',
          '/private',
        ]) {
          expect(guidance.text, isNot(contains(secret)));
        }
        expect(guidance.text, isNot(contains('firewall')));
        expect(guidance.text, isNot(contains('VPN')));
      }
    },
  );

  test('TLS identity failures do not suggest a network retry', () {
    for (final failure in [
      const HandshakeException(raw),
      const TlsException(raw),
    ]) {
      final guidance = connectionGuidance(failure)!;
      expect(guidance.message, contains('identity could not be verified'));
      expect(guidance.nextStep, contains('same office computer'));
      expect(guidance.nextStep, contains('verified backup'));
      expect(guidance.text, isNot(contains(raw)));
      expect(guidance.text, isNot(contains('retry')));
    }
  });

  test(
    'malformed connections are redacted and backup errors remain actionable',
    () {
      expect(
        connectionProblem(const FormatException(raw)),
        isNot(contains(raw)),
      );
      final error = StateError(
        'The computer identity is incomplete. Files have been retained. Restore a verified office backup.',
      );
      expect(connectionGuidance(error), isNull);
      expect(connectionProblem(error), error.message);
    },
  );
}
