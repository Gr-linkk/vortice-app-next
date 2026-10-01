import assert from 'node:assert/strict';
import {chmod, lstat, readFile, realpath, writeFile} from 'node:fs/promises';
import net from 'node:net';
import {basename, dirname, isAbsolute, join} from 'node:path';
import {executeFile, operation} from './harness.mjs';

// Opt-in actual native-service acceptance. Every client operation is an
// extracted bin/vortice-agent subprocess; original client modules are never
// imported or used as a transport. The guarded fresh fixture is caller-owned.
const options = new Map();
for (let i = 2; i < process.argv.length; i += 2) {
  const flag = process.argv[i], value = process.argv[i + 1];
  assert(['--launcher', '--ready', '--socket'].includes(flag) && !options.has(flag));
  assert(typeof value === 'string' && isAbsolute(value)); options.set(flag, value);
}
assert.equal(options.size, 3);
const launcher = options.get('--launcher'), ready = options.get('--ready'), socketPath = options.get('--socket');
const root = dirname(ready);
assert.equal(root, dirname(socketPath));
assert(basename(root).startsWith('vortice-cli-dist-e2e-'));
assert.equal(await realpath(root), root);
const parentStat = await lstat(root), readyStat = await lstat(ready);
assert(parentStat.isDirectory() && parentStat.uid === process.getuid() && (parentStat.mode & 0o7777) === 0o700);
assert(readyStat.isFile() && !readyStat.isSymbolicLink() && readyStat.nlink === 1 &&
  readyStat.uid === process.getuid() && (readyStat.mode & 0o7777) === 0o600 && readyStat.size < 65536);
const fixture = JSON.parse(await readFile(ready, 'utf8'));
assert.equal(fixture.synthetic_fixture, true);
assert.equal(fixture.workspace_id, 'synthetic-agent-workspace');
assert.equal(fixture.protocol_version, 1);
assert.equal(basename(launcher), 'vortice-agent');
const scope = {workspace_id: fixture.workspace_id, company_id: fixture.company_id, device_id: fixture.device_id};
const credential = 'synthetic-agent-token'; // Public fixture credential, never an issuer.
const connection = join(root, 'connection.json');
await writeFile(connection, JSON.stringify({protocol_version: 1, socket_path: socketPath,
  scope, token_environment: 'VORTICE_LOCAL_AGENT_TOKEN'}), {mode: 0o600});
await chmod(connection, 0o600);
let checks = 0, cliCalls = 0;
function check(actual, expected) {assert.deepEqual(actual, expected); checks++;}
async function call(words, flags = [], {settings = connection, input = '', token = credential} = {}) {
  cliCalls++;
  const process = await executeFile(launcher, [...words, '--connection', settings, ...flags],
    {cwd: root, input, env: {VORTICE_LOCAL_AGENT_TOKEN: token}});
  check(process.stderr, '');
  check(process.stdout.includes(credential), false);
  const response = JSON.parse(process.stdout);
  return {response, process};
}
async function success(words, flags = [], options = {}) {
  const result = await call(words, flags, options);
  check(result.process.status, 0); check(result.response.ok, true);
  return result.response.result;
}
async function failure(words, flags, code, outcome, options = {}) {
  const result = await call(words, flags, options);
  check(result.response.ok, false); check(result.response.error.code, code);
  check(result.response.error.outcome, outcome);
  check(result.process.status, outcome === 'unknown' ? 3 : 1);
  return result.response;
}
const capabilities = await success(['capabilities']);
check(capabilities.commands.includes('proposals.create'), true);
check(capabilities.proposal_types.includes('inspection.notes'), true);
const beforeStatus = await success(['workspace', 'status']);
check(beforeStatus.proposals_backup_included, false);
check(beforeStatus.proposal_human_review_available, false);
const equipment = await success(['equipment', 'list'], ['--limit', '1']);
check(equipment.count, 1);
check(typeof equipment.next_cursor, 'string');
const next = await success(['equipment', 'list'], ['--limit', '1', '--cursor', equipment.next_cursor]);
check(next.items[0].id !== equipment.items[0].id, true);
await success(['equipment', 'show'], ['--id', fixture.equipment_ids[0]]);
await success(['procedures', 'list']);
await success(['procedures', 'show'], ['--id', fixture.procedure_ids[0]]);
await success(['work', 'list']);
const job = (await success(['work', 'show'], ['--id', fixture.job_ids[0]])).item;
await success(['history', 'list'], ['--job', job.job_id]);
await failure(['equipment', 'show'], ['--id', 'missing-record'], 'not_found', 'rejected');
await failure(['work', 'list'], [], 'unauthorized', 'not_sent', {token: 'synthetic-invalid-token'});

