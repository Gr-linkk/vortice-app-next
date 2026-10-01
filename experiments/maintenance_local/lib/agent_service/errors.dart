const agentErrorMessages = {
  'invalid_request': 'Send a complete valid version 1 request.',
  'unsupported_version': 'This protocol version is not supported.',
  'unauthorized': 'An explicit external-agent grant is required.',
  'grant_expired': 'This external-agent grant has expired.',
  'grant_revoked': 'This external-agent grant has been revoked.',
  'scope_mismatch': 'This grant does not match the requested scope.',
  'permission_denied': 'This grant does not allow that operation.',
  'not_found': 'This record is not available in the permitted scope.',
  'stale_context': 'The visible work changed. Read it again before continuing.',
  'idempotency_conflict':
      'This operation key was already used with different input.',
  'unsupported_command': 'This command is not supported.',
  'unsupported_proposal': 'Only inspection notes proposals are supported.',
  'internal_error':
      'The local command could not be completed. Saved data was retained.',
};

class AgentFailure implements Exception {
  const AgentFailure(this.code);
  final String code;
}

/// A deterministic read refusal, using the existing v1 error code.
class AgentCapacityFailure extends AgentFailure {
  const AgentCapacityFailure() : super('internal_error');
}

const agentCapacityMessage =
    'This local record is too large for version 1. Read fewer records or review it in the maintenance app.';
