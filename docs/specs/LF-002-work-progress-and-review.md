# LF-002 — Current inspection work and exact review

Garrett authorized sustained local-first development on September 30. This
bounded increment continues the core company/equipment/checklist/inspection/
office-review/history/recovery/setup workflow. No production cutover, installation,
live import, public release, network-security change, inventory, billing,
multi-company sharing or automatic failover is authorized.

## Isolation and priorities

Base: receipt `b6d1c8d86950439be33921a2c4b6cf1638e71d95`, whose application source
is verified `45380ae6b093a400e8a5f589b19359fe822bfc28`. Parent's independent audit
passed against that immutable target. Worktree: `task-8/maintenance-progress`;
branch: `codex/maintenance-progress-slice`. The earlier maintenance checkout,
receipt, binaries, rollback and running physical workspaces stay untouched.

1. Current work versus immutable versions: fix job cards that still say approved
   after an offline saved edit, or prepared after recording an unsubmitted draft.
2. Focused office review and correction: expose undecided versions near work,
   preserve decided history, and open a returned job's correct current draft.
3. Next bounded candidates: recover interrupted raw editor drafts and author
   future checklist revisions without altering frozen jobs. Their concrete
   storage/publication semantics and acceptance will be inspected before edits.

## Architecture and read-only adapter contract

Add typed progress projections and a bulk snapshot reader outside widgets. Reuse
existing draft validation and evidence integrity checks; do not persist derived
workflow state. Do not edit `LabStore`, sync, approval, native code or backup
schema for this increment. The authoritative command/decision guards remain in
the reviewed runtime. Widget code renders projections and routes pinned job or
submission IDs; it does not invent approval policy.

Capture catalog context, every job's exact byte snapshot, submissions and receipts
under the existing serial queue. Decode those captured bytes, not an implicitly
selected document. Check evidence with `complete`, never `status` or partial-file
publication. A token derived from data relevant to the projection fences late
asynchronous results; selection alone does not invalidate another job's status.
The reader must not mutate documents, settings, events, history or evidence.

Represent draft phase (prepared/incomplete/ready/conflicted/unavailable), required
step progress, conflicts, local photo completeness and existing submission
problem. Separately represent exact-current-document submission records and
immutable historical decisions. Different bytes after edit/revert do not inherit
an earlier decision even if visible values match. Multiple device chains are not
globally ordered by revision or phone clock; ambiguous current records remain
explicit rather than selecting an invented latest authority.

Undecided old versions stay in office review so the coordinator can return them;
they are not silently discarded when a newer draft exists. Received command does
not mean complete photo or approvable current work. The existing exact review
guard remains decisive. Local receipt knowledge is historical, not fresh proof
that a restored office retains a newer decision; existing recovery warnings stay
visible.

## Acceptance and ownership

Runtime/projection worker owns new typed projection/reader modules and focused
unit tests. Workflow UI worker owns workspace/inspection/review integration and
new composed view widgets. Independent test worker owns new race/restart/history
regressions. Render worker owns a new ordinary workflow fixture at 412×915 and
1x/2x text. Workers use separate branches/worktrees; coordinator owns contracts,
integration, scope/version metadata, full gates and receipt.

Prove prepared/partial/complete drafts, approved and returned edit/revert,
queued restart, newer draft alongside older undecided review, two-job selection
and correct routing, optional/NA/no-meter/action rules, missing/conflicting
documents, complete versus partial/corrupt photos, late stale reads and unchanged
raw storage after repeated reads. Unchanged submission reports the existing
command/decision accurately; changed work extends its existing device/job chain.
Render normal entry → approved version → edit/save/back → draft + preserved
approval, and return → correct intended job → resubmit → pending review/history.

Run the full maintenance gate, isolation/domain guards, real rendered checks and
internal builds. Preserve source-versus-packaging receipt commits. Parent audits
each stable revision independently. No phone commands occur while Garrett uses
his phone; reconnecting USB later is not permission to install/reset or evidence
of network acceptance.

## Actual open gates and choices

Combined LF-001 source `45380ae` subsequently received independent PASS: both P2
findings closed, 78 focused checks, eight rendered cases and four capture-disabled
repeats passed; source/receipt trees, package hashes, identity and signer matched.
The independent gates must remain passing in this descendant. Physical gallery transfer,
exact approval, fresh-computer restore/reconfirmation and unassisted setup remain
unverified. Startup-failure recovery navigation and older-backup missing-decision
reconciliation need separately designed bounded flows; no phone receipt promotion
is permitted. Existing-company import, multi-coordinator failover, engine-cache
ownership and production identity compromise/rotation remain deferred choices.
