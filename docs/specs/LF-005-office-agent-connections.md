# LF-005 — Office agent connections

## Isolated base and scope

Checkout: `task-8/office-agent-connections`, branch
`codex/office-agent-connections`, base receipt
`ed79c4faaa014c0bfb6f514256ed2cea8f44472e`. The tested application tree is the
same as independently reviewed `7e9918c966cbdeed5894cd05f00aaefbf62d8d0d`.
That reviewed branch and its binaries remain frozen.

Implement normal Linux-office service lifecycle and connection management:
explicit enable/disable, truthful listener state, named grants with selected
equipment and jobs, finite expiry, one-time token display and revocation. The v1
CLI wire and permission-checked AgentService stay unchanged. Agent writes remain
pending notes suggestions. This builds code and synthetic acceptance; developers
must not create real persistent grants or alter Garrett's active workspace.

The current experimental authority is the office OS account in decision 0022.
Hosted MFA and hosted MCP remain their own rollback boundaries. No new production
identity claim is made by the desktop UI.

## Exclusive ownership and proposal handoff

The separate LF-004 proposal-review owner reserves:

- `lib/agent_service/proposal_review.dart`;
- `lib/ui/agent_proposals_page.dart`;
- `test/proposal_review_*` and `docs/specs/LF-004-agent-proposal-review.md`;
- the narrow `LabStore.reviewAgentNotes` command and review-receipt reader,
  including validated-edit preparation reuse;
- a validation-only `office_backup.dart` hunk for new authoritative event
  receipts, uniqueness and recovery semantics, without schema changes.

LF-005 does **not** edit those files/hunks. LF-005 owns new access scope/models,
grant store, host lifecycle and connections screen, their distinct tests and
this spec. The coordinator exclusively owns `app.dart` and office navigation
hooks in `workspace_page.dart`, including the LF-004 review entry point.
No worker edits LabStore, proposal storage, existing grants/service/transport,
CLI files or native/sync/approval code.

Pass the trusted canonical scope to LF-004:
`AgentProposalReviewer(store: store, workspaceId: host.scope!.workspaceId,
serviceDeviceId: store.device)`. The helper `AgentAccessScope.forOffice(store)`
is available without enabling connections or creating credentials. It returns
null for phones and unprepared company workspaces. Its workspace ID is `ws-`
plus the canonical SHA-256 of application, saved company ID and saved office
device ID. Those IDs survive coherent office restoration; authorization does
not. Foreign scopes are never inferred from proposal contents.

The original pending-create response and exact retries stay immutable. Human
review writes its separate authoritative event receipt. LF-004 recovery
validation may retain older scope identity as historical evidence; restoring a
backup does not recreate agent capabilities or pending private sidecars.

## Shared implementation seams

Pure Dart `access_scope.dart` and `access_models.dart` are coordinator-owned.
Grant module: `OfficeAgentGrantStore.open(workspaceRoot:, scope:, now:)`,
`enabled()`, `setEnabled(bool)`, `list()`, `issue(AgentGrantRequest)`,
`revoke(String grantId)`, `close()`, and `GrantProvider.resolve(token)`.
Use `agent-access-v1` beneath the actual opened workspace root, with private
ordinary owner-controlled files. Store only a digest of each cryptographically
random token. Reads revalidate current persisted state, expiry and revocation.
Invalid/corrupt/foreign sidecars fail closed and are retained for recovery.
No database table/settings or generic backup inclusion is added.

Host module: `OfficeAgentHost(store:, runtimeDirectory:, now:)`,
`initialize()`, `enable()`, `disable()`, `reload()`,
`issue(AgentGrantRequest)`, `revoke(String)`, `close()`;
getters `store`, `scope`, `snapshot`, `grants` (current immutable summaries),
and `changes` (a broadcast Stream<void>). `runtimeDirectory` is optional and
injectable for synthetic tests. Constructors have no access side effects.

