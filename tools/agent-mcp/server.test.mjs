import test from 'node:test';
import assert from 'node:assert/strict';
import { PassThrough, Readable } from 'node:stream';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { configuration, createHandler, serve } from './server.mjs';

const env = {
  VORTICE_NEXT_URL: 'https://hkjpojobdbbtjkhaudki.supabase.co',
  VORTICE_NEXT_PUBLIC_KEY: 'sb_publishable_localtest',
  VORTICE_AGENT_TOKEN: `vna_${'a'.repeat(64)}`,
};
const req = (method, params = {}, id = 1) => ({ jsonrpc: '2.0', id, method, params });
const init = req('initialize', { protocolVersion: '2025-11-25', capabilities: {}, clientInfo: { name: 'test', version: '1' } });
const args = { operation_id: 'a0190000-0000-4000-8000-000000000001', asset_id: 'a0190000-0000-4000-8000-000000000021', title: 'Inspect mounting' };
const draft = (arguments_ = args) => req('tools/call', { name: 'vortice_create_work_order_draft', arguments: arguments_ });

test('configuration pins Next, requires scoped token and rejects admin/session keys', () => {
  assert.equal(configuration(env).url, env.VORTICE_NEXT_URL);
  assert.throws(() => configuration({ ...env, VORTICE_NEXT_URL: 'https://example.com' }));
  assert.throws(() => configuration({ ...env, VORTICE_NEXT_URL: `${env.VORTICE_NEXT_URL}/redirect` }));
  assert.throws(() => configuration({ ...env, VORTICE_AGENT_TOKEN: 'user-session' }));
  for (const role of ['service_role', 'authenticated']) {
    const key = `e30.${Buffer.from(JSON.stringify({ role, ref: 'hkjpojobdbbtjkhaudki' })).toString('base64url')}.signature`;
    assert.throws(() => configuration({ ...env, VORTICE_NEXT_PUBLIC_KEY: key }));
  }
  const key = `e30.${Buffer.from(JSON.stringify({ role: 'anon', ref: 'hkjpojobdbbtjkhaudki' })).toString('base64url')}.signature`;
  assert.equal(configuration({ ...env, VORTICE_NEXT_PUBLIC_KEY: key }).key, key);
});

test('protocol initialization, discovery and notification silence', async () => {
  const handler = createHandler(configuration(env), () => { throw new Error('must not fetch'); });
  assert.equal((await handler(req('tools/list'))).error.code, -32000);
  assert.equal((await handler(init)).result.protocolVersion, '2025-11-25');
  assert.equal((await handler(req('tools/list'))).result.tools.length, 11);
  assert.equal(await handler({ jsonrpc: '2.0', method: 'notifications/initialized' }), null);
  assert.equal((await handler(req('resources/read'))).error.code, -32601);
  assert.equal((await handler([])).error.code, -32600);
  assert.equal((await handler({ ...init, id: null })).error.code, -32600);
});

test('invalid tools and input cannot reach network', async () => {
  let called = 0;
  const handler = createHandler(configuration(env), async () => { called++; return Response.json({}); });
  await handler(init);
  for (const request of [
    req('tools/call', { name: 'execute_sql', arguments: { query: 'select 1' } }),
    draft({ ...args, assigned_to: args.asset_id }), draft({ ...args, operation_id: 'bad' }),
    draft({ ...args, title: '  ' }), draft({ ...args, job_type: 'invoice' }), draft({ ...args, asset_id: null }),
    draft({ ...args, description: 'x'.repeat(8001) }), draft({ ...args, expected_materials: { malicious: true } }),
    req('tools/call', { name: 'vortice_maintenance_summary', arguments: { page: -1 } }),
    req('tools/call', { name: 'vortice_maintenance_summary', arguments: { page: 0.5 } }),
    req('tools/call', { name: 'vortice_maintenance_summary', arguments: { client_id: args.asset_id } }),
  ]) assert.equal((await handler(request)).error.code, -32602);
  assert.equal(called, 0);
});

