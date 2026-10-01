import assert from 'node:assert/strict';
import {readFile, lstat, realpath} from 'node:fs/promises';
import {dirname, basename} from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {execute} from '../client.mjs';
import {socketTransport} from '../transport.mjs';
import {CliError} from '../contract.mjs';

// Opt-in acceptance against the actual native service's guarded SYNTHETIC
// fixture only. No normal workspace discovery, service launch or real grant.
const opts = new Map();
for (let i = 2; i < process.argv.length; i += 2) {
  const key = process.argv[i];
  assert(['--ready', '--socket'].includes(key) && !opts.has(key));
  opts.set(key, process.argv[i + 1]);
}
assert.equal(opts.size, 2);
const readyPath = opts.get('--ready'), socketPath = opts.get('--socket');
assert(readyPath?.startsWith('/') && socketPath?.startsWith('/'));
assert.equal(dirname(readyPath), dirname(socketPath));
assert(basename(dirname(readyPath)).startsWith('vortice-cli-e2e-'));
assert.equal(await realpath(dirname(readyPath)), dirname(readyPath));
const stat = await lstat(readyPath);
assert(stat.isFile() && !stat.isSymbolicLink() && stat.uid === process.getuid() && (stat.mode & 0o777) === 0o600 && stat.size < 65536);
const fixture = JSON.parse(await readFile(readyPath, 'utf8'));
assert.equal(fixture.synthetic_fixture, true);
assert.equal(fixture.workspace_id, 'synthetic-agent-workspace');
assert.equal(fixture.protocol_version, 1);
const scope = {workspace_id: fixture.workspace_id, company_id: fixture.company_id, device_id: fixture.device_id};
const options = {token: 'synthetic-agent-token', socketPath, transport: socketTransport};
let checks = 0;
async function call(command, args = {}, altered = {}) {
  return execute({scope, command, args, ...altered}, options);
}
function success(reply) { assert.equal(reply.ok, true, 'Expected a verified service success.'); checks++; return reply.result; }
function failure(reply, code) { assert.equal(reply.ok, false); assert.equal(reply.error.code, code); checks++; }
const caps = success(await call('capabilities'));
assert(caps.commands.includes('proposals.create') && caps.proposal_types.includes('inspection.notes'));
const status = success(await call('workspace.status'));
assert.equal(status.proposal_human_review_available, false);
assert.equal(status.proposals_backup_included, false);
const binary = spawnSync(process.execPath, [fileURLToPath(new URL('../cli.mjs', import.meta.url)),
  'work', 'list', '--socket', socketPath, '--workspace', scope.workspace_id,
  '--company', scope.company_id, '--device', scope.device_id, '--limit', '1'],
  {env: {VORTICE_LOCAL_AGENT_TOKEN: options.token}, encoding: 'utf8', timeout: 10000, maxBuffer: 1024 * 1024});
assert.equal(binary.status, 0);
assert.equal(binary.stderr, '');
const binaryResult = success(JSON.parse(binary.stdout));
assert.equal(binaryResult.count, 1);
const equipment = success(await call('equipment.list', {limit: 1}));
assert.equal(equipment.items.length, 1);
assert(equipment.next_cursor);
const secondEquipment = success(await call('equipment.list', {limit: 1, cursor: equipment.next_cursor}));
assert.notEqual(equipment.items[0].id, secondEquipment.items[0].id);
success(await call('equipment.show', {equipment_id: fixture.equipment_ids[0]}));
success(await call('procedures.list', {limit: 25}));
success(await call('procedures.show', {procedure_id: fixture.procedure_ids[0]}));
success(await call('work.list', {limit: 25}));
const job = success(await call('work.show', {job_id: fixture.job_ids[0]})).item;
success(await call('history.list', {job_id: fixture.job_ids[0], limit: 25}));
failure(await call('work.show', {job_id: fixture.job_ids[0]}, {scope: {...scope, company_id: 'different-company'}}), 'scope_mismatch');
failure(await call('equipment.show', {equipment_id: 'missing-record'}), 'not_found');
failure(await execute({scope, command: 'work.list', args: {}}, {...options, token: 'synthetic-invalid-token'}), 'unauthorized');
const args = {type: 'inspection.notes', job_id: job.job_id, expected_document_hash: job.draft.document_hash,
  notes: 'Synthetic agent proposes inspecting the recorded guard finding.', idempotency_key: '11111111-1111-4111-8111-111111111111'};
let committed;
const interrupted = await execute({scope, command: 'proposals.create', args}, {...options,
  transport: async request => {
    committed = success(await Promise.resolve(socketTransport(request)));
    throw new CliError('service_unavailable', {retryable: true, outcome: 'unknown'});
  }});
failure(interrupted, 'service_unavailable');
assert.equal(interrupted.error.outcome, 'unknown');
assert.equal(interrupted.error.idempotency_key, args.idempotency_key);
const replay = success(await call('proposals.create', args));
assert.equal(replay.item.proposal_id, committed.item.proposal_id);
assert.equal(replay.item.applied, false);
assert.equal(replay.item.status, 'pending_human_review');
failure(await call('proposals.create', {...args, notes: 'Different intent under same key'}), 'idempotency_conflict');
success(await call('proposals.show', {proposal_id: replay.item.proposal_id}));
const proposals = success(await call('proposals.list', {limit: 25}));
assert.equal(proposals.items.length, 1);
const unchanged = success(await call('work.show', {job_id: fixture.job_ids[0]})).item;
assert.equal(unchanged.draft.document_hash, job.draft.document_hash);
assert.deepEqual(unchanged.known_history, job.known_history);
process.stdout.write(`${JSON.stringify({synthetic_fixture: true, protocol_version: 1, ok: true, checks,
  proves: ['native-service scoped reads', 'Unix JSONL client IO', 'pending-only proposal', 'exact retry after lost response', 'unchanged inspection'],
  excludes: ['real grant provisioning', 'human proposal application', 'proposal backup/replication', 'live workspace', 'physical acceptance']})}\n`);
