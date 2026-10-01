# LF-CLI-SVC-001 — Local agent service contract v1

Garrett selected a desktop CLI for external agents in the future local-first
edition. The hosted MCP remains rollback/reference. This isolated service is
code and synthetic integration only: no real persistent grant, production launch,
cutover, publication, network change or installation is authorized.

## Isolation and owners

Service: `task-8/local-agent-service`, branch `codex/local-agent-service`, base
receipt `b6d1c8d86950439be33921a2c4b6cf1638e71d95` (reviewed application `45380ae`).
Owner: maintenance coordinator/runtime worker. New service modules only under
`experiments/maintenance_local/lib/agent_service/`, unique service tests and
synthetic fixture launcher. Existing LabStore/sync/approval/Rust/recovery stays
unchanged. Reviewed LF-002 pure progress/reader modules may be ported selectively.

CLI owner separately owns `tools/local-agent-cli/` and `docs/specs/LF-CLI-001.md`
in `task/local-agent-cli`; this service does not edit those files. LF-002 work
continues separately in `task-8/maintenance-progress` with no CLI files.

## Transport and envelope

Canonical agreed protocol version **1**. The separate client owner explicitly
adopted this transport and snake_case envelope; its earlier HTTP/camelCase draft
is superseded. Local Linux private Unix-domain stream socket, JSON Lines:
one UTF-8 JSON object per line, one response per request. No TCP/public listener.
Maximum request line 64 KiB. File permissions/private parent apply in fixtures;
permission checked grants remain required even for a local peer. Start no real
service or create real grants during this implementation.

Request:

```json
{"protocol_version":1,"request_id":"req-1","scope":{"workspace_id":"workspace","company_id":"company","device_id":"device"},"credential":{"token":"opaque"},"command":"work.show","args":{"job_id":"job"}}
```

Success:

```json
{"protocol_version":1,"request_id":"req-1","scope":{"workspace_id":"workspace","company_id":"company","device_id":"device"},"ok":true,"result":{},"meta":{"observed_at":"UTC ISO8601","source":"local","freshness":"local_snapshot","local_revision":"scoped-data-hash","complete":true,"synced":{"verified":false,"reason":"no_fresh_transfer_proof"}}}
```

Failure:

```json
{"protocol_version":1,"request_id":"req-1","scope":{"workspace_id":"workspace","company_id":"company","device_id":"device"},"ok":false,"error":{"code":"permission_denied","message":"This grant does not allow that operation.","retryable":false,"outcome":"rejected"}}
```

Echo the exact validated three-field request scope on success and failure so
clients fail closed on cross-workspace replies. For an invalid scope/envelope,
use null instead of reflecting arbitrary input. Never emit grant-wide counts
outside record filters. No tokens, file paths, certificate/private keys, raw database/native bytes,
backup material or raw exceptions in responses/logs. Stable codes:
`invalid_request`, `unsupported_version`, `unauthorized`, `grant_expired`,
`grant_revoked`, `scope_mismatch`, `permission_denied`, `not_found`,
`stale_context`, `idempotency_conflict`, `unsupported_command`,
`unsupported_proposal`, `internal_error`. Backend exceptions are mapped to a
fixed internal error; recoverable local data is retained. Unknown fields and
ill-typed envelopes must not create proposals.

## Scope and commands

Grant identity is separate from office/mechanic identity. Require exact explicit
workspace, company and service-device scope, UTC expiry and revocation check on
every request (including exact replay). Default deny. Grant record includes
permitted command names and optional `job_ids` / `equipment_ids` allowlists.
Filters apply both to collections and details/history/proposals; an empty list
means no records, null means all records within this one company. Job access
must also satisfy its equipment filter. Never infer an agent grant from access
to the filesystem, a mechanic token or the office flag.

Commands v1 (subject to grant and filters):

- `capabilities`: supported protocol/commands/proposal types permitted by grant.
- `workspace.status`: scoped identity, local work counts, explicitly separated
  local/synced/approval knowledge. Cached last-sync time is not fresh proof.
