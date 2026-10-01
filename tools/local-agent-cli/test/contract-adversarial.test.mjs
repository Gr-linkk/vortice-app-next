import assert from 'node:assert/strict';
import {Readable} from 'node:stream';
import test from 'node:test';
import {execute} from '../client.mjs';
import {run} from '../cli.mjs';
import {CliError} from '../contract.mjs';

// Synthetic protocol fixtures only. These do not demonstrate authorization,
// atomicity, or domain behavior in the real shared service.
const token = 'synthetic-agent-capability-not-a-real-secret';
const socketPath = '/tmp/synthetic-vortice-agent.sock';
const scope = {workspace_id: 'workspace_a', company_id: 'company_a', device_id: 'device_a'};
const idempotency_key = '11111111-1111-4111-8111-111111111111';
const meta = {source: 'local', freshness: 'local_snapshot', observed_at: '2026-10-01T00:00:00.000Z',
  local_revision: '7'.repeat(64), complete: true, synced: {verified: false, reason: 'no_fresh_transfer_proof'}};
const readIntent = (command = 'equipment.list', args = {}) =>
  ({scope: {...scope}, command, args: args});
const proposalIntent = (changes = {}) => ({scope: {...scope}, command: 'proposals.create',
  args: {type: 'inspection.notes', job_id: 'job_a', expected_document_hash: 'a'.repeat(64),
    notes: 'Suggested synthetic inspection notes', idempotency_key, ...changes}});
const reply = (request, data = {items: [], count: 0, next_cursor: null}) => ({protocol_version: 1, request_id: request.request_id,
  scope: {...request.scope}, ok: true, result: data, meta: structuredClone(meta)});
const rejection = (request, code) => ({protocol_version: 1, request_id: request.request_id,
  scope: {...request.scope}, ok: false, error: {code, message: `unsafe ${token}`,
    retryable: false, outcome: 'rejected', debug: {token}}});
const pending = request => ({item: {proposal_id: 'proposal_a', ...request.args,
  status: 'pending_human_review', requires_human_review: true, applied: false, created_at: '2026-10-01T00:00:00.000Z'}});
const proposalBody = () => {const {idempotency_key, ...body} = proposalIntent().args; return body;};
const options = transport => ({transport, token, socketPath});
const flags = ['--socket', socketPath, '--workspace', scope.workspace_id, '--company', scope.company_id,
  '--device', scope.device_id];

test('malformed CLI input fails before transport and does not echo input', async t => {
  const cases = [
    ['unknown command', ['manual', 'show', ...flags]],
    ['missing workspace', ['equipment', 'list', '--socket', socketPath, '--company', 'company_a', '--device', 'device_a']],
    ['missing company', ['equipment', 'list', '--socket', socketPath, '--workspace', 'workspace_a', '--device', 'device_a']],
    ['missing device', ['equipment', 'list', '--socket', socketPath, '--workspace', 'workspace_a', '--company', 'company_a']],
    ['implicit socket', ['equipment', 'list', ...flags.slice(2)]],
    ['relative socket', ['equipment', 'list', ...flags.map(v => v === socketPath ? './agent.sock' : v)]],
    ['network socket', ['equipment', 'list', ...flags.map(v => v === socketPath ? 'https://example.invalid' : v)]],
    ['duplicate option', ['equipment', 'list', ...flags, '--company', 'company_b']],
    ['credential option', ['equipment', 'list', ...flags, '--token', token]],
    ['trailing positional', ['equipment', 'list', ...flags, 'extra']],
    ['missing option value', ['equipment', 'show', ...flags, '--id']],
    ['out of range limit', ['equipment', 'list', ...flags, '--limit', '101']],
    ['negative limit', ['equipment', 'list', ...flags, '--limit', '-1']],
    ['fractional limit', ['equipment', 'list', ...flags, '--limit', '1.1']],
    ['empty record id', ['equipment', 'show', ...flags, '--id', '']],
    ['unsafe record id', ['equipment', 'show', ...flags, '--id', '../company_b']],
    ['read operation id', ['equipment', 'list', ...flags, '--operation', idempotency_key]],
    ['proposal invalid JSON', ['proposals', 'create', ...flags, '--operation', idempotency_key, '--input', '-'], '{'],
    ['proposal array', ['proposals', 'create', ...flags, '--operation', idempotency_key, '--input', '-'], '[]'],
    ['proposal missing operation', ['proposals', 'create', ...flags, '--input', '-'], JSON.stringify(proposalBody())],
    ['proposal arbitrary state', ['proposals', 'create', ...flags, '--operation', idempotency_key, '--input', '-'],
      JSON.stringify({...proposalBody(), status: 'approved'})],
    ['proposal unsupported type', ['proposals', 'create', ...flags, '--operation', idempotency_key, '--input', '-'],
      JSON.stringify({...proposalBody(), type: 'invoice'})],
    ['proposal oversized input', ['proposals', 'create', ...flags, '--operation', idempotency_key, '--input', '-'], 'x'.repeat(64 * 1024 + 1)],
  ];
  for (const [name, argv, input = ''] of cases) await t.test(name, async () => {
    let calls = 0;
    const result = await run(argv, {env: {VORTICE_LOCAL_AGENT_TOKEN: token}, stdin: Readable.from([input]),
      transport: async () => {calls++; throw new Error(token);}});
    assert.equal(result.error.code, 'invalid_input');
    assert.equal(result.error.outcome, 'not_sent');
    assert.equal(calls, 0);
    assert.equal(JSON.stringify(result).includes(token), false);
  });
});