Fresh workspaces start disabled; only a durably saved explicit enable action
allows reopen to resume. Disabled sessions deny requests immediately, before
waiting for durable handlers/socket shutdown. Already committed proposals are
retained; absent replies remain uncertain and must use the same operation ID.
Stop/drain the old host before changing/closing a store on restoration.

Finite grant expiry is at most seven days. Always pin explicit record sets:
empty job IDs grant no jobs, and newly created records do not broaden access.
The host validates selections against the current office catalog and rejects
jobs outside selected equipment. `allowNotes` adds only `proposals.create`.
No apply, approval, publication, grant or enrollment command is added.

Use the existing private Unix transport's frame/connection bounds. Refuse
foreign/unsafe runtime paths without chmod/unlink. Safe reopen must neither
delete another host's endpoint nor leak grant tokens. One host per workspace
is enforced within the process and across processes; child tests must exercise
abrupt exit and later reopening rather than claim a PID check is a lock.

UI: `AgentConnectionsPage(host:)`. Normal office navigation opens it; phones
have no connection-management entry. Show disabled/listening/unavailable,
expiry/revocation, selected scope and backup limitations truthfully. Show the
credential only in the explicit creation result and clipboard action; never
in ordinary lists, errors, telemetry or screenshots outside synthetic fixtures.

## Phases and acceptance

1. Commit ownership and canonical scope/model seams; independent store,
   lifecycle and UI owners implement disjoint files. Threat review is read-only.
2. Integrate their reviewed code and normal app lifecycle. Add independent
   adversarial tests for disable/revoke/expiry during queued work, malformed
   private state, duplicate starts, crash/reopen, scope/filter preservation and
   unchanged inspection/approval history.
3. Walk normal office navigation and grant creation/revocation at 1x and 2x
   text using synthetic data. Verify no phone management route. Combine the
   separately reviewed LF-004 slice only after its stable handoff.
4. Run full local maintenance/native/client gates and actual CLI acceptance,
   inspect rendered output and source-publication hygiene; independent review
   precedes a named-branch source push. Do not claim physical acceptance,
   hosted CI, installation or production conversion from synthetic results.

No policy blocker is needed for these code/synthetic boundaries. Real grant
provisioning, production personal identity, compromised-key recovery and
multi-office failover remain explicit future authorization/decisions.

## Follow-up review and integration

The independent architecture audit found two P2 defects at preserved `7e9918c`:
INT-AUDIT-001 (proposal durability flush bypass on exact retry) and INT-AUDIT-002
(clean editor submitting unseen stored fields). This branch owns their scoped
repairs. Original reproductions and reviewed checkpoints remain unchanged.
Proposal replay now confirms directory durability on every path before success;
post-publication uncertainty retains the accepted record. Editor repair must
preserve dirty intent and fence submission against the displayed native version.
Readiness/source push awaits the combined gates and independent recheck.

The P3 socket-path fix validates both actual bind and public paths in UTF-8
bytes. The private bind parent limit is 83 bytes; public transport limit is
107, while the CLI conservatively keeps its existing 100-byte public limit.
Normal host defaults use a short private runtime directory and a fresh endpoint
per start. Consumers copy the current settings after reopening; stale socket
entries are retained and never adopted or deleted as another host's address.

Prepared office initialization may create an empty disabled private config and
writer lease to enforce a single host. It creates no credentials or grants.
Constructors and phone/unprepared-company initialization have no access effects.
Grants never become broader when future equipment or jobs are created; equipment
context in v1 also requires an accessible selected inspection job.

LF-004's human-reviewed proposal copy lives in the authoritative event receipt
and is included in office recovery. The separate unreviewed proposal directory
and access sidecars remain excluded. Restored receipts prevent reapplication
even if a stale pending envelope is later recreated. Agents' immutable v1
proposal reads/retries retain the original creation envelope; use the office
review/history screen for current accept/reject decisions.

`scripts/local-maintenance.sh verify` additionally runs `agent-host-smoke`:
normal Node CLI subprocesses against real OfficeAgentHost enable/issue/revoke
code in a fresh guarded synthetic temporary workspace. This complements the
existing immutable service fixture; it never opens ordinary app storage.
