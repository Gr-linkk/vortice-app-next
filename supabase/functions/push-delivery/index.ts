import { fcmMessage, isInvalidToken, type Delivery } from "./message.ts";

const env = (name: string) => Deno.env.get(name) ?? "";
const base64url = (input: Uint8Array | string) => btoa(typeof input === "string" ? input : String.fromCharCode(...input))
  .replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");

async function googleToken() {
  const account = JSON.parse(env("FIREBASE_SERVICE_ACCOUNT_JSON"));
  const project = env("FIREBASE_PROJECT_ID");
  if (!project || account.project_id !== project) throw new Error("Firebase project mismatch");
  const now = Math.floor(Date.now() / 1000);
  const unsigned = `${base64url(JSON.stringify({ alg: "RS256", typ: "JWT" }))}.${base64url(JSON.stringify({
    iss: account.client_email, scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token", iat: now, exp: now + 3600,
  }))}`;
  const pem = account.private_key.replace(/-----[^-]+-----|\s/g, "");
  const key = await crypto.subtle.importKey("pkcs8", Uint8Array.from(atob(pem), c => c.charCodeAt(0)),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(unsigned));
  const response = await fetch("https://oauth2.googleapis.com/token", { method: "POST",
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: `${unsigned}.${base64url(new Uint8Array(signature))}` }),
    signal: AbortSignal.timeout(15000) });
  if (!response.ok) throw new Error("Firebase authorization failed");
  return { project, token: (await response.json()).access_token as string };
}

async function rpc(name: string, body: object = {}) {
  const url = env("SUPABASE_URL");
  if (new URL(url).hostname !== "hkjpojobdbbtjkhaudki.supabase.co") throw new Error("Wrong Supabase target");
  const response = await fetch(`${url}/rest/v1/rpc/${name}`, { method: "POST",
    headers: { apikey: env("SUPABASE_SERVICE_ROLE_KEY"), Authorization: `Bearer ${env("SUPABASE_SERVICE_ROLE_KEY")}`, "Content-Type": "application/json" },
    body: JSON.stringify(body), signal: AbortSignal.timeout(15000) });
  if (!response.ok) throw new Error(`Database operation failed: ${name}`);
  return response.status === 204 ? null : await response.json();
}

Deno.serve(async (request: Request) => {
  const secret = env("PUSH_WORKER_SECRET");
  if (!secret || request.method !== "POST" || request.headers.get("x-push-worker-secret") !== secret) {
    return new Response("Unauthorized", { status: 401 });
  }
  if (!env("FIREBASE_PROJECT_ID") || !env("FIREBASE_SERVICE_ACCOUNT_JSON")) {
    return new Response("Firebase delivery is not configured", { status: 503 });
  }
  try {
    const google = await googleToken();
    const rows: Delivery[] = await rpc("claim_push_deliveries", { p_limit: 25 });
    let sent = 0;
    await Promise.all(rows.map(async (row) => {
      let success = false, invalid = false, error: string | null = null;
      try {
        const result = await fetch(`https://fcm.googleapis.com/v1/projects/${google.project}/messages:send`, {
          method: "POST", headers: { Authorization: `Bearer ${google.token}`, "Content-Type": "application/json" },
          body: JSON.stringify(fcmMessage(row)), signal: AbortSignal.timeout(15000),
        });
        success = result.ok;
        if (!success) { invalid = isInvalidToken(await result.json()); error = `FCM HTTP ${result.status}`; }
      } catch (_) { error = "Delivery response unavailable; retry pending"; }
      await rpc("finish_push_delivery", { p_delivery: row.id, p_lease: row.lease, p_success: success, p_error: error, p_invalid_token: invalid });
      if (success) sent++;
    }));
    return Response.json({ claimed: rows.length, accepted_by_fcm: sent });
  } catch (_) { return new Response("Delivery unavailable; queued work retained", { status: 503 }); }
});