test('inherited object keys are not commands', async t => {
  for (const command of ['__proto__', 'constructor', 'toString', 'hasOwnProperty']) await t.test(command, async () => {
    let calls = 0;
    const result = await execute(readIntent(command, {}), options(async ({request}) => {calls++; return reply(request);}));
    assert.equal(result.error?.code, 'invalid_input');
    assert.equal(calls, 0, 'invalid command must never reach service');
  });
});

test('invalid command/options/scope do not consume proposal stdin', async t => {
  const cases = [
    ['file input', ['proposals', 'create', ...flags, '--operation', idempotency_key, '--input', 'synthetic.json']],
    ['read input', ['equipment', 'list', ...flags, '--input', '-']],
    ['proposal missing scope', ['proposals', 'create', '--socket', socketPath, '--operation', idempotency_key, '--input', '-']],
    ['proposal missing operation', ['proposals', 'create', ...flags, '--input', '-']],
  ];
  for (const [name, argv] of cases) await t.test(name, async () => {
    let reads = 0;
    const stdin = {[Symbol.asyncIterator]() {reads++; throw new Error('stdin must not be consumed');}};
    const result = await run(argv, {env: {VORTICE_LOCAL_AGENT_TOKEN: token}, stdin,
      transport: async () => {throw new Error('transport must not be called');}});
    assert.equal(result.error.code, 'invalid_input');
    assert.equal(reads, 0);
  });
});

test('valid collection pagination and filters preserve exact arguments', async () => {
  let captured;
  const result = await run(['history', 'list', ...flags, '--limit', '3', '--cursor', 'synthetic_cursor',
    '--job', 'job_a', '--equipment', 'equipment_a'], {env: {VORTICE_LOCAL_AGENT_TOKEN: token},
    transport: async ({request}) => {captured = request; return reply(request, {items: [], count: 0, next_cursor: null});}});
  assert.equal(result.ok, true);
  assert.deepEqual(captured.args, {limit: 3, cursor: 'synthetic_cursor', job_id: 'job_a', equipment_id: 'equipment_a'});
  assert.deepEqual(captured.scope, scope);
});