test('write maps only allowlisted API action and preserves idempotency UUID', async () => {
  const calls = [];
  const handler = createHandler(configuration(env), async (url, options) => {
    calls.push({ url, options });
    return Response.json({ data: { work_order_id: args.asset_id, status: 'draft' } });
  });
  await handler(init);
  const response = await handler(draft());
  await handler(draft());
  assert.equal(response.result.isError, false);
  assert.equal(calls[0].url, `${env.VORTICE_NEXT_URL}/rest/v1/rpc/agent_execute`);
  assert.equal(calls[0].options.redirect, 'error');
  const body = JSON.parse(calls[0].options.body);
  assert.equal(body.p_action, 'create_work_order_draft');
  assert.equal(body.p_token, env.VORTICE_AGENT_TOKEN);
  assert.equal(body.p_operation, args.operation_id);
  assert.equal(body.p_input.operation_id, undefined);
  assert.deepEqual(calls[0].options.body, calls[1].options.body);
  assert.ok(!JSON.stringify(response).includes(env.VORTICE_AGENT_TOKEN));
});

test('API denial, network errors, invalid/oversized responses never leak credentials', async () => {
  for (const response of [
    () => Response.json({ error: 'Access denied' }),
    () => Response.json({ error: env.VORTICE_AGENT_TOKEN }),
    () => new Response(env.VORTICE_AGENT_TOKEN, { status: 500 }),
    () => new Response('x'.repeat(1024 * 1024 + 1)),
    () => Response.json({ data: null }),
    () => { throw new Error(env.VORTICE_AGENT_TOKEN); },
  ]) {
    const handler = createHandler(configuration(env), response);
    await handler(init);
    const result = await handler(draft());
    assert.equal(result.result.isError, true);
    assert.ok(!JSON.stringify(result).includes(env.VORTICE_AGENT_TOKEN));
  }
});

test('stdio supports fragmented UTF8, multiple messages and malformed JSON', async () => {
  const output = new PassThrough();
  const collected = [];
  output.on('data', chunk => collected.push(chunk));
  const input = Buffer.from(`${JSON.stringify(init)}\n{broken}\n${JSON.stringify(req('tools/list', {}, 'á'))}\n`);
  const cut = input.indexOf(Buffer.from('á')) + 1;
  await serve(Readable.from([input.subarray(0, cut), input.subarray(cut)]), output, createHandler(configuration(env)));
  const replies = Buffer.concat(collected).toString().trim().split('\n').map(JSON.parse);
  assert.equal(replies.length, 3);
  assert.equal(replies[1].error.code, -32700);
  assert.equal(replies[2].id, 'á');
});

test('oversized unterminated input is stopped', async () => {
  await assert.rejects(serve(Readable.from(['x'.repeat(131073)]), new PassThrough(), () => {}), /too large/);
});

test('real process speaks MCP over stdin/stdout and cleanly rejects bad configuration', () => {
  const path = fileURLToPath(new URL('./server.mjs', import.meta.url));
  const result = spawnSync(process.execPath, [path], { env, encoding: 'utf8', input: `${JSON.stringify(init)}\n${JSON.stringify(req('tools/list'))}\n` });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stderr, '');
  assert.equal(result.stdout.trim().split('\n').map(JSON.parse)[1].result.tools.length, 11);
  const bad = spawnSync(process.execPath, [path], { env: { ...env, VORTICE_AGENT_TOKEN: 'bad-secret' }, encoding: 'utf8' });
  assert.equal(bad.status, 1);
  assert.ok(!bad.stderr.includes('bad-secret'));
  assert.equal(bad.stdout, '');
});

