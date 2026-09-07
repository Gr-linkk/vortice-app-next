import test from 'node:test';
import assert from 'node:assert/strict';
import { createDocumentHandler } from './handler.mjs';
const NEXT = 'https://hkjpojobdbbtjkhaudki.supabase.co';
const env = { SUPABASE_URL: NEXT, SUPABASE_ANON_KEY: 'PUBLIC_TEST', SUPABASE_SERVICE_ROLE_KEY: 'SERVER_SECRET_TEST' };
const input = { token: `vna_${'a'.repeat(64)}`, document_id: 'a0200000-0000-4000-8000-000000000040', page: 1 };
const request = (body = input) => new Request(`${NEXT}/functions/v1/agent-document-page`, { method: 'POST', body: JSON.stringify(body) });
const png = new Uint8Array([137,80,78,71,13,10,26,10]);

test('authorized page proxies exact immutable path without revealing service key', async () => {
  const calls = [];
  const handler = createDocumentHandler(env, async (url, options) => {
    calls.push({ url, options });
    if (calls.length === 1) return Response.json({ data: { object_path: `${input.document_id}/1.png` } });
    return new Response(png);
  });
  const response = await handler(request());
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('content-type'), 'image/png');
  assert.equal(response.headers.get('cache-control'), 'no-store');
  assert.deepEqual(new Uint8Array(await response.arrayBuffer()), png);
  assert.equal(calls[0].url, `${NEXT}/rest/v1/rpc/agent_execute`);
  assert.equal(JSON.parse(calls[0].options.body).p_action, 'document_page');
  assert.ok(!JSON.stringify(calls[0].options).includes(env.SUPABASE_SERVICE_ROLE_KEY));
  assert.equal(calls[1].url, `${NEXT}/storage/v1/object/maintenance-documents/${input.document_id}/1.png`);
  assert.equal(calls[1].options.redirect, 'error');
});

test('revoked grant and forged paths never reach storage', async () => {
  for (const answer of [{ error: 'Access denied' }, { data: { object_path: '../another-bucket/secret.png' } },
    { data: { object_path: `${input.document_id}/2.png` } }, { data: { object_path: 'https://example.invalid/image' } }]) {
    let calls = 0;
    const response = await createDocumentHandler(env, async () => { calls++; return Response.json(answer); })(request());
    assert.equal(response.status, 403);
    assert.equal(calls, 1);
    assert.equal(await response.text(), 'Document unavailable');
  }
});

test('invalid input, wrong environment and oversized request cannot cause a fetch', async () => {
  const fetchImpl = () => { throw new Error('network must not run'); };
  for (const value of [{ ...input, page: 0 }, { ...input, token: 'bad' }, { ...input, path: 'forged' }, { ...input, document_id: 'bad' }]) {
    assert.equal((await createDocumentHandler(env, fetchImpl)(request(value))).status, 400);
  }
  assert.equal((await createDocumentHandler(env, fetchImpl)(request({ token: 'x'.repeat(2049) }))).status, 413);
  assert.equal((await createDocumentHandler({ ...env, SUPABASE_URL: 'https://example.invalid' }, fetchImpl)(request())).status, 503);
});

test('non-images and oversized storage replies are rejected without leaking backend errors', async () => {
  for (const bytes of [new TextEncoder().encode(env.SUPABASE_SERVICE_ROLE_KEY), new Uint8Array(5*1024*1024+1)]) {
    let calls = 0;
    const response = await createDocumentHandler(env, async () => ++calls === 1
      ? Response.json({ data: { object_path: `${input.document_id}/1.png` } }) : new Response(bytes))(request());
    assert.ok(response.status >= 400);
    assert.ok(!(await response.text()).includes(env.SUPABASE_SERVICE_ROLE_KEY));
  }
});