test('malformed direct intents fail before transport', async t => {
  const good = proposalIntent();
  const cases = [null, [], {}, {...readIntent(), args: null}, {...readIntent(), scope: {...scope, token}},
    {...readIntent(), scope: {...scope, company_id: 'company a'}}, {...readIntent(), command: null},
    {...readIntent(), args: {limit: true}}, {...readIntent(), args: {limit: 0}},
    {...readIntent(), args: {cursor: ''}}, {...readIntent(), args: {cursor: 'x'.repeat(4097)}},
    {...readIntent(), args: {anything: token}}, {...good, args: {...good.args, idempotency_key: token}},
    {...good, args: {...good.args, notes: '  '}},
    {...good, args: {...good.args, notes: 'x'.repeat(10001)}},
    {...good, args: {...good.args, job_id: 12}}];
  for (const [i, intent] of cases.entries()) await t.test(String(i), async () => {
    let calls = 0;
    const result = await execute(intent, options(async () => {calls++;}));
    assert.equal(result.error.code, 'invalid_input');
    assert.equal(calls, 0);
    assert.equal(JSON.stringify(result).includes(token), false);
  });
});

test('credential validation never calls transport or echoes secrets', async t => {
  for (const bad of [undefined, '', 'short', `${token}\n`, `${token}\0`, 'x'.repeat(4097)]) await t.test(String(bad?.length), async () => {
    let calls = 0;
    const result = await execute(readIntent(), {...options(async () => {calls++;}), token: bad});
    assert.equal(result.error.code, 'auth_required');
    assert.equal(result.error.outcome, 'not_sent');
    assert.equal(calls, 0);
    assert.equal(JSON.stringify(result).includes(token), false);
  });
});

test('service errors use safe static versioned messages', async t => {
  for (const code of ['permission_denied', 'grant_expired', 'grant_revoked', 'not_found']) await t.test(code, async () => {
    const result = await execute(readIntent(), options(async ({request}) => rejection(request, code)));
    assert.equal(result.protocol_version, 1);
    assert.equal(result.ok, false);
    assert.equal(result.error.code, code);
    assert.equal(result.error.outcome, 'rejected');
    assert.equal(result.error.retryable, false);
    assert.equal(JSON.stringify(result).includes(token), false);
    assert.equal(JSON.stringify(result).includes('unsafe'), false);
  });
});

test('raw thrown exception does not disclose credential, path or proposal notes', async () => {
  const notes = 'synthetic confidential inspection note';
  const result = await execute(proposalIntent({notes}), options(async () => {
    throw new Error(`debug ${token} ${socketPath} ${notes}`);
  }));
  assert.equal(result.error.code, 'internal_error');
  assert.equal(result.error.outcome, 'unknown');
  assert.equal(result.error.idempotency_key, idempotency_key);
  for (const privateValue of [token, socketPath, notes]) assert.equal(JSON.stringify(result).includes(privateValue), false);
});

test('response identity and freshness metadata fail closed', async t => {
  const mutate = [
    ['wrong workspace', value => value.scope.workspace_id = 'workspace_b'],
    ['wrong company', value => value.scope.company_id = 'company_b'],
    ['wrong device', value => value.scope.device_id = 'device_b'],
    ['extra scope', value => value.scope.another = 'scope'],
    ['missing scope', value => delete value.scope.device_id],
    ['wrong protocol', value => value.protocol_version = 2],
    ['wrong request', value => value.request_id = 'not_the_request'],
    ['missing meta', value => delete value.meta],
    ['missing observation time', value => delete value.meta.observed_at],
    ['invalid observation time', value => value.meta.observed_at = 'unknown'],
    ['missing completeness', value => delete value.meta.complete],
    ['missing local revision', value => delete value.meta.local_revision],
    ['invalid completeness', value => value.meta.complete = 'yes'],
    ['invalid local revision', value => value.meta.local_revision = {token}],
    ['invalid source', value => value.meta.source = 'production_database'],
    ['missing sync knowledge', value => delete value.meta.synced],
    ['invalid sync time', value => value.meta.synced.verified = 'yes'],
    ['missing data', value => delete value.result],
    ['unknown server error', value => {value.ok = false; value.error = {code: token, retryable: false, outcome: 'rejected'};}],
  ];
  for (const [name, change] of mutate) await t.test(name, async () => {
    const result = await execute(readIntent(), options(async ({request}) => {
      const value = reply(request); change(value); return value;
    }));
    assert.equal(result.error.code, 'invalid_response');
    assert.equal(result.error.outcome, 'unknown');
    assert.equal(JSON.stringify(result).includes(token), false);
  });
});