test('document page returns native MCP image content through the fixed proxy', async () => {
  const calls = [];
  const bytes = Buffer.from([137,80,78,71,13,10,26,10]);
  const handler = createHandler(configuration(env), async (url, options) => {
    calls.push({ url, body: JSON.parse(options.body) });
    return new Response(bytes, { headers: { 'Content-Type': 'image/png' } });
  });
  await handler(init);
  const response = await handler(req('tools/call', { name: 'vortice_document_page', arguments: { document_id: args.asset_id, page: 1 } }));
  assert.equal(response.result.content[1].type, 'image');
  assert.equal(response.result.content[1].data, bytes.toString('base64'));
  assert.equal(calls[0].url, `${env.VORTICE_NEXT_URL}/functions/v1/agent-document-page`);
  assert.equal(calls[0].body.token, env.VORTICE_AGENT_TOKEN);
  assert.ok(!JSON.stringify(response).includes(env.VORTICE_AGENT_TOKEN));
});

test('source draft nested validation rejects injected fields and preserves quotes', async () => {
  const calls = [];
  const handler = createHandler(configuration(env), async (_, options) => {
    calls.push(JSON.parse(options.body));
    return Response.json({ data: { procedure_id: args.asset_id, status: 'draft' } });
  });
  await handler(init);
  const input = { operation_id: args.operation_id, asset_id: args.asset_id, document_id: args.asset_id,
    name: 'Cooling system', checklist_type: 'operator_daily', items: [{ description_en: 'Inspect coolant when cold', source_page: 1,
      source_quote: 'Only open when cold', definition: { critical: true, input_type: 'check' } }] };
  const call = arguments_ => handler(req('tools/call', { name: 'vortice_create_checklist_draft', arguments: arguments_ }));
  assert.equal((await call({ ...input, items: [{ ...input.items[0], definition: { execute: 'delete_all' } }] })).error.code, -32602);
  assert.equal((await call({ ...input, items: [{ ...input.items[0], source_page: 31 }] })).error.code, -32602);
  assert.equal((await call({ ...input, items: [] })).error.code, -32602);
  assert.equal(calls.length, 0);
  assert.equal((await call(input)).result.isError, false);
  assert.equal(calls[0].p_action, 'create_checklist_draft');
  assert.equal(calls[0].p_input.items[0].source_quote, input.items[0].source_quote);
  assert.equal(calls[0].p_operation, input.operation_id);
});

test('management tools require revisions and do not expose completion or overlap overrides', async () => {
  const calls = [];
  const handler = createHandler(configuration(env), async (_, options) => { calls.push(JSON.parse(options.body)); return Response.json({ data: {} }); });
  await handler(init);
  const input = { operation_id: args.operation_id, work_order_id: args.asset_id, revision: 4, assigned_to: args.asset_id };
  assert.equal((await handler(req('tools/call', { name: 'vortice_assign_work_order', arguments: input }))).result.isError, false);
  assert.equal(calls[0].p_input.revision, 4);
  assert.equal(calls[0].p_action, 'assign_work_order');
  assert.equal((await handler(req('tools/call', { name: 'vortice_assign_work_order', arguments: { ...input, revision: null } }))).error.code, -32602);
  assert.equal((await handler(req('tools/call', { name: 'vortice_complete_work_order', arguments: input }))).error.code, -32602);
});

test('plan proposal accepts sourced hours but forbids invented equipment service history', async () => {
  let body;
  const handler = createHandler(configuration(env), async (_, options) => { body = JSON.parse(options.body); return Response.json({ data: { status:'draft' } }); });
  await handler(init);
  const input = { operation_id:args.operation_id,document_id:args.asset_id,asset_id:args.asset_id,engine_id:args.asset_id,
    interval_label:'Cooling service',interval_hours:250,source_page:1,source_quote:'Service every 250 hours' };
  const call = arguments_ => handler(req('tools/call',{name:'vortice_create_plan_draft',arguments:arguments_}));
  assert.equal((await call({...input,last_service_hours:0})).error.code,-32602);
  assert.equal((await call({...input,interval_hours:0})).error.code,-32602);
  assert.equal((await call(input)).result.isError,false);
  assert.equal(body.p_action,'create_plan_draft');
  assert.equal(body.p_input.interval_hours,250);
});