- `equipment.list`, `equipment.show` (`equipment_id`).
- `work.list`, `work.show` (`job_id`): frozen work context, safe draft projection
  and immutable known decisions; no raw Automerge document bytes.
- `procedures.list`, `procedures.show` (`procedure_id`): published checklists
  referenced by accessible jobs and their provenance. There is no general manual
  repository in this slice; do not claim full hosted MCP parity.
- `history.list`: optional `job_id`, only accessible immutable submitted/decided
  records with sanitized inspection values/context and local evidence status.
- `proposals.list`, `proposals.show` (`proposal_id`).
- `proposals.create`: only `inspection.notes` initially; no direct inspection
  edit, submission, decision, publication, device/grant or billing command.

Collection args permit `limit` (1..100, default 25) and opaque `cursor`, plus
appropriate `job_id`/`equipment_id` filters. Pagination is scoped and bound to
the captured visible revision; stale cursors reject with `stale_context`.
Collection result shape: `{"items":[],"count":0,"next_cursor":null}`; count
is the returned-page count, not a grant-wide total. `meta.complete` is false
when a page is truncated, and `local_revision` derives only from scoped visible
data. Detail result shape:
`{"item":{}}`. Capabilities shape: `{"commands":[],"proposal_types":["inspection.notes"]}`.

Proposal create args:

```json
{"idempotency_key":"11111111-1111-4111-8111-111111111111","type":"inspection.notes","job_id":"job","expected_document_hash":"64-lowercase-hex","notes":"Suggested inspection notes"}
```

Idempotency keys are caller-supplied UUIDs; reads never mint durable operations.
Notes are suggested replacement text (nonempty, at most 10,000 characters), not
an applied append or replacement. Pin original frozen context/document hash and
actor/grant identity. Result detail has stable `proposal_id`, `type`, `job_id`,
`expected_document_hash`, `notes`, `status":"pending_human_review"`,
`requires_human_review":true`, `applied":false`, `created_at` and
`idempotency_key`; excludes credentials/native bytes. There is no apply/approve
command in v1 and no false claim that the existing UI already reviews proposals.

## Durable proposal and idempotency boundary

Use a separate private local proposal store under the actual opened workspace
root, serialized and flushed before success. Do not add a table/settings entry
silently to the strict reviewed database/recovery format. Proposals are excluded
from existing office backups and replication; state this limitation explicitly.
The grant provider is injectable with synthetic grants only in fixtures. No
production persistent credential issuer is introduced.

Key uniqueness is `(grant identity, idempotency_key)`. Freeze canonical request
payload plus proposal/result; exact authorized replay returns the same ID and
result across service restart, without another proposal. Changed payload under
same key rejects before writes. Authorization/expiry/revocation/scope checks
precede replay. For a new proposal, require current job/context and matching
expected exact document hash; stale context rejects without writes. Exact retry
returns the original pending proposal even if the job later changes, after
fresh authorization. No result says applied/submitted/synced/approved.

Reads capture a coherent serial store snapshot; use read-only progress/evidence
checks, not evidence status/publication or selected-job convenience mutation.
A late token mismatch rejects or retries conservatively. `synced.verified`
remains false unless an actual current whole-job transfer proof is supplied by
a reviewed adapter; reading lastCompleteSync does not supply that proof.
Known office receipts remain historical exact-version decisions.

## Synthetic acceptance

Use actual isolated company/equipment/checklist/job/native SQLite fixtures and
real Unix transport, not a fake SQL data dictionary. Check collection/detail
filters and no cross-scope/private leakage; missing/expired/revoked/denied grants;
unsupported commands/fields/versions; exact replay/restart, changed-key payload,
stale context and concurrent duplicate proposals; denied/revoked replay; malformed
and oversized JSON; photo completeness read-only; no LabStore mutations or
approval/enrollment bypass; proposals excluded from strict existing backups.
Never launch against Garrett's running office/phone data. Existing raw-editor
recovery and multiworker collaboration are separate scopes.