test('local snapshot and unknown sync freshness stay explicit in a valid read', async () => {
  const result = await execute(readIntent(), options(async ({request}) => ({...reply(request,
    {items: [], count: 0, next_cursor: 'synthetic_cursor'}), meta: {...meta, complete: false}})));
  assert.equal(result.ok, true);
  assert.equal(result.meta.local_revision, '7'.repeat(64));
  assert.equal(result.meta.freshness, 'local_snapshot');
  assert.deepEqual(result.meta.synced, {verified: false, reason: 'no_fresh_transfer_proof'});
  assert.equal(result.meta.complete, false);
});

test('unrecognized response metadata cannot disclose a capability', async () => {
  const result = await execute(readIntent(), options(async ({request}) => ({...reply(request),
    meta: {...meta, debugToken: token}})));
  assert.equal(JSON.stringify(result).includes(token), false);
});

test('different record IDs, cross-company data and secret structural fields fail closed', async t => {
  const cases = [
    ['wrong record', {item: {id: 'equipment_b'}}],
    ['wrong company', {item: {id: 'equipment_a', company_id: 'company_b'}}],
    ['wrong nested company', {item: {id: 'equipment_a', context: {companyId: 'company_b'}}}],
    ['wrong workspace', {item: {id: 'equipment_a', workspace_id: 'workspace_b'}}],
    ['credential', {item: {id: 'equipment_a', credential: {token}}}],
    ['nested token', {item: {id: 'equipment_a', extra: {token}}}],
    ['private key', {item: {id: 'equipment_a', private_key: 'synthetic private material'}}],
    ['certificate', {item: {id: 'equipment_a', certificate: 'synthetic certificate'}}],
    ['database path', {item: {id: 'equipment_a', database_path: '/tmp/synthetic.sqlite'}}],
    ['evidence paths', {item: {id: 'equipment_a', evidence_paths: ['/tmp/synthetic-photo']}}],
    ['raw native document', {item: {id: 'equipment_a', raw_document: 'synthetic bytes'}}],
    ['backup material', {item: {id: 'equipment_a', backup: 'synthetic backup'}}],
  ];
  for (const [name, result] of cases) await t.test(name, async () => {
    const outcome = await execute(readIntent('equipment.show', {equipment_id: 'equipment_a'}),
      options(async ({request}) => reply(request, result)));
    assert.equal(outcome.error.code, 'invalid_response');
    assert.equal(outcome.error.outcome, 'unknown');
    assert.equal(Object.hasOwn(outcome, 'result'), false);
    assert.equal(JSON.stringify(outcome).includes(token), false);
  });
});

test('malformed collections cannot disguise scope, counts or completeness', async t => {
  const good = {items: [{id: 'equipment_a'}], count: 1, next_cursor: null};
  const cases = [
    ['missing count', value => delete value.count],
    ['inflated count', value => value.count = 999],
    ['negative count', value => value.count = -1],
    ['fractional count', value => value.count = 1.1],
    ['wrong item shape', value => value.items = [null]],
    ['missing item identity', value => value.items = [{name: 'synthetic equipment'}]],
    ['empty item identity', value => value.items = [{id: ''}]],
    ['cross-company item', value => value.items[0].company_id = 'company_b'],
    ['secret item', value => value.items[0].token = token],
    ['additional count', value => value.total = 9000],
    ['empty cursor', value => value.next_cursor = ''],
    ['wrong cursor type', value => value.next_cursor = 123],
    ['oversized cursor', value => value.next_cursor = 'x'.repeat(4097)],
    ['page exceeds requested limit', value => {value.items.push({id: 'equipment_b'}); value.count = 2;}],
    ['inconsistent complete flag', value => value.next_cursor = 'next_page'],
  ];
  for (const [name, change] of cases) await t.test(name, async () => {
    const result = structuredClone(good); change(result);
    const outcome = await execute(readIntent('equipment.list', {limit: 1}),
      options(async ({request}) => reply(request, result)));
    assert.equal(outcome.error.code, 'invalid_response');
    assert.equal(Object.hasOwn(outcome, 'result'), false);
  });
});

