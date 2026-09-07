# NOW-019: Scoped agent access

Authorized 2026-09-07. Work is isolated on `codex/now-019-agent-access` while
equipment/UI and stress-test sessions use the shared checkout.

## First usable slice

Owner, client and client-admin users can create a named connection for one
explicit fleet. Default access is maintenance summaries; optional write access
creates unassigned managed work-order drafts through the existing checked RPC.
An API plus local stdio MCP adapter exposes only these actions. The More screen
provides creation, one-time key display, expiry, revocation and recent activity.
Users explicitly choose a trusted agent/provider before sharing fleet data.

## Enforced boundaries

- Opaque 256-bit connection keys, stored only as SHA-256 hashes; seven-day expiry.
- Owner grant creation requires an MFA-verified session and a live verified
  factor. In-app TOTP setup/reverification is provided; removing the owner's
  verified factors blocks existing owner grants. Disconnect remains available.
- Keys are not Supabase sessions and cannot invoke other authenticated RPCs.
- Every request rechecks live user role, fleet membership, grant scope, expiry
  and revocation. SQL dispatch serializes against revocation using a row lock.
- No arbitrary SQL, arbitrary RPC names, credentials, photos, billing, assignments,
  completion, signatures, scheduling or access-management tools.
- Draft creation has an operation UUID and exact-input replay protection. Only
  explicit allowlisted fields are accepted; output and input sizes are bounded.
- Connection rate limits, a daily draft limit, append-only activity, personal
  disconnect, fleet disconnect and owner global disconnect. These revoke current
  grants; they do not permanently ban future grant creation.
- No offline credential cache or queued grants. Errors retain form data. Account
  changes dispose the screen and discard any displayed key or fetched activity.

Manual connection keys are the initial stdio integration, not OAuth. Remote
HTTP MCP/OAuth and approval-bound consequential operations
are follow-on work, not claimed implemented by this slice. Hosted activation,
external AI privacy/retention review and real agent/device acceptance are separate
from local code/tests. No live migrations run while the shared stress test runs.

## Acceptance

Exercise actual SQL allow/deny for two companies, owner restrictions, role and
capability removal, expiry/revocation, unknown tools/fields, direct table access,
replay/conflict and unchanged service-completion/billing state. Test MCP through
stdin/stdout and mocked HTTP (errors, malformed messages, transport restrictions,
secret redaction). Verify Flutter form, revocation, errors and account isolation.

## Local implementation evidence (2026-09-07)

- Base `aeb7f40`, isolated branch `codex/now-019-agent-access`; the shared checkout
  and other tasks' changes were not modified or integrated.
- Guarded `scripts/verify.cmd`: clean analysis, 520 passed, 204 existing skips.
- All 18 local SQL suites passed after the access/MFA migration; the final
  owner-factor refresh assertion was then rerun successfully in the agent suite.
- Eight Node MCP tests passed, including real stdin/stdout process negotiation,
  mocked HTTP, strict arguments, credential redaction and bounded messages.
- Local Docker race test: eight simultaneous identical requests create one
  draft; revocation waits for an active write and blocks subsequent writes.
- Native fixture-based UI tests cover consent, errors, one-time keys, disconnect,
  account changes, MFA and English/Spanish at 320px/200% in both themes. Rendered
  screenshots are in `outputs/agent-access-screens/` in this worktree.
- Direct code review followed the UI, credential boundary, SQL dispatch and
  existing draft RPC. No independent reviewer was used. Corrected late-MFA
  account restoration, stale factor UI, and large-text label issues in this slice.

No migration, account enrollment, external agent connection, APK installation,
push or release was performed. These tests do not prove hosted PostgREST/MFA,
third-party MCP host configuration or physical-device acceptance.

## Activation after integration

First integrate the branch with the current Next base and rerun guarded checks,
preserving the other tasks' catalog/UI changes. From that verified checkout,
confirm the Next project-ref file and deploy through
`scripts/supabase-push.sh --project-ref hkjpojobdbbtjkhaudki`. Configure hosted
invalid-key/unauthenticated request limits before client rollout. Build through
the guarded Android helper using explicit Next configuration.

Follow `tools/agent-mcp/README.md` to connect a trusted MCP host. On actual devices,
verify owner TOTP setup and an existing factor, a client read-only grant, a
permitted draft appearing in Work, identical retry, and disconnect followed by
denial. Check that another fleet never appears. Never paste real keys into chat
or include them in evidence. OAuth and consequential-action approvals are not
part of the implemented adapter; those operations are not exposed.
