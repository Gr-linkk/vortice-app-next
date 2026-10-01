import 'access_scope.dart';
import 'grants.dart';

enum OfficeAgentHostState {
  disabled,
  starting,
  listening,
  stopping,
  unavailable,
  closed,
}

class OfficeAgentHostSnapshot {
  const OfficeAgentHostSnapshot({
    required this.state,
    required this.enabled,
    this.scope,
    this.socketPath,
    this.problem,
  });
  final OfficeAgentHostState state;

  /// Last durably saved owner intent; listening is a separate fact.
  final bool enabled;
  final AgentAccessScope? scope;
  final String? socketPath;

  /// Fixed plain-language guidance, without native errors or credentials.
  final String? problem;
}

class OfficeAgentGrantSummary {
  const OfficeAgentGrantSummary({
    required this.grant,
    required this.label,
    required this.createdAt,
    this.revokedAt,
  });
  final AgentGrant grant;
  final String label;
  final DateTime createdAt;
  final DateTime? revokedAt;
}

class IssuedAgentGrant {
  const IssuedAgentGrant({required this.token, required this.summary});

  /// Shown once following an explicit owner action. Never persisted plaintext.
  final String token;
  final OfficeAgentGrantSummary summary;
}

class AgentGrantRequest {
  AgentGrantRequest({
    required this.label,
    required this.expiresAt,
    required Set<String> jobIds,
    required Set<String> equipmentIds,
    this.allowNotes = false,
  }) : jobIds = Set.unmodifiable(jobIds),
       equipmentIds = Set.unmodifiable(equipmentIds);
  final String label;
  final DateTime expiresAt;
  final Set<String> jobIds, equipmentIds;
  final bool allowNotes;
}