test('valid scoped record and ordinary free text survive intact', async () => {
  const item = {id: 'equipment_a', company_id: scope.company_id, workspace_id: scope.workspace_id,
    notes: 'Replace the token indicator; document the inspection.'};
  const result = await execute(readIntent('equipment.show', {equipment_id: 'equipment_a'}),
    options(async ({request}) => reply(request, {item})));
  assert.equal(result.ok, true);
  assert.deepEqual(result.result.item, item);
});

test('capabilities cannot advertise unsupported commands or proposal types', async t => {
  for (const data of [{commands: ['approve'], proposal_types: ['inspection.notes']},
    {commands: ['equipment.list'], proposal_types: ['invoice']},
    {commands: ['equipment.list'], proposal_types: ['inspection.notes'], token}]) await t.test(JSON.stringify(data.commands), async () => {
    const result = await execute(readIntent('capabilities', {}), options(async ({request}) => reply(request, data)));
    assert.equal(result.error.code, 'invalid_response');
  });
  const result = await execute(readIntent('capabilities', {}), options(async ({request}) => reply(request,
    {commands: ['equipment.list', 'proposals.create'], proposal_types: ['inspection.notes']})));
  assert.equal(result.ok, true);
});

test('proposal replies cannot claim consequential actions or mismatched operations', async t => {
  const cases = [
    ['approved status', value => value.status = 'approved'],
    ['published status', value => value.status = 'published'],
    ['prepared status', value => value.status = 'prepared'],
    ['mismatched operation', value => value.idempotency_key = '22222222-2222-4222-8222-222222222222'],
    ['missing operation', value => delete value.idempotency_key],
    ['applied without review', value => value.applied = true],
    ['no human review', value => value.requires_human_review = false],
    ['wrong work record', value => value.job_id = 'job_b'],
    ['wrong frozen version', value => value.expected_document_hash = 'b'.repeat(64)],
    ['altered suggestion', value => value.notes = 'Unexpected synthetic change'],
    ['approved review state', value => value.review = 'approved'],
    ['returned review state', value => value.review = 'returned'],
  ];
  for (const [name, change] of cases) await t.test(name, async () => {
    const result = await execute(proposalIntent(), options(async ({request}) => {
      const data = pending(request); change(data.item); return reply(request, data);
    }));
    assert.equal(result.error?.code, 'invalid_response');
    assert.equal(result.error?.outcome, 'unknown');
    assert.equal(result.error?.idempotency_key, idempotency_key);
  });
});

test('proposal success explicitly requires human review and does not claim application', async () => {
  const result = await execute(proposalIntent(), options(async ({request}) => reply(request, pending(request))));
  assert.equal(result.ok, true);
  assert.equal(result.result.item.status, 'pending_human_review');
  assert.equal(result.result.item.requires_human_review, true);
  assert.equal(result.result.item.applied, false);
  assert.equal(result.result.item.idempotency_key, idempotency_key);
});

