import 'dart:io';

/// Keep each connected run's manifests and evidence together for exact cleanup.
String auditOutputPath(String relative) {
  final configured = Platform.environment['VORTICE_E2E_OUTPUT'];
  final directory = Directory(
    configured == null || configured.trim().isEmpty ? 'outputs' : configured,
  )..createSync(recursive: true);
  return '${directory.path}/$relative';
}
