/// External-agent authority is independent of office and mechanic identities.
class AgentGrant {
  AgentGrant({
    required this.id,
    required this.actorId,
    required this.workspaceId,
    required this.companyId,
    required this.deviceId,
    required this.expiresAt,
    required Set<String> commands,
    this.revoked = false,
    Set<String>? jobIds,
    Set<String>? equipmentIds,
  }) : commands = Set.unmodifiable(commands),
       jobIds = jobIds == null ? null : Set.unmodifiable(jobIds),
       equipmentIds = equipmentIds == null
           ? null
           : Set.unmodifiable(equipmentIds);
  final String id, actorId, workspaceId, companyId, deviceId;
  final DateTime expiresAt;
  final bool revoked;
  final Set<String> commands;
  final Set<String>? jobIds, equipmentIds;
}

abstract interface class GrantProvider {
  Future<AgentGrant?> resolve(String token);
}

class DenyAgentGrants implements GrantProvider {
  const DenyAgentGrants();
  @override
  Future<AgentGrant?> resolve(String token) async => null;
}
