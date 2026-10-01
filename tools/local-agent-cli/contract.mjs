export const PROTOCOL_VERSION = 1;
export const MAX_BYTES = 1024 * 1024;
export const MAX_SOCKET_PATH_BYTES = 100;
const ID = /^[a-zA-Z0-9_-]{1,100}$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const scopeKeys = ['workspace_id', 'company_id', 'device_id'];
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
export class CliError extends Error {
  constructor(code, {retryable = false, outcome = 'not_sent'} = {}) {
    super(code); this.code = code; this.retryable = retryable; this.outcome = outcome;
  }
}
export const messages = Object.freeze({
  invalid_input: 'Invalid command input. Run help for the command schema.',
  unauthorized: 'The agent capability was not accepted.',
  scope_mismatch: 'The agent capability does not match this workspace, company and device.',
  invalid_request: 'The service rejected the request format.',
  unsupported_version: 'The service does not support this protocol version.',
  unsupported_proposal: 'The service does not support this proposal type.',
  auth_required: 'An explicit agent capability is required.',
  permission_denied: 'This agent scope does not allow the requested action.',
  grant_expired: 'This agent scope has expired.',
  grant_revoked: 'This agent scope has been revoked.',
  not_found: 'The requested record is not available in this scope.',
  idempotency_conflict: 'This operation ID was already used with different input.',
  stale_context: 'The referenced record changed. Read it before proposing again.',
  unsupported_command: 'The service does not support this command.',
  service_unavailable: 'The local agent service is unavailable.',
  invalid_response: 'The service response could not be verified.',
  internal_error: 'The command could not be completed.',
});
function requireInput(condition) { if (!condition) throw new CliError('invalid_input'); }
export function validateSocketPath(socketPath) {
  requireInput(typeof socketPath === 'string' && socketPath.startsWith('/') && !socketPath.includes('\0') &&
    Buffer.byteLength(socketPath, 'utf8') <= MAX_SOCKET_PATH_BYTES);
}
function shape(value, required, allowed = required) {
  requireInput(object(value) && required.every(k => Object.hasOwn(value, k)) &&
    Object.keys(value).every(k => allowed.includes(k)));
}
export function validateScope(scope) {
  shape(scope, scopeKeys);
  requireInput(scopeKeys.every(k => typeof scope[k] === 'string' && ID.test(scope[k])));
}
export const COMMANDS = Object.freeze({
  'capabilities': {kind: 'read', args: 'none'},
  'workspace.status': {kind: 'read', args: 'none'},
  'equipment.list': {kind: 'read', args: 'list'},
  'equipment.show': {kind: 'read', args: 'id', idKey: 'equipment_id'},
  'procedures.list': {kind: 'read', args: 'list'},
  'procedures.show': {kind: 'read', args: 'id', idKey: 'procedure_id'},
  'work.list': {kind: 'read', args: 'list'},
  'work.show': {kind: 'read', args: 'id', idKey: 'job_id'},
  'history.list': {kind: 'read', args: 'list'},
  'proposals.list': {kind: 'read', args: 'list'},
  'proposals.show': {kind: 'read', args: 'id', idKey: 'proposal_id'},
  'proposals.create': {kind: 'proposal', args: 'proposal'},
});
export function validateIntent(intent) {
  shape(intent, ['scope', 'command', 'args']);
  validateScope(intent.scope);
  requireInput(typeof intent.command === 'string' && Object.hasOwn(COMMANDS, intent.command));
  const def = COMMANDS[intent.command];
  const a = intent.args;
  if (def.args === 'none') shape(a, []);
  if (def.args === 'id') { shape(a, [def.idKey]); requireInput(typeof a[def.idKey] === 'string' && ID.test(a[def.idKey])); }
  if (def.args === 'list') {
    shape(a, [], ['job_id', 'equipment_id', 'limit', 'cursor']);
    for (const key of ['job_id', 'equipment_id']) if (a[key] !== undefined) {
      requireInput(typeof a[key] === 'string' && ID.test(a[key]));
    }
    if (a.limit !== undefined) requireInput(Number.isInteger(a.limit) && a.limit >= 1 && a.limit <= 100);
    if (a.cursor !== undefined) requireInput(typeof a.cursor === 'string' && a.cursor.length > 0 && a.cursor.length <= 4096);
  }
  if (def.args === 'proposal') {
    shape(a, ['type', 'job_id', 'expected_document_hash', 'notes', 'idempotency_key']);
    requireInput(a.type === 'inspection.notes' && typeof a.job_id === 'string' && ID.test(a.job_id) &&
      typeof a.expected_document_hash === 'string' && /^[0-9a-f]{64}$/.test(a.expected_document_hash) &&
      typeof a.notes === 'string' && a.notes.trim().length > 0 && a.notes.length <= 10000 &&
      typeof a.idempotency_key === 'string' && UUID.test(a.idempotency_key));
  }
  requireInput(Buffer.byteLength(JSON.stringify(intent)) <= 64 * 1024 - 1);
  return def;
}
export function safeError(error, request_id = null, idempotency_key = undefined) {
  const known = error instanceof CliError && Object.hasOwn(messages, error.code);
  const code = known ? error.code : 'internal_error';
  return {protocol_version: PROTOCOL_VERSION, request_id, ok: false, error: {
    code, message: messages[code], retryable: known && error.retryable,
    outcome: known ? error.outcome : 'unknown', ...(idempotency_key ? {idempotency_key} : {}),
  }};
}
function date(value) { return typeof value === 'string' && /^\d{4}-\d\d-\d\dT/.test(value) && Number.isFinite(Date.parse(value)); }
function resultValid(result, request, meta) {
  if (!object(result)) return false;
  const forbidden = new Set(['credential', 'token', 'privatekey', 'certificate', 'secret', 'authorization',
    'databasepath', 'socketpath', 'photopath', 'evidencepaths', 'rawdocument', 'document', 'backup']);
  function safe(value, depth = 0) {
    if (depth > 64) return false;
    if (Array.isArray(value)) return value.every(v => safe(v, depth + 1));
    if (!object(value)) return true;
    return Object.entries(value).every(([key, v]) => {
      const name = key.replaceAll('_', '').toLowerCase();
      if (key.startsWith('_') || forbidden.has(name)) return false;
      if (name === 'companyid' && v !== request.scope.company_id) return false;
      if (name === 'workspaceid' && v !== request.scope.workspace_id) return false;
      return safe(v, depth + 1);
    });
  }
  if (!safe(result)) return false;
  const cmd = request.command;
  if (cmd === 'capabilities') return Object.keys(result).every(k => ['commands', 'proposal_types'].includes(k)) &&
    Array.isArray(result.commands) && result.commands.every(c => Object.hasOwn(COMMANDS, c)) &&
    Array.isArray(result.proposal_types) && result.proposal_types.every(t => t === 'inspection.notes');
  if (cmd === 'workspace.status') return object(result.scope) && scopeKeys.every(k => result.scope[k] === request.scope[k]) &&
    ['local_work_count', 'local_equipment_count', 'known_version_count', 'pending_proposal_count'].every(k =>
      Number.isInteger(result[k]) && result[k] >= 0) &&
    result.proposals_local_only === true && result.proposals_backup_included === false &&
    result.proposal_human_review_available === false && result.known_decisions_are_historical === true;
  const idKey = cmd.startsWith('equipment.') || cmd.startsWith('procedures.') ? 'id' :
    cmd.startsWith('work.') ? 'job_id' : cmd.startsWith('history.') ? 'submission_id' : 'proposal_id';
  function itemValid(item) {
    if (!object(item) || typeof item[idKey] !== 'string' || !ID.test(item[idKey])) return false;
    if (cmd.startsWith('proposals.')) return item.type === 'inspection.notes' && item.status === 'pending_human_review' &&
      item.requires_human_review === true && item.applied === false &&
      ['review', 'approved', 'published', 'signed', 'synced'].every(k => !Object.hasOwn(item, k));
    return true;
  }
  if (cmd.endsWith('.list')) return Object.keys(result).every(k => ['items', 'count', 'next_cursor'].includes(k)) &&
    Array.isArray(result.items) && result.items.length <= (request.args.limit ?? 25) && result.items.every(itemValid) &&
    Number.isInteger(result.count) && result.count === result.items.length &&
    (result.next_cursor === null || typeof result.next_cursor === 'string' && result.next_cursor.length > 0 && result.next_cursor.length <= 4096) &&
    meta.complete === (result.next_cursor === null);
  if (!Object.keys(result).every(k => k === 'item') || !itemValid(result.item)) return false;
  if (cmd.endsWith('.show')) return result.item[idKey] === request.args[COMMANDS[cmd].idKey];
  return true;
}
export function validateResponse(value, request) {
  const invalid = () => { throw new CliError('invalid_response', {outcome: 'unknown', retryable: true}); };
  if (!object(value) || value.protocol_version !== PROTOCOL_VERSION || value.request_id !== request.request_id ||
      !object(value.scope) || Object.keys(value.scope).length !== scopeKeys.length ||
      !scopeKeys.every(k => value.scope[k] === request.scope[k]) || typeof value.ok !== 'boolean') invalid();
  if (!value.ok) {
    const e = value.error;
    if (!object(e) || !Object.hasOwn(messages, e.code) || typeof e.retryable !== 'boolean' ||
        !['rejected', 'unknown'].includes(e.outcome)) invalid();
    throw new CliError(e.code, {retryable: e.retryable, outcome: e.outcome});
  }
  const m = value.meta;
  if (!Object.hasOwn(value, 'result') || !object(m) || m.source !== 'local' ||
      m.freshness !== 'local_snapshot' || !date(m.observed_at) ||
      typeof m.local_revision !== 'string' || !/^[0-9a-f]{64}$/.test(m.local_revision) || typeof m.complete !== 'boolean' ||
      !object(m.synced) || m.synced.verified !== false ||
      m.synced.reason !== 'no_fresh_transfer_proof') invalid();
  if (!resultValid(value.result, request, m)) invalid();
  if (request.command === 'proposals.create') {
    const item = value.result?.item;
    if (!object(item) || item.idempotency_key !== request.args.idempotency_key ||
        item.status !== 'pending_human_review' || item.requires_human_review !== true || item.applied !== false ||
        typeof item.proposal_id !== 'string' || !ID.test(item.proposal_id) ||
        item.type !== request.args.type || item.job_id !== request.args.job_id ||
        item.expected_document_hash !== request.args.expected_document_hash || item.notes !== request.args.notes ||
        ['review', 'approved', 'published', 'signed', 'synced'].some(k => Object.hasOwn(item, k))) invalid();
  }
  return {protocol_version: value.protocol_version, request_id: value.request_id, ok: true,
    scope: {...value.scope}, result: value.result, meta: {
      source: m.source, freshness: m.freshness, observed_at: m.observed_at,
      local_revision: m.local_revision, complete: m.complete,
      synced: {verified: false, reason: m.synced.reason},
    }};
}