function syntheticScopedService() {
  const grants = new Map([
    [token, {scope, records: new Set(['equipment_a']), state: 'active'}],
    ['synthetic-revoked-agent-capability', {scope, records: new Set(['equipment_a']), state: 'revoked'}],
    ['synthetic-expired-agent-capability', {scope, records: new Set(['equipment_a']), state: 'expired'}],
  ]);
  const records = new Map([
    ['equipment_a', {id: 'equipment_a', company_id: 'company_a'}],
    ['equipment_private', {id: 'equipment_private', company_id: 'company_a'}],
    ['equipment_b', {id: 'equipment_b', company_id: 'company_b'}],
  ]);
  return async ({request, token: provided}) => {
    const grant = grants.get(provided);
    if (!grant) return rejection(request, 'permission_denied');
    if (grant.state !== 'active') return rejection(request, grant.state === 'revoked' ? 'grant_revoked' : 'grant_expired');
    if (Object.keys(scope).some(key => request.scope[key] !== grant.scope[key])) return rejection(request, 'permission_denied');
    if (request.command === 'equipment.show') {
      const record = records.get(request.args.equipment_id);
      if (!record || record.company_id !== request.scope.company_id || !grant.records.has(record.id)) return rejection(request, 'not_found');
      return reply(request, {item: record});
    }
    return reply(request, {items: [...records.values()].filter(record =>
      record.company_id === request.scope.company_id && grant.records.has(record.id)), count: 1, next_cursor: null});
  };
}

test('synthetic service fixture enforces company and per-object scopes; not real authorization proof', async () => {
  const transport = syntheticScopedService();
  const listed = await execute(readIntent(), options(transport));
  assert.deepEqual(listed.result.items.map(value => value.id), ['equipment_a']);
  const allowed = await execute(readIntent('equipment.show', {equipment_id: 'equipment_a'}), options(transport));
  assert.equal(allowed.ok, true);
  for (const id of ['equipment_private', 'equipment_b']) {
    const result = await execute(readIntent('equipment.show', {equipment_id: id}), options(transport));
    assert.equal(result.error.code, 'not_found');
    assert.equal(Object.hasOwn(result, 'result'), false);
  }
  const crossCompany = {...readIntent(), scope: {...scope, company_id: 'company_b'}};
  assert.equal((await execute(crossCompany, options(transport))).error.code, 'permission_denied');
  for (const state of ['revoked', 'expired']) {
    const result = await execute(readIntent(), {...options(transport), token: `synthetic-${state}-agent-capability`});
    assert.equal(result.error.code, state === 'revoked' ? 'grant_revoked' : 'grant_expired');
  }
});

test('partial synthetic proposal acceptance preserves operation ID and never automatically retries', async () => {
  const accepted = new Map();
  let calls = 0;
  let saves = 0;
  const transport = async ({request}) => {
    calls++;
    const payload = JSON.stringify({scope: request.scope, args: request.args});
    if (accepted.has(request.args.idempotency_key)) {
      const previous = accepted.get(request.args.idempotency_key);
      if (previous.payload !== payload) return rejection(request, 'idempotency_conflict');
      return reply(request, previous.data);
    }
    const data = pending(request);
    accepted.set(request.args.idempotency_key, {payload, data}); saves++;
    throw new CliError('service_unavailable', {retryable: true, outcome: 'unknown'});
  };
  const first = await execute(proposalIntent(), options(transport));
  assert.equal(first.error.code, 'service_unavailable');
  assert.equal(first.error.outcome, 'unknown');
  assert.equal(first.error.idempotency_key, idempotency_key);
  assert.equal(calls, 1);
  assert.equal(saves, 1);
  const replay = await execute(proposalIntent(), options(transport));
  assert.equal(replay.ok, true);
  assert.equal(replay.result.item.idempotency_key, idempotency_key);
  assert.equal(saves, 1);
  const changed = await execute(proposalIntent({notes: 'Different synthetic intent'}), options(transport));
  assert.equal(changed.error.code, 'idempotency_conflict');
  assert.equal(changed.error.idempotency_key, idempotency_key);
  assert.equal(saves, 1);
});

test('malformed write response also leaves outcome unknown with exact retry identity', async () => {
  let calls = 0;
  const result = await execute(proposalIntent(), options(async ({request}) => {calls++; return {...reply(request, pending(request)), request_id: 'wrong'};}));
  assert.equal(result.error.code, 'invalid_response');
  assert.equal(result.error.outcome, 'unknown');
  assert.equal(result.error.idempotency_key, idempotency_key);
  assert.equal(calls, 1);
});
