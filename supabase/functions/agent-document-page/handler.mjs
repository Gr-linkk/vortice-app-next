const NEXT = 'https://hkjpojobdbbtjkhaudki.supabase.co';
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function createDocumentHandler(env, fetchImpl = fetch) {
  return async request => {
    const reject = (status = 403) => new Response('Document unavailable', { status, headers: { 'Cache-Control': 'no-store' } });
    if (request.method !== 'POST') return reject(405);
    try {
      if (env.SUPABASE_URL !== NEXT || !env.SUPABASE_SERVICE_ROLE_KEY || !env.SUPABASE_ANON_KEY) return reject(503);
      let body = '';
      for await (const chunk of request.body) {
        body += new TextDecoder().decode(chunk);
        if (body.length > 2048) return reject(413);
      }
      const input = JSON.parse(body);
      if (!input || Object.keys(input).some(k => !['token', 'document_id', 'page'].includes(k)) ||
          !/^vna_[0-9a-f]{64}$/.test(input.token ?? '') || !UUID.test(input.document_id ?? '') ||
          !Number.isInteger(input.page) || input.page < 1 || input.page > 30) return reject(400);
      // Credentials, live role/fleet/MFA, revocation and read rate limits are
      // checked by the sole agent dispatcher. Never accept a client object path.
      const auth = await fetchImpl(`${NEXT}/rest/v1/rpc/agent_execute`, {
        method: 'POST', redirect: 'error', signal: AbortSignal.timeout(15000),
        headers: { apikey: env.SUPABASE_ANON_KEY, 'Content-Type': 'application/json' },
        body: JSON.stringify({ p_token: input.token, p_action: 'document_page', p_input: { document_id: input.document_id, page: input.page } }),
      });
      if (!auth.ok) return reject();
      const result = await auth.json();
      const path = result?.data?.object_path;
      if (result?.error || typeof path !== 'string' || !new RegExp(`^${input.document_id}/${input.page}\\.(jpg|png)$`, 'i').test(path)) return reject();
      const download = await fetchImpl(`${NEXT}/storage/v1/object/maintenance-documents/${path}`, {
        redirect: 'error', signal: AbortSignal.timeout(15000),
        headers: { apikey: env.SUPABASE_SERVICE_ROLE_KEY, Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}` },
      });
      if (!download.ok) return reject();
      const chunks = []; let size = 0;
      for await (const chunk of download.body) {
        size += chunk.length;
        if (size > 5 * 1024 * 1024) return reject(413);
        chunks.push(chunk);
      }
      const bytes = new Uint8Array(size); let offset = 0;
      for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
      const png = path.endsWith('.png');
      if (png ? bytes[0] !== 137 || bytes[1] !== 80 || bytes[2] !== 78 || bytes[3] !== 71 : bytes[0] !== 255 || bytes[1] !== 216 || bytes[2] !== 255) return reject();
      return new Response(bytes, { headers: { 'Content-Type': png ? 'image/png' : 'image/jpeg', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' } });
    } catch { return reject(); }
  };
}
