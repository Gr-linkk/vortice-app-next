import test from 'node:test';
import assert from 'node:assert/strict';
import { configuration, createHandler } from './server.mjs';

const env = { VORTICE_NEXT_URL: 'https://hkjpojobdbbtjkhaudki.supabase.co', VORTICE_NEXT_PUBLIC_KEY: 'sb_publishable_fixture', VORTICE_AGENT_TOKEN: `vna_${'b'.repeat(64)}` };
const request = (method, params = {}) => ({ jsonrpc: '2.0', id: 1, method, params });

test('connection test reaches scoped backend without a fleet read or mutation', async () => {
  const calls = [];
  const handler = createHandler(configuration(env), async (url, options) => {
    calls.push({ url, body: JSON.parse(options.body) });
    return Response.json({ data: { connected: true, connection_id: 'connection', human_review_required: true } });
  });
  await handler(request('initialize', { protocolVersion: '2025-11-25' }));
  await handler(request('ping'));
  assert.equal(calls.length, 0, 'transport ping must not be branded backend verification');
  const response = await handler(request('tools/call', { name: 'vortice_connection_test', arguments: {} }));
  assert.equal(response.result.isError, false);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].body.p_action, 'connection_test');
  assert.deepEqual(calls[0].body.p_input, {});
  assert.equal(calls[0].body.p_operation, null);
  assert.ok(!JSON.stringify(response).includes(env.VORTICE_AGENT_TOKEN));
});

test('connection check forbids extra scope and management tools advertise human review', async () => {
  const handler = createHandler(configuration(env), () => { throw new Error('must not fetch'); });
  await handler(request('initialize', { protocolVersion: '2025-11-25' }));
  const response = await handler(request('tools/call', { name: 'vortice_connection_test', arguments: { fleet_id: 'other' } }));
  assert.equal(response.error.code, -32602);
  const tools = (await handler(request('tools/list'))).result.tools;
  for (const name of ['assign_work_order', 'schedule_work_order', 'edit_work_order']) {
    assert.match(tools.find(tool => tool.name === `vortice_${name}`).description, /person must review and apply/);
  }
  assert.equal(tools.some(tool => /approve|invoice|publish|review_agent/.test(tool.name)), false);
});

test('plan tool preserves explicit distance units and rejects unknown units before network', async () => {
  const calls = [];
  const handler = createHandler(configuration(env), async (_, options) => {
    calls.push(JSON.parse(options.body));
    return Response.json({ data: { status: 'draft', review_required: true } });
  });
  await handler(request('initialize', { protocolVersion: '2025-11-25' }));
  const id = 'a3200000-0000-4000-8000-000000000001';
  const input = { operation_id: id, document_id: id, asset_id: id, engine_id: id, interval_label: 'Truck service', interval_hours: 10000, meter_unit: 'km', source_page: 1, source_quote: 'Service every 10000 km' };
  const response = await handler(request('tools/call', { name: 'vortice_create_plan_draft', arguments: input }));
  assert.equal(response.result.isError, false);
  assert.equal(calls[0].p_input.meter_unit, 'km');
  assert.equal(calls[0].p_input.interval_hours, 10000);
  const bad = await handler(request('tools/call', { name: 'vortice_create_plan_draft', arguments: { ...input, meter_unit: 'minutes' } }));
  assert.equal(bad.error.code, -32602);
  assert.equal(calls.length, 1);
});
