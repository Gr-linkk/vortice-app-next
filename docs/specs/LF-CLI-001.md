# LF-CLI-001 — Scoped desktop agent client

Status: client implemented; real shared-service integration pending.
Authorization: Garrett's October 1 request for a desktop CLI for external agents.
Base: `45380ae6b093a400e8a5f589b19359fe822bfc28`, LF-001 inspection runtime.
Owner: `codex/local-agent-cli`; main workflow owns shared service/runtime.

## First useful increment and ownership

Client files: `tools/local-agent-cli/`. Main service is independently owned in
`task-8/local-agent-service`, under `experiments/maintenance_local/lib/agent_service/`.
Read its `docs/specs/LF-CLI-SVC-001.md` for the authoritative v1 service contract.
Neither owner edits the other's implementation. Hosted MCP remains untouched as
intended-capability reference/rollback; its actual external-agent journey is not
proven and is not a parity gate.

Read commands: capabilities, workspace status, equipment list/show, procedures
list/show (existing published checklists), work list/show, immutable history and
pending proposals. No raw DB, phone `/bundle`, native documents, backup identity,
keys or OS-owner-derived company grant. Records are filtered by the service before
any details, counts or collections leave it.

The sole write is `proposals.create` for `inspection.notes`: suggested replacement
notes on an existing inspection pinned by its exact document hash. It persists a
proposal requiring human review, not an inspection edit/submission/approval.
No human application UI is claimed by this client increment. Proposals are not
yet replicated or included in the existing strict office backup format.
Manuals, recurring plans, work preparation/checklist draft types, assignment,
scheduling, inventory and billing remain missing support, not fake commands.

## Agreed service boundary

Unix-domain stream, JSON Lines v1, no TCP endpoint/discovery. Explicit absolute
socket path and workspace/company/device IDs are required. The host supplies
`VORTICE_LOCAL_AGENT_TOKEN` through private process environment; the client never
generates, configures or persists a credential. Authentication and every live
permission/expiry/revocation/record filter check belong to the service.

```json
{"protocol_version":1,"request_id":"uuid","scope":{"workspace_id":"id","company_id":"id","device_id":"id"},"credential":{"token":"opaque"},"command":"work.show","args":{"job_id":"id"}}
```

Client requires responses to echo version, request ID and exact scope. Success
contains `result` and `meta: {source: local, observed_at, freshness: local_snapshot,
synced: {verified: false, reason: no_fresh_transfer_proof}}`. A generated
observation time is not a reading timestamp or verified transfer. Current and
historical approval are separate; approval of old history never approves later
edits. Complete native-data projections/authority live in the shared service.

Proposal JSON input is `type: inspection.notes`, `job_id`,
`expected_document_hash` (64 lowercase hex), and nonempty suggested `notes`.
`--operation` supplies the caller's stable UUID as `idempotency_key`. Exact
retries preserve key/hash/payload. The service returns one durable pending
proposal, checks fresh authority before replay, and rejects changed-key payloads.
The client performs no automatic retry. Unknown transport/response failure keeps
the operation ID and must never be interpreted as rollback.

Errors are versioned JSON with stable safe codes/messages, retryability, outcome
(`not_sent`, `rejected`, `unknown`) and the idempotency key after a sent proposal.
Raw exceptions and service messages never reach output. Mismatched scope/version/
request ID rejects returned data. Request size is limited to the service's 64 KiB
line; response size is limited to 1 MiB and transport has a total deadline.
Collections support limit (1..100, default 25), opaque revision-bound cursors,
and service-checked job/equipment filters. Page counts reveal only returned rows.
Metadata includes scoped local_revision and explicit completeness.

## Evidence needed for completion

Independent CLI tests cover malformed inputs, synthetic scoped denials,
revoked/expired grants, reply identity, safe errors, exact retries and interrupted
Unix transport. Synthetic fixture authorization is contract evidence only.
A tested milestone additionally requires actual shared-service Unix IO with its
native SQLite/domain fixtures and synthetic grants: scoped reads, proposals,
restart/exact replay, changed-payload rejection and partial failure after durable
acceptance. Never use a real company, persistent grant, running office data or
real private key. No deployment/installation/merge/push/cutover is authorized.

## Client milestone — October 1, 2026 UTC

`node --test --test-reporter=spec tools/local-agent-cli/test/*.test.mjs` passes
155 tests, zero failures/skips. The bounded test run needs subprocess/private
Unix-socket access; it uses synthetic identities and temporary files only.
Independent review reproduced and closed the read-result validation gap: wrong
record/company IDs, malformed collections and unexpected structural private
fields now reject. Normal replies and legitimate user free text still pass.

The opt-in `integration/service-e2e.mjs` attaches only the main service's guarded
synthetic fixture, with a private `/tmp/vortice-cli-e2e-*` ready/socket directory.
It is prepared but has not yet run. Fixture/unit authorization and replay tests
are not native shared-service integration proof. No app screen, ordinary service
launcher, real grant provisioning, human application UI or backup/replication of
proposals is delivered by this client checkpoint.
