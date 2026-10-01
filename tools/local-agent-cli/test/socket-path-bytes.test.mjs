import assert from 'node:assert/strict';
import test from 'node:test';
import {execute} from '../client.mjs';
import {run} from '../cli.mjs';
import {CliError, MAX_SOCKET_PATH_BYTES, validateSocketPath} from '../contract.mjs';

const token = 'synthetic-path-test-capability';
const scope = {workspace_id: 'workspace_a', company_id: 'company_a', device_id: 'device_a'};
const intent = {command: 'capabilities', scope, args: {}};
const flags = socketPath => ['--socket', socketPath, '--workspace', scope.workspace_id,
  '--company', scope.company_id, '--device', scope.device_id];
const reply = request => ({protocol_version: 1, request_id: request.request_id, scope: {...scope}, ok: true,
  result: {commands: ['capabilities'], proposal_types: []},
  meta: {source: 'local', freshness: 'local_snapshot', observed_at: '2026-10-01T00:00:00.000Z',
    local_revision: 'a'.repeat(64), complete: true, synced: {verified: false, reason: 'no_fresh_transfer_proof'}}});

for (const [name, socketPath] of [
  ['ASCII exactly 100 bytes', `/${'x'.repeat(99)}`],
  ['two-byte Unicode exactly 100 bytes', `/${'é'.repeat(49)}s`],
  ['four-byte Unicode exactly 100 bytes', `/${'🚢'.repeat(24)}abc`],
]) {
  test(`${name} remains accepted by direct client and CLI`, async () => {
    assert.equal(Buffer.byteLength(socketPath, 'utf8'), MAX_SOCKET_PATH_BYTES);
    assert.doesNotThrow(() => validateSocketPath(socketPath));
    let calls = 0;
    const transport = async ({request, token: receivedToken, socketPath: receivedPath}) => {
      calls++;
      assert.equal(receivedToken, token);
      assert.equal(receivedPath, socketPath);
      return reply(request);
    };
    assert.equal((await execute(intent, {token, socketPath, transport})).ok, true);
    assert.equal((await run(['capabilities', ...flags(socketPath)],
      {env: {VORTICE_LOCAL_AGENT_TOKEN: token}, transport})).ok, true);
    assert.equal(calls, 2);
  });
}

for (const [name, socketPath] of [
  ['ASCII 101 bytes', `/${'x'.repeat(100)}`],
  ['two-byte Unicode 101 bytes', `/${'é'.repeat(50)}`],
  ['four-byte Unicode 101 bytes', `/${'🚢'.repeat(25)}`],
  ['relative path', 'synthetic.sock'],
  ['network address', 'https://example.invalid/synthetic.sock'],
  ['embedded NUL', '/tmp/synthetic\0.sock'],
  ['empty path', ''],
]) {
  test(`${name} is rejected before transport receives a capability or stdin is read`, async () => {
    assert.throws(() => validateSocketPath(socketPath), error => error instanceof CliError && error.code === 'invalid_input');
    let calls = 0, reads = 0;
    const transport = async () => {calls++; throw new Error('No capability may reach this transport.');};
    const stdin = {[Symbol.asyncIterator]() {reads++; throw new Error('No proposal stdin may be consumed.');}};
    const direct = await execute(intent, {token, socketPath, transport});
    const cli = await run(['capabilities', ...flags(socketPath)], {env: {VORTICE_LOCAL_AGENT_TOKEN: token}, transport});
    const proposal = await run(['proposals', 'create', ...flags(socketPath), '--input', '-',
      '--operation', '11111111-1111-4111-8111-111111111111'], {env: {VORTICE_LOCAL_AGENT_TOKEN: token}, transport, stdin});
    for (const result of [direct, cli, proposal]) {
      assert.equal(result.error.code, 'invalid_input');
      assert.equal(result.error.outcome, 'not_sent');
      assert.equal(JSON.stringify(result).includes(token), false);
      if (socketPath) assert.equal(JSON.stringify(result).includes(socketPath), false);
    }
    assert.equal(calls, 0);
    assert.equal(reads, 0);
  });
}

test('non-string direct socket paths fail closed before transport', async () => {
  for (const socketPath of [undefined, null, 100, true, {}, [], Symbol('synthetic')]) {
    let calls = 0;
    const result = await execute(intent, {token, socketPath, transport: async () => {calls++;}});
    assert.equal(result.error.code, 'invalid_input');
    assert.equal(result.error.outcome, 'not_sent');
    assert.equal(calls, 0);
  }
});