const proposed = {type: 'inspection.notes', job_id: job.job_id,
  expected_document_hash: job.draft.document_hash,
  notes: 'Packaged CLI synthetic proposal 空间 café remains pending.'};
const proposalFlags = ['--operation', operation, '--input', '-'];
let committed, dispatches = 0, drop = true;
const clients = new Set(), proxyPath = join(root, 'lost.sock');
const proxy = net.createServer(front => {
  clients.add(front); front.once('close', () => clients.delete(front)); front.on('error', () => {});
  let requestBytes = Buffer.alloc(0);
  front.on('data', chunk => {
    requestBytes = Buffer.concat([requestBytes, chunk]);
    if (!requestBytes.includes(10)) return;
    front.removeAllListeners('data');
    const request = JSON.parse(requestBytes.subarray(0, requestBytes.indexOf(10)).toString('utf8'));
    const backend = net.createConnection(socketPath);
    clients.add(backend); backend.once('close', () => clients.delete(backend));
    backend.on('error', () => front.destroy());
    backend.once('connect', () => backend.write(requestBytes));
    let replyBytes = Buffer.alloc(0);
    backend.on('data', data => {
      replyBytes = Buffer.concat([replyBytes, data]);
      if (!replyBytes.includes(10)) return;
      const reply = JSON.parse(replyBytes.subarray(0, replyBytes.indexOf(10)).toString('utf8'));
      if (request.command === 'proposals.create') {
        dispatches++;
        if (drop) {drop = false; committed = reply; front.destroy(); backend.destroy(); return;}
      }
      front.end(replyBytes); backend.destroy();
    });
  });
});
try {
  await new Promise((resolve, reject) => {proxy.once('error', reject); proxy.listen(proxyPath, resolve);});
  await chmod(proxyPath, 0o600);
  const lostConnection = join(root, 'lost-connection.json');
  await writeFile(lostConnection, JSON.stringify({protocol_version: 1, socket_path: proxyPath,
    scope, token_environment: 'VORTICE_LOCAL_AGENT_TOKEN'}), {mode: 0o600});
  await chmod(lostConnection, 0o600);
  const lost = await failure(['proposals', 'create'], proposalFlags, 'service_unavailable', 'unknown',
    {settings: lostConnection, input: JSON.stringify(proposed)});
  check(lost.error.idempotency_key, operation);
  check(dispatches, 1); check(committed.ok, true);
  check(committed.result.item.applied, false);
  const replay = await success(['proposals', 'create'], proposalFlags, {input: JSON.stringify(proposed)});
  check(replay.item, committed.result.item);
  check(replay.item.status, 'pending_human_review');
  check(dispatches, 1); // Explicit retry used the actual endpoint, never auto-retried through proxy.
  await failure(['proposals', 'create'], proposalFlags, 'idempotency_conflict', 'rejected',
    {input: JSON.stringify({...proposed, notes: 'Different intent under the same operation'})});
  await success(['proposals', 'show'], ['--id', replay.item.proposal_id]);
  const proposals = await success(['proposals', 'list']); check(proposals.items.length, 1);
  const unchanged = (await success(['work', 'show'], ['--id', job.job_id])).item;
  check(unchanged.draft.document_hash, job.draft.document_hash);
  check(unchanged.known_history, job.known_history);
  check(proposals.items[0].applied, false);
} finally {
  for (const client of clients) client.destroy();
  await new Promise(resolve => proxy.close(resolve));
}
process.stdout.write(`${JSON.stringify({synthetic_fixture: true, protocol_version: 1, ok: true,
  checks, cli_calls: cliCalls, packaged_cli_only: true, dropped_proposal_replies: 1,
  automatic_proposal_retries: 0, inspection_hash_unchanged: true, inspection_history_unchanged: true,
  runtime: process.version, excludes: ['real grants', 'ordinary workspaces', 'device or production acceptance']})}\n`);
