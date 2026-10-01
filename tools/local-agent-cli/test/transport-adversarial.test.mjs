import assert from 'node:assert/strict';
import net from 'node:net';
import {chmod, mkdtemp, rm, symlink, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import test from 'node:test';
import {execute} from '../client.mjs';
import {MAX_BYTES} from '../contract.mjs';
import {socketTransport} from '../transport.mjs';

// Ephemeral Unix-socket protocol fixtures only: no running application, real
// workspace, grant, enrollment credential, or shared service is accessed.
const token = 'synthetic-transport-capability-not-a-real-secret';
const scope = {workspace_id: 'workspace_a', company_id: 'company_a', device_id: 'device_a'};
const idempotency_key = '11111111-1111-4111-8111-111111111111';
const intent = {scope, command: 'proposals.create', args: {idempotency_key,
  type: 'inspection.notes', job_id: 'job_a', expected_document_hash: 'a'.repeat(64), notes: 'Synthetic proposal'}};
const reply = request => ({protocol_version: 1, request_id: request.request_id, scope: request.scope, ok: true,
  result: {item: {proposal_id: 'proposal_a', ...request.args,
    status: 'pending_human_review', requires_human_review: true, applied: false}},
  meta: {source: 'local', freshness: 'local_snapshot', observed_at: '2026-10-01T00:00:00.000Z',
    local_revision: '1'.repeat(64), complete: true, synced: {verified: false, reason: 'no_fresh_transfer_proof'}}});

async function fixture(t, handler, {onConnect} = {}) {
  const directory = await mkdtemp(join(tmpdir(), 'vortice-cli-contract-'));
  await chmod(directory, 0o700);
  const socketPath = join(directory, 's.sock');
  const connections = new Set();
  const server = net.createServer(socket => {
    onConnect?.(socket);
    connections.add(socket); socket.on('close', () => connections.delete(socket));
    let data = '';
    socket.on('data', chunk => {
      data += chunk.toString('utf8');
      if (!data.includes('\n')) return;
      const request = JSON.parse(data.slice(0, data.indexOf('\n')));
      socket.removeAllListeners('data');
      handler(socket, request);
    });
  });
  t.after(async () => {
    for (const socket of connections) socket.destroy();
    await new Promise(resolve => server.close(resolve));
    await rm(directory, {recursive: true, force: true});
  });
  await new Promise((resolve, reject) => {server.once('error', reject); server.listen(socketPath, resolve);});
  await chmod(socketPath, 0o600);
  return socketPath;
}
const call = socketPath => execute(intent, {socketPath, token, transport: socketTransport});

test('Unix JSONL transport sends one scoped request with exact retry identity', async t => {
  let captured;
  const socketPath = await fixture(t, (socket, request) => {
    captured = request; socket.end(`${JSON.stringify(reply(request))}\n`);
  });
  const result = await call(socketPath);
  assert.equal(result.ok, true);
  assert.deepEqual(captured.credential, {token});
  assert.deepEqual(captured.scope, scope);
  assert.deepEqual(captured.args, intent.args);
  assert.equal(captured.args.idempotency_key, idempotency_key);
  assert.equal(JSON.stringify(result).includes(token), false);
});

test('transport rejects invalid JSON, extra frames and oversized responses', async t => {
  const scenarios = [
    ['invalid JSON', () => '{\n'],
    ['extra frame', request => `${JSON.stringify(reply(request))}\n${JSON.stringify(reply(request))}\n`],
    ['trailing bytes', request => `${JSON.stringify(reply(request))}\n${token}`],
    ['oversized', () => `${'x'.repeat(MAX_BYTES + 1)}\n`],
  ];
  for (const [name, value] of scenarios) await t.test(name, async t => {
    let calls = 0;
    const socketPath = await fixture(t, (socket, request) => {calls++; socket.end(value(request));});
    const result = await call(socketPath);
    assert.equal(result.error.code, 'invalid_response');
    assert.equal(result.error.outcome, 'unknown');
    assert.equal(result.error.idempotency_key, idempotency_key);
    assert.equal(calls, 1);
    assert.equal(JSON.stringify(result).includes(token), false);
  });
});

test('chunked UTF-8 response remains one valid frame', async t => {
  const withUnicode = {...intent, args: {...intent.args, notes: 'Synthetic café 🔧'}};
  const socketPath = await fixture(t, (socket, request) => {
    const data = Buffer.from(`${JSON.stringify(reply(request))}\n`);
    const split = data.indexOf(Buffer.from('🔧')) + 1;
    socket.write(data.subarray(0, split));
    setImmediate(() => socket.end(data.subarray(split)));
  });
  const result = await execute(withUnicode, {socketPath, token, transport: socketTransport});
  assert.equal(result.ok, true);
  assert.equal(result.result.item.notes, withUnicode.args.notes);
});

test('invalid UTF-8 cannot be silently replaced inside a JSON response', async t => {
  const socketPath = await fixture(t, socket => socket.end(Buffer.concat([
    Buffer.from('{"value":"'), Buffer.from([0xff]), Buffer.from('"}\n'),
  ])));
  await assert.rejects(socketTransport({socketPath, token, request: {}}),
    error => error.code === 'invalid_response' && error.outcome === 'unknown');
});

test('insecure or substituted endpoints reject before connecting or sending credentials', async t => {
  const scenarios = [
    ['readable parent', async path => {await chmod(dirname(path), 0o755); return path;}],
    ['readable socket', async path => {await chmod(path, 0o666); return path;}],
    ['endpoint symlink', async path => {
      const alias = join(dirname(path), 'alias.sock'); await symlink(path, alias); return alias;
    }],
    ['parent symlink', async path => {
      const aliasDirectory = await mkdtemp(join(tmpdir(), 'vortice-cli-alias-'));
      t.after(() => rm(aliasDirectory, {recursive: true, force: true}));
      const alias = join(aliasDirectory, 'linked'); await symlink(dirname(path), alias); return join(alias, 's.sock');
    }],
    ['ordinary file', async path => {
      const file = join(dirname(path), 'not-a-socket'); await writeFile(file, '', {mode: 0o600}); return file;
    }],
  ];
  for (const [name, alter] of scenarios) await t.test(name, async t => {
    let connections = 0, receivedBytes = 0;
    const path = await fixture(t, socket => socket.destroy(), {onConnect: socket => {
      connections++; socket.on('data', chunk => receivedBytes += chunk.length);
    }});
    const socketPath = await alter(path);
    const result = await call(socketPath);
    assert.equal(result.error.code, 'service_unavailable');
    assert.equal(result.error.outcome, 'not_sent');
    assert.equal(result.error.idempotency_key, idempotency_key);
    assert.equal(connections, 0);
    assert.equal(receivedBytes, 0);
    assert.equal(JSON.stringify(result).includes(token), false);
    assert.equal(JSON.stringify(result).includes(socketPath), false);
  });
});

test('interrupted response after synthetic acceptance causes no automatic write retry', async t => {
  let accepted = 0;
  const socketPath = await fixture(t, socket => {
    accepted++; socket.end('{"protocol_version":1');
  });
  const result = await call(socketPath);
  assert.equal(result.error.code, 'service_unavailable');
  assert.equal(result.error.outcome, 'unknown');
  assert.equal(result.error.idempotency_key, idempotency_key);
  assert.equal(accepted, 1);
});

test('timeout reports unknown write outcome without diagnostics or retries', async t => {
  let accepted = 0;
  const socketPath = await fixture(t, () => {accepted++;});
  const result = await execute(intent, {socketPath, token,
    transport: args => socketTransport({...args, timeoutMs: 30})});
  assert.equal(result.error.code, 'service_unavailable');
  assert.equal(result.error.outcome, 'unknown');
  assert.equal(result.error.idempotency_key, idempotency_key);
  assert.equal(accepted, 1);
  assert.equal(JSON.stringify(result).includes(socketPath), false);
  assert.equal(JSON.stringify(result).includes(token), false);
});

test('missing service fails safely without disclosing the socket path', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'vortice-cli-absent-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  const socketPath = join(directory, 'missing.sock');
  const result = await call(socketPath);
  assert.equal(result.error.code, 'service_unavailable');
  assert.equal(result.error.outcome, 'not_sent');
  assert.equal(result.error.idempotency_key, idempotency_key);
  assert.equal(JSON.stringify(result).includes(socketPath), false);
});
